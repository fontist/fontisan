# frozen_string_literal: true

require "stringio"
require "digest/sha2"

module Fontisan
  module Woff2
    # Encodes a TTC/OTC font collection into WOFF2 collection format per
    # spec section 4.2.
    #
    # Output layout:
    #   [WOFF2Header (48 bytes, flavor = 'ttcf')]
    #   [TableDirectory]              # one entry per unique table
    #   [CollectionDirectory]         # CollectionHeader + N CollectionFontEntry
    #   [CompressedFontData]          # single brotli stream of all tables
    #
    # Each font references tables via indices in its CollectionFontEntry.
    # Identical tables across fonts share a single directory entry.
    #
    # Per spec section 5.5, glyf/loca pairs from the same font MUST be
    # adjacent (loca immediately follows glyf) in the directory.
    class CollectionEncoder
      TTC_FLAVOR = 0x74746366 # 'ttcf'

      # @param brotli_quality [Integer] 0-11
      def initialize(brotli_quality: 11)
        @brotli_quality = brotli_quality
      end

      # Encode an array of fonts as a WOFF2 collection.
      #
      # @param fonts [Array<TrueTypeFont, OpenTypeFont>] Source fonts
      # @return [String] WOFF2 collection binary
      def encode_fonts(fonts)
        raise ArgumentError, "fonts cannot be empty" if fonts.nil? || fonts.empty?

        prepared = fonts.map.with_index { |font, i| prepare_font(font, i) }
        _, font_to_ckeys = deduplicate(prepared)
        layout = build_layout(prepared, font_to_ckeys)
        compressed = compress_stream(layout)
        assemble(fonts:, layout:, font_to_ckeys:, compressed:)
      end

      private

      # Prepare a single font: collect tables, apply encoder rules, run
      # glyf/loca transform. Returns a Hash:
      #   {index:, tables: {tag ⇒ bytes}, loca_orig_length: (or nil)}
      def prepare_font(font, index)
        tables = {}
        font.table_names.each do |tag|
          data = font.table_data[tag]
          next unless data && !data.empty?

          tables[tag] = data
        end

        EncoderRules.apply!(tables)
        loca_orig_length = apply_glyf_loca_transform!(tables, font)

        { index:, tables:, loca_orig_length: }
      end

      # Apply the glyf/loca transform in place. Removes "loca" from
      # `tables`. Returns the original loca length, or nil if not applied.
      def apply_glyf_loca_transform!(tables, font)
        return nil unless tables.key?("glyf") && tables.key?("loca")

        maxp = font.table("maxp")
        head = font.table("head")
        return nil unless maxp && head

        loca_orig_length = tables["loca"].bytesize
        tables["glyf"] = GlyfLocaTransform.new(
          glyf_data: tables["glyf"],
          loca_data: tables["loca"],
          num_glyphs: maxp.num_glyphs,
          index_format: head.index_to_loc_format,
        ).transform
        tables.delete("loca")
        loca_orig_length
      end

      # Deduplicate identical tables across fonts. Returns:
      #   canonical: ckey → {tag, data}
      #   font_to_ckeys: Array (per font) of {tag ⇒ ckey}
      def deduplicate(prepared)
        canonical = {}
        font_to_ckeys = Array.new(prepared.size) { {} }
        seen = {} # "tag:sha256" → ckey

        prepared.each do |pf|
          pf[:tables].each do |tag, data|
            cache_key = "#{tag}:#{Digest::SHA256.digest(data)}"
            if (existing = seen[cache_key])
              font_to_ckeys[pf[:index]][tag] = existing
            else
              ckey = "#{tag}@#{pf[:index]}"
              canonical[ckey] = { tag:, data: }
              seen[cache_key] = ckey
              font_to_ckeys[pf[:index]][tag] = ckey
            end
          end
        end

        [canonical, font_to_ckeys]
      end

      # Walk fonts in order; for each font, walk tags in spec-mandated
      # order (glyf → loca placeholder → rest alphabetical). Each unique
      # ckey appears once in the layout.
      #
      # Loca placeholders are keyed by the glyf ckey they pair with, so
      # fonts that share a transformed glyf (via deduplication) also
      # share the loca placeholder. Per spec section 5.5, loca MUST
      # immediately follow glyf in the directory.
      def build_layout(prepared, font_to_ckeys)
        seen = {}
        entries = []

        prepared.each do |pf|
          tags = pf[:tables].keys
          ordered = order_tags_for_font(tags, has_loca: pf[:loca_orig_length])

          ordered.each do |tag|
            if tag == "loca_placeholder"
              # Handled below as part of the glyf branch.
              next
            end

            ckey = font_to_ckeys[pf[:index]][tag]
            unless seen[ckey]
              data = pf[:tables][tag]
              seen[ckey] = entries.size
              entries << {
                ckey:, tag:,
                data:,
                orig_length: data.bytesize,
                transform_length: (tag == "glyf" ? data.bytesize : nil)
              }
            end

            # loca placeholder immediately after glyf. Tied to glyf's ckey
            # so fonts that share a glyf also share its loca placeholder.
            if tag == "glyf" && pf[:loca_orig_length]
              placeholder_key = "loca_placeholder_for:#{ckey}"
              unless seen[placeholder_key]
                seen[placeholder_key] = entries.size
                entries << {
                  ckey: placeholder_key,
                  tag: "loca",
                  data: nil,
                  orig_length: pf[:loca_orig_length],
                  transform_length: 0,
                }
              end
            end
          end
        end

        entries
      end

      # Per-font tag order: glyf first, loca placeholder immediately after,
      # rest alphabetical. Spec section 5.5.
      def order_tags_for_font(tags, has_loca:)
        return tags.sort unless has_loca

        %w[glyf loca_placeholder] + (tags - ["glyf"]).sort
      end

      # Concatenate unique table data in directory order. Placeholder
      # entries (loca after transform) contribute 0 bytes per spec 5.3.
      def compress_stream(layout)
        combined = String.new(encoding: Encoding::BINARY)
        layout.each do |e|
          combined << e[:data] if e[:data]
        end
        Utilities::BrotliWrapper.compress(combined, quality: @brotli_quality)
      end

      def assemble(fonts:, layout:, font_to_ckeys:, compressed:)
        io = StringIO.new
        io.set_encoding(Encoding::BINARY)

        io.write("\x00" * 48) # reserve header
        layout.each { |e| write_table_directory_entry(io, e) }

        ckey_to_index = layout.each_with_index.to_h { |e, i| [e[:ckey], i] }
        write_collection_directory(io, fonts, font_to_ckeys, ckey_to_index)

        io.write(compressed)

        # Pad to a 4-byte boundary. The W3C reference decoder validates that
        # the file's `length` field matches the actual byte count, and many
        # decoders expect a 4-byte-aligned file length for collections.
        pad = (4 - (io.pos % 4)) % 4
        io.write("\x00" * pad) if pad.positive?
        total_size = io.size

        io.pos = 0
        write_header(io, num_tables: layout.size,
                         total_compressed_size: compressed.bytesize, total_size:)
        io.string
      end

      def write_header(io, num_tables:, total_compressed_size:, total_size:)
        io.write([Woff2::Woff2Header::SIGNATURE].pack("N"))
        io.write([TTC_FLAVOR].pack("N"))
        io.write([total_size].pack("N"))
        io.write([num_tables].pack("n"))
        io.write([0].pack("n"))
        io.write([0].pack("N"))                       # totalSfntSize (ref only)
        io.write([total_compressed_size].pack("N"))
        io.write([1].pack("n"))                       # majorVersion
        io.write([0].pack("n"))                       # minorVersion
        io.write([0].pack("N"))                       # metaOffset
        io.write([0].pack("N"))                       # metaLength
        io.write([0].pack("N"))                       # metaOrigLength
        io.write([0].pack("N"))                       # privOffset
        io.write([0].pack("N"))                       # privLength
      end

      def write_table_directory_entry(io, entry)
        dir_entry = Directory::Entry.new
        dir_entry.tag = entry[:tag]
        dir_entry.orig_length = entry[:orig_length]
        dir_entry.transform_length = entry[:transform_length]
        flags = dir_entry.calculate_flags
        io.write([flags].pack("C"))
        io.write(entry[:tag].ljust(4, "\x00")) unless dir_entry.known_tag?
        io.write(Directory.encode_uint_base128(entry[:orig_length]))
        return unless dir_entry.transformed?

        io.write(Directory.encode_uint_base128(entry[:transform_length] || 0))
      end

      def write_collection_directory(io, fonts, font_to_ckeys, ckey_to_index)
        # CollectionHeader
        io.write([0x00010000].pack("N")) # version 1.0
        io.write(encode_255_uint16(fonts.size))

        # One CollectionFontEntry per font
        fonts.each_with_index do |font, fi|
          font_keys = font_to_ckeys[fi]
          glyf_ckey = font_keys["glyf"]
          placeholder_key = glyf_ckey && "loca_placeholder_for:#{glyf_ckey}"
          has_placeholder = ckey_to_index.key?(placeholder_key)
          # CollectionFontEntry index list is in font's natural alphabetical
          # order (including "loca" if a placeholder exists). The glyf/loca
          # adjacency constraint applies to the table directory, not the
          # entry index list per spec section 5.5.
          ordered = font_keys.keys
          ordered << "loca" if has_placeholder
          ordered = ordered.sort

          io.write(encode_255_uint16(ordered.size))
          io.write([font_flavor(font)].pack("N"))
          ordered.each do |tag|
            ckey = font_keys[tag] || placeholder_key
            index = ckey_to_index.fetch(ckey)
            io.write(encode_255_uint16(index))
          end
        end
      end

      def font_flavor(font)
        if font.has_table?("CFF ") || font.has_table?("CFF2")
          Constants::SFNT_VERSION_OTTO
        else
          Constants::SFNT_VERSION_TRUETYPE
        end
      end

      def encode_255_uint16(value)
        if value < 253
          [value].pack("C")
        elsif value < 506
          [253, value - 253].pack("CC")
        elsif value < 65_536
          [254].pack("C") + [value].pack("n")
        else
          [255].pack("C") + [value - 506].pack("n")
        end
      end
    end
  end
end
