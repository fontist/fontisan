# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `cmap` (character-to-glyph mapping) table.
      # Emits two subtables:
      #   - Format 4 (BMP), platform 3 encoding 1 (Windows Unicode BMP)
      #   - Format 12 (full Unicode), platform 3 encoding 10 (Windows Unicode full)
      #
      # Both subtables share the same segment list (capped to BMP for
      # format 4); format 4 is required by Windows even though format
      # 12 is more capable.
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cmap
      module Cmap
        PLATFORM_WINDOWS = 3
        ENCODING_WINDOWS_BMP = 1
        ENCODING_WINDOWS_FULL = 10

        # @param _font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] in gid order
        # @return [String] cmap table bytes
        def self.build(_font, glyphs:)
          mappings = {}
          glyphs.each_with_index do |glyph, gid|
            glyph.unicodes.each do |cp|
              mappings[cp] = gid unless mappings.key?(cp)
            end
          end

          subtable_bmp = format4_subtable(mappings.reject { |cp, _| cp > 0xFFFF })
          subtable_full = format12_subtable(mappings)

          header_size = 4 + (2 * 8) # version + numTables + 2 records
          offset_bmp = header_size
          offset_full = header_size + subtable_bmp.bytesize

          header = [0, 2].pack("nn")
          header << subtable_record(PLATFORM_WINDOWS, ENCODING_WINDOWS_BMP, offset_bmp)
          header << subtable_record(PLATFORM_WINDOWS, ENCODING_WINDOWS_FULL, offset_full)
          header + subtable_bmp + subtable_full
        end

        def self.subtable_record(platform_id, encoding_id, offset)
          [platform_id, encoding_id, offset].pack("nnN")
        end

        # Group adjacent (cp, gid) pairs into contiguous ranges where
        # both cp and gid advance by 1 each step.
        # @return [Array<Range>] Array of inclusive cp ranges
        def self.build_segments(cp_to_gid)
          sorted = cp_to_gid.sort
          return [] if sorted.empty?

          segments = []
          seg_start_cp, prev_gid = sorted.first
          prev_cp = seg_start_cp

          sorted[1..].each do |cp, gid|
            contiguous = cp == prev_cp + 1 && gid == prev_gid + 1
            unless contiguous
              segments << (seg_start_cp..prev_cp)
              seg_start_cp = cp
            end
            prev_cp = cp
            prev_gid = gid
          end
          segments << (seg_start_cp..prev_cp)
          segments
        end

        # Format 4 segment-encoded cmap subtable for the BMP.
        def self.format4_subtable(mappings)
          segments = build_segments(mappings) + [0xFFFF..0xFFFF] # sentinel
          seg_count = segments.size
          search_range = largest_pow2_le(seg_count) * 2
          entry_selector = (Math.log([1, search_range / 2].max) / Math.log(2)).to_i
          range_shift = seg_count * 2 - search_range

          end_codes = segments.map(&:end)
          start_codes = segments.map(&:begin)
          # id_delta[i] = (gid_at_start - start_code) mod 65536
          id_deltas = segments.map do |range|
            start_cp = range.begin
            gid = mappings.fetch(start_cp, 0)
            # For the sentinel segment (0xFFFF..0xFFFF) with no mapping,
            # delta 1 maps 0xFFFF → gid 0 (.notdef).
            gid_delta = start_cp == 0xFFFF && gid.zero? ? 1 : (gid - start_cp)
            gid_delta & 0xFFFF
          end

          body = +""
          body << [seg_count * 2, search_range, entry_selector, range_shift].pack("nnnn")
          body << end_codes.pack("n*")
          body << [0].pack("n") # reservedPad
          body << start_codes.pack("n*")
          body << id_deltas.pack("n*")
          body << Array.new(seg_count, 0).pack("n*") # idRangeOffset (all 0)

          length = 14 + body.bytesize # 14-byte header
          [4, length, 0].pack("nnn") + body
        end

        # Format 12 sparse-coverage subtable for full Unicode.
        def self.format12_subtable(mappings)
          segments = build_segments(mappings)

          body = +""
          segments.each do |range|
            start_gid = mappings.fetch(range.begin, 0)
            body << [range.begin, range.end, start_gid].pack("NNN")
          end

          length = 16 + body.bytesize # 16-byte header
          [12, 0].pack("nn") + [length, 0, segments.size].pack("NNN") + body
        end

        def self.largest_pow2_le(n)
          return 0 if n <= 0

          1 << (n.bit_length - 1)
        end
        private_class_method :subtable_record, :build_segments,
                             :format4_subtable, :format12_subtable,
                             :largest_pow2_le
      end
    end
  end
end
