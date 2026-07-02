# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff2
      # Builds the FDSelect subtable for CFF2, mapping glyph IDs to
      # Font DICT indices.
      #
      # Three formats:
      #   0 — flat array: one byte per glyph
      #   3 — range-based (compact for clustered FDs, ≤65,534 glyphs)
      #   4 — range-based with uint32 (for >65,534 glyphs)
      #
      # For single-FD fonts (all glyphs share one Font DICT), FDSelect
      # is omitted entirely — the CFF2 Top DICT's FontDICTSelectOffset
      # is left unset.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cff2
      class FdSelect
        # @param assignments [Array<Integer>] FD index per glyph (length = numGlyphs)
        # @return [String] FDSelect bytes in the most compact format
        def self.build(assignments)
          return 0.to_s if assignments.empty?

          format0_bytes(assignments)
        end

        # Format 0: simple byte array. Best for random FD assignments.
        #   uint8 format (= 0)
        #   uint8 fontDICTIDs[numGlyphs]
        def self.format0_bytes(assignments)
          ([0] + assignments).pack("C*")
        end

        # Format 3: range-based. Best for clustered FD assignments.
        #   uint8 format (= 3)
        #   uint16 numRanges
        #   Range3[numRanges]: { uint16 first, uint8 fontDICTID }
        #   uint16 sentinel (= numGlyphs)
        def self.format3_bytes(assignments)
          ranges = build_ranges(assignments)

          io = +""
          io << [3, ranges.size].pack("Cn")
          ranges.each { |first, fd| io << [first, fd].pack("nC") }
          io << [assignments.size].pack("n")
          io
        end

        # Build range records from a flat FD assignment array.
        # Returns [[first_gid, fd_index], ...] with the first entry
        # always starting at gid 0.
        def self.build_ranges(assignments)
          ranges = []
          current_fd = nil
          assignments.each_with_index do |fd, gid|
            if fd != current_fd
              ranges << [gid, fd]
              current_fd = fd
            end
          end
          ranges
        end

        private_class_method :build_ranges
      end
    end
  end
end
