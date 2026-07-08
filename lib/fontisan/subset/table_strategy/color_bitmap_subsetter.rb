# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Paired CBDT + CBLC subsetter.
      #
      # CBDT (Color Bitmap Data) and CBLC (Color Bitmap Location) are
      # tightly coupled: CBLC indexes glyph IDs to CBDT byte offsets,
      # and CBDT is just a blob of bitmap blocks. Subsetting requires
      # walking both at once — filtering to subset GIDs, copying the
      # retained bitmap blocks into a fresh CBDT, and rewriting CBLC's
      # IndexSubTable offsets to match.
      #
      # Both the Cbdt and Cblc strategies call into this collaborator,
      # which performs the work once and caches both byte strings. This
      # keeps the strategies themselves trivial and avoids forcing the
      # TableSubsetter to know about CBDT/CBLC ordering.
      #
      # The output CBLC keeps the source BitmapSize records verbatim
      # (ppem, metrics, glyph_range) and rewrites each IndexSubTable's
      # `imageDataOffset` and offset array to point into the new CBDT.
      # Glyph IDs are remapped via the supplied [GlyphMapping] so the
      # subset's CBLC references subset GIDs, not source GIDs.
      #
      # Output IndexSubTables always use format 1 (uint32 offsets) —
      # it has no alignment requirement, so arbitrary bitmap block
      # sizes from the source work without padding.
      #
      # Reference: OpenType CBDT/CBLC specifications.
      class ColorBitmapSubsetter
        # @return [String] new CBDT bytes (header + retained blocks)
        attr_reader :cbdt_bytes

        # @return [String] new CBLC bytes (header + BitmapSize + ISTA + IST)
        attr_reader :cblc_bytes

        # @param font [SfntFont]
        # @param mapping [GlyphMapping] old↔new GID map for the subset
        def initialize(font:, mapping:)
          @font = font
          @mapping = mapping
          @cbdt_bytes = +""
          @cblc_bytes = +""
        end

        # Build the subset CBDT + CBLC bytes. Idempotent.
        #
        # @return [self]
        def build
          return self if @built

          source_cblc = @font.table_data["CBLC"]
          source_cbdt = @font.table_data["CBDT"]

          if source_cblc.nil? || source_cbdt.nil?
            @built = true
            return self
          end

          cblc = Tables::Cblc.read(source_cblc)
          cbdt = Tables::Cbdt.read(source_cbdt)

          plan = ColorBitmapSubsetPlan.new(@mapping)
          plan.collect!(cblc)

          emit_cbdt(cbdt, plan)
          emit_cblc(cblc, plan)

          @built = true
          self
        end

        private

        # Emit CBDT: preserve the source 4-byte header, then concatenate
        # every retained bitmap block in (strike, gid) order. The
        # placement's new_offset is recorded so CBLC emission can
        # reference it.
        def emit_cbdt(cbdt, plan)
          @cbdt_bytes = String.new(encoding: Encoding::BINARY)
          @cbdt_bytes << cbdt.raw_data[0, 4] # majorVersion + minorVersion

          plan.each_placement do |placement|
            block = cbdt.bitmap_data_at(placement.source_offset,
                                        placement.byte_length)
            next unless block

            placement.new_offset = @cbdt_bytes.bytesize
            @cbdt_bytes << block
          end
        end

        # Emit CBLC: header + BitmapSize section + IndexSubTableArray
        # section + IndexSubTable records. The IndexSubTableArray entries
        # are grouped per strike; IndexSubTable records are appended
        # after all ISTA entries. Each IndexSubTable is format 1.
        def emit_cblc(cblc, plan)
          output = String.new(encoding: Encoding::BINARY)
          output << [Integer(cblc.version), plan.strikes.size].pack("NN")

          bitmap_size_section_end = output.bytesize + (plan.strikes.size * 48)
          ista_offsets = build_ista_offsets(plan, bitmap_size_section_end)
          ista_section_end = ista_offsets.last.to_i +
            (plan.strike_plans.sum(&:subtable_count) * 8)

          # BitmapSize records (patched array_offset + number_of_subtables).
          plan.strike_plans.each_with_index do |strike_plan, idx|
            output << patch_bitmap_size(strike_plan.source_strike,
                                        ista_offsets[idx],
                                        strike_plan.subtable_count)
          end

          # IndexSubTableArray entries (one per subtable plan).
          ist_cursor = ista_section_end
          plan.strike_plans.each_with_index do |strike_plan, idx|
            strike_ista_offset = ista_offsets[idx]
            strike_plan.subtable_plans.each do |sub|
              additional = ist_cursor - strike_ista_offset
              output << [sub.first_new_gid, sub.last_new_gid,
                         additional].pack("nnN")
              ist_cursor += sub.byte_length
            end
          end

          # IndexSubTable records (format 1).
          plan.each_strike_plan do |strike_plan|
            strike_plan.subtable_plans.each do |sub|
              output << build_index_sub_table(sub)
            end
          end

          @cblc_bytes = output
        end

        # Absolute CBLC offset of each survivor strike's IndexSubTableArray.
        # Each strike's ISTA is laid out right after the BitmapSize section
        # and the previous strikes' ISTA entries (8 bytes × subtable count).
        def build_ista_offsets(plan, bitmap_size_section_end)
          offsets = []
          cursor = bitmap_size_section_end
          plan.strike_plans.each do |sp|
            offsets << cursor
            cursor += sp.subtable_count * 8
          end
          offsets
        end

        # Clone a BitmapSize with patched `index_subtable_array_offset`
        # and `number_of_index_subtables`; everything else preserved
        # from the source.
        def patch_bitmap_size(source_strike, new_ista_offset, subtable_count)
          clone = Tables::CblcBitmapSize.new
          clone.index_subtable_array_offset = new_ista_offset
          clone.index_tables_size = source_strike.index_tables_size
          clone.number_of_index_subtables = subtable_count
          clone.color_ref = source_strike.color_ref
          clone.hori = source_strike.hori
          clone.vert = source_strike.vert
          clone.start_glyph_index = source_strike.start_glyph_index
          clone.end_glyph_index = source_strike.end_glyph_index
          clone.ppem_x = source_strike.ppem_x
          clone.ppem_y = source_strike.ppem_y
          clone.bit_depth = source_strike.bit_depth
          clone.flags = source_strike.flags
          clone.to_binary_s
        end

        # Format 1 IndexSubTable: 8-byte header + uint32 offsetArray[count+1].
        # imageDataOffset = absolute new CBDT offset of the first glyph's
        # bitmap. offsets[i] = relative offset from imageDataOffset for
        # glyph i.
        def build_index_sub_table(sub)
          bytes = String.new(encoding: Encoding::BINARY)
          bytes << [1, sub.image_format, sub.first_new_offset].pack("nnN")
          bytes << sub.offset_array.pack("N*")
          bytes
        end
      end
    end
  end
end
