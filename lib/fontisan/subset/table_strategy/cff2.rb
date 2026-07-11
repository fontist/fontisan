# frozen_string_literal: true

require "stringio"

module Fontisan
  module Subset
    module TableStrategy
      # CFF2 (Compact Font Format 2) subsetter strategy.
      #
      # Subsets CFF2 tables by filtering the CharStrings INDEX and FDSelect
      # to the subset glyphs, then rebuilding the table with patched offsets.
      # The Variable Store (ItemVariationStore) is preserved unchanged —
      # its `vsindex` references in charstrings remain valid because
      # charstrings are carried as opaque bytes.
      #
      # Unlike the CFF1 subsetter (which routes through UFO), CFF2 uses a
      # standalone binary filter because CFF2 charstrings carry blend/vsindex
      # operators for variation that the UFO round-trip would strip.
      #
      # Layout of the rebuilt table:
      #
      #   Header (5 bytes)
      #   Top DICT               (offsets patched to new positions)
      #   Global Subr INDEX      (preserved as-is)
      #   [Variable Store]       (preserved as-is, if present)
      #   [FDArray INDEX]        (Private DICT offsets patched)
      #   [Private DICTs]        (preserved as-is, relocated after FDArray)
      #   [FDSelect]             (filtered to subset glyphs, if present)
      #   CharStrings INDEX      (filtered to subset glyphs)
      #
      # Private DICT offsets in Font DICTs always use the 5-byte integer
      # encoding (operator 29 + int32). This makes the FDArray byte size
      # independent of the offset values, breaking the layout chicken-and-egg.
      #
      # See TODO #15 for the full design rationale.
      class Cff2
        # CFF2 Top DICT operator codes (per Adobe TN 5177 §8.1).
        OP_CHARSTRINGS = 17
        OP_VSTORE = 24
        OP_FDARRAY = [12, 36].freeze
        OP_FDSELECT = [12, 37].freeze
        OP_PRIVATE = 18

        MAX_TOPDICT_ITERATIONS = 16

        # @param context [SubsetContext]
        # @param tag [String] "CFF2"
        # @param table [Object] parsed CFF2 table (unused — we read raw bytes)
        # @return [String] subset CFF2 table bytes
        def self.call(context:, tag:, table:)
          raw = raw_bytes_from_font(context.font) || raw_bytes_from_table(table)
          return raw unless raw && !raw.empty?

          new(raw, context.mapping).subset
        end

        def self.raw_bytes_from_font(font)
          t = font.table("CFF2") if font.respond_to?(:table)
          t&.raw_data
        end
        private_class_method :raw_bytes_from_font

        def self.raw_bytes_from_table(table)
          table&.raw_data if table.respond_to?(:raw_data)
        end
        private_class_method :raw_bytes_from_table

        # ------------------------------------------------------------------

        def initialize(raw_data, mapping)
          @raw = raw_data
          @mapping = mapping
          @reader = Tables::Cff2::TableReader.new(raw_data)
          @reader.read_top_dict
        end

        # Build the subset CFF2 table.
        #
        # @return [String]
        def subset
          sections = gather_sections
          retained_gids = @mapping.old_ids.sort

          filtered = build_filtered_sections(sections, retained_gids)
          layout = converge_layout(sections, filtered)
          write_table(layout, filtered)
        end

        # ------------------------------------------------------------------
        # Source section gathering
        # ------------------------------------------------------------------

        def gather_sections
          td = @reader.top_dict
          hdr = @reader.header
          gsubr_off = hdr[:header_size] + hdr[:top_dict_length]

          {
            header_size: hdr[:header_size],
            charstrings: read_index(td[OP_CHARSTRINGS]),
            gsubr: read_index(gsubr_off),
            fdarray: td[OP_FDARRAY] ? read_index(td[OP_FDARRAY]) : nil,
            fdselect_offset: td[OP_FDSELECT],
            vstore_offset: td[OP_VSTORE],
          }
        end

        def read_index(offset)
          Tables::Cff2::Index.read(@raw, offset)
        end

        # ------------------------------------------------------------------
        # Section filtering
        # ------------------------------------------------------------------

        # Build all filtered/rebuilt section bytes.
        def build_filtered_sections(sections, retained_gids)
          {
            charstrings_bytes: filter_charstrings(sections[:charstrings], retained_gids),
            fdselect_bytes: filter_fdselect(sections, retained_gids),
            fdarray_entries: sections[:fdarray] ? parse_fdarray_entries(sections[:fdarray]) : [],
          }
        end

        # Build a new CharStrings INDEX containing only the retained glyphs.
        def filter_charstrings(source_cs, retained_gids)
          items = retained_gids.map do |gid|
            item = source_cs[gid]
            item.nil? || item.empty? ? "\x0e".b : item
          end
          Tables::Cff2::IndexBuilder.build(items)
        end

        # Rebuild FDSelect to cover only retained glyphs in their new order.
        def filter_fdselect(sections, retained_gids)
          return nil unless sections[:fdselect_offset]

          assignments = Tables::Cff2::FdSelect.read(
            @raw, sections[:fdselect_offset], sections[:charstrings].count
          )
          new_assigns = retained_gids.map { |gid| assignments[gid] || 0 }
          Tables::Cff2::FdSelect.build(new_assigns)
        end

        # Parse each Font DICT in the FDArray, extract Private DICT bytes,
        # and prepare entries for relocation.
        def parse_fdarray_entries(source_fdarray)
          source_fdarray.to_a.map do |fd_bytes|
            parsed = @reader.parse_dict(fd_bytes)
            priv = parsed[OP_PRIVATE]
            entry = { parsed: parsed, priv_bytes: nil, priv_size: nil }
            next entry unless priv.is_a?(Array) && priv.size == 2

            size, offset = priv
            entry[:priv_bytes] = @raw.byteslice(offset, size)
            entry[:priv_size] = size
            entry
          end
        end

        # Build the FDArray INDEX bytes with the given Private DICT offsets.
        # Private offsets always use 5-byte int32 encoding for deterministic
        # sizing across layout iterations.
        def build_fdarray_bytes(entries, priv_offsets)
          rebuilt = entries.each_with_index.map do |entry, idx|
            parsed = entry[:parsed].dup
            if entry[:priv_size]
              parsed[OP_PRIVATE] = [entry[:priv_size], priv_offsets[idx] || 0]
            end
            encode_font_dict(parsed)
          end
          Tables::Cff2::IndexBuilder.build(rebuilt)
        end

        # ------------------------------------------------------------------
        # Layout convergence
        # ------------------------------------------------------------------

        # Iterate Top DICT encoding to stability, then produce the final
        # layout with FDArray patched with concrete Private DICT offsets.
        def converge_layout(sections, filtered)
          top_dict_size = @reader.header[:top_dict_length]
          placeholder_offsets = Array.new(filtered[:fdarray_entries].size, 0)
          fdarray_placeholder = if filtered[:fdarray_entries].any?
                                  build_fdarray_bytes(filtered[:fdarray_entries],
                                                      placeholder_offsets)
                                end
          priv_bytes = filtered[:fdarray_entries].map { |e| e[:priv_bytes] }.compact

          prev_size = nil
          layout = nil
          MAX_TOPDICT_ITERATIONS.times do
            layout = layout_offsets(sections, top_dict_size, filtered,
                                    fdarray_placeholder, priv_bytes)
            new_td = build_top_dict_bytes(layout)
            top_dict_size = new_td.bytesize
            break if top_dict_size == prev_size

            prev_size = top_dict_size
          end

          finalize_layout(layout, sections, top_dict_size, filtered,
                          fdarray_placeholder, priv_bytes)
        end

        # Assign byte offsets to every section.
        def layout_offsets(sections, top_dict_size, filtered, fdarray_bytes, priv_bytes)
          pos = sections[:header_size] + top_dict_size
          layout = { top_dict_size: top_dict_size }

          layout[:global_subrs_offset] = pos
          layout[:global_subrs_bytes] = index_bytes(sections[:gsubr])
          pos += layout[:global_subrs_bytes].bytesize

          if sections[:vstore_offset]
            layout[:vstore_offset] = pos
            layout[:vstore_bytes] = vstore_bytes(sections[:vstore_offset])
            pos += layout[:vstore_bytes].bytesize
          end

          if fdarray_bytes
            layout[:fdarray_offset] = pos
            layout[:fdarray_bytes] = fdarray_bytes
            pos += fdarray_bytes.bytesize

            priv_offsets = priv_bytes.map do |pb|
              off = pos
              pos += pb.bytesize
              off
            end
            layout[:private_dict_offsets] = priv_offsets
            layout[:private_dicts] = priv_bytes
          end

          if filtered[:fdselect_bytes]
            layout[:fdselect_offset] = pos
            layout[:fdselect_bytes] = filtered[:fdselect_bytes]
            pos += layout[:fdselect_bytes].bytesize
          end

          layout[:charstrings_offset] = pos
          layout[:charstrings_bytes] = filtered[:charstrings_bytes]
          layout
        end

        # Build the Top DICT bytes with updated section offsets.
        def build_top_dict_bytes(layout)
          td = @reader.top_dict.dup
          td[OP_CHARSTRINGS] = layout[:charstrings_offset]
          td[OP_VSTORE] = layout[:vstore_offset] if layout[:vstore_offset]
          td[OP_FDARRAY] = layout[:fdarray_offset] if layout[:fdarray_offset]
          td[OP_FDSELECT] = layout[:fdselect_offset] if layout[:fdselect_offset]
          encode_dict(td)
        end

        # Produce the final layout: stabilized Top DICT bytes, header,
        # and FDArray rebuilt with concrete Private DICT offsets.
        def finalize_layout(layout, sections, top_dict_size, filtered,
                            fdarray_placeholder, priv_bytes)
          final = layout.dup
          final[:top_dict_bytes] = build_top_dict_bytes(layout)
          final[:header_bytes] = Tables::Cff2::Header.build(
            top_dict_size: top_dict_size,
          )
          if filtered[:fdarray_entries].any?
            final[:fdarray_bytes] = build_fdarray_bytes(
              filtered[:fdarray_entries], final[:private_dict_offsets] || []
            )
          end
          final
        end

        # ------------------------------------------------------------------
        # Table serialization
        # ------------------------------------------------------------------

        def write_table(layout, filtered)
          io = StringIO.new(+"")
          io << layout[:header_bytes]
          io << layout[:top_dict_bytes]
          io << layout[:global_subrs_bytes]
          io << layout[:vstore_bytes] if layout[:vstore_bytes]
          io << layout[:fdarray_bytes] if layout[:fdarray_bytes]
          (layout[:private_dicts] || []).each { |pd| io << pd }
          io << layout[:fdselect_bytes] if layout[:fdselect_bytes]
          io << layout[:charstrings_bytes]
          io.string
        end

        # ------------------------------------------------------------------
        # Binary helpers
        # ------------------------------------------------------------------

        # Extract the raw bytes of a parsed INDEX from the source table.
        def index_bytes(index)
          @raw.byteslice(index.start_offset, index.total_size)
        end

        # Extract VStore bytes by computing its byte extent.
        def vstore_bytes(vstore_offset)
          size = vstore_extent(vstore_offset)
          @raw.byteslice(vstore_offset, size)
        end

        # Compute the byte size of an ItemVariationStore.
        def vstore_extent(vs_off)
          io = StringIO.new(@raw)
          io.seek(vs_off)
          _format = read_u16(io)
          region_list_off = read_u32(io)
          data_count = read_u16(io)
          data_offsets = Array.new(data_count) { read_u32(io) }

          extents = []
          extents << region_list_end(vs_off + region_list_off) if region_list_off.positive?
          data_offsets.each do |rel_off|
            extents << item_variation_data_end(vs_off + rel_off) if rel_off.positive?
          end
          end_off = extents.max || (8 + (data_count * 4))
          end_off - vs_off
        end

        def region_list_end(abs_off)
          io = StringIO.new(@raw)
          io.seek(abs_off)
          axis_count = read_u16(io)
          region_count = read_u16(io)
          abs_off + 4 + (region_count * axis_count * 6)
        end

        def item_variation_data_end(abs_off)
          io = StringIO.new(@raw)
          io.seek(abs_off)
          item_count = read_u16(io)
          short_delta_count = read_u16(io)
          region_index_count = read_u16(io)
          long_count = region_index_count - short_delta_count
          delta_set_size = (short_delta_count * 2) + long_count
          abs_off + 6 + (region_index_count * 2) + (item_count * delta_set_size)
        end

        def read_u16(io)
          io.read(2).unpack1("n")
        end

        def read_u32(io)
          io.read(4).unpack1("N")
        end

        # ------------------------------------------------------------------
        # DICT encoding
        # ------------------------------------------------------------------

        # Encode a DICT hash to binary using the CFF2 DictEncoder.
        def encode_dict(dict)
          io = +""
          dict.each do |operator, operands|
            vals = Array(operands)
            vals.each do |v|
              io << Tables::Cff2::DictEncoder.encode_integer(v.to_i)
            end
            io << Tables::Cff2::DictEncoder.encode_operator(operator)
          end
          io
        end

        # Encode a Font DICT. The Private operator (18) always uses 5-byte
        # integer encoding for BOTH operands so the Font DICT byte size
        # is deterministic across layout iterations.
        def encode_font_dict(parsed)
          io = +""
          parsed.each do |operator, operands|
            vals = Array(operands)
            if operator == OP_PRIVATE && vals.size == 2
              io << encode_int32(vals[0].to_i)
              io << encode_int32(vals[1].to_i)
            else
              vals.each { |v| io << Tables::Cff2::DictEncoder.encode_integer(v.to_i) }
            end
            io << Tables::Cff2::DictEncoder.encode_operator(operator)
          end
          io
        end

        # 5-byte integer encoding: byte 29 (marker) + 4-byte big-endian.
        def encode_int32(value)
          [29, value].pack("CN")
        end
      end
    end
  end
end
