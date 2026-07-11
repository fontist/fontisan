# frozen_string_literal: true

require "stringio"

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
        # Read an FDSelect subtable and return the flat FD-index array
        # (one entry per glyph).
        #
        # @param raw_data [String] full CFF2 table bytes
        # @param offset [Integer] byte offset of the FDSelect
        # @param num_glyphs [Integer] glyph count (from maxp)
        # @return [Array<Integer>] FD index per glyph
        def self.read(raw_data, offset, num_glyphs)
          io = StringIO.new(raw_data)
          io.seek(offset)
          format = io.read(1).unpack1("C")

          case format
          when 0 then read_format0(io, num_glyphs)
          when 3 then read_format3(io, num_glyphs)
          when 4 then read_format4(io, num_glyphs)
          else
            raise CorruptedTableError, "unsupported FDSelect format: #{format}"
          end
        end

        # Format 0: uint8 fd_index[numGlyphs]
        def self.read_format0(io, num_glyphs)
          io.read(num_glyphs).unpack("C*")
        end
        private_class_method :read_format0

        # Format 3: uint16 numRanges, Range3[], uint16 sentinel
        def self.read_format3(io, num_glyphs)
          num_ranges = io.read(2).unpack1("n")
          assignments = Array.new(num_glyphs, 0)
          ranges = Array.new(num_ranges) do
            first = io.read(2).unpack1("n")
            fd = io.read(1).unpack1("C")
            [first, fd]
          end
          sentinel = io.read(2).unpack1("n")

          ranges.each_cons(2) do |(first, fd), (next_first, _)|
            assignments.fill(fd, first, next_first - first)
          end
          if ranges.any?
            last_first, last_fd = ranges.last
            assignments.fill(last_fd, last_first, sentinel - last_first)
          end
          assignments
        end
        private_class_method :read_format3

        # Format 4: uint32 numRanges, Range4[], uint32 sentinel
        def self.read_format4(io, num_glyphs)
          num_ranges = io.read(4).unpack1("N")
          assignments = Array.new(num_glyphs, 0)
          ranges = Array.new(num_ranges) do
            first = io.read(4).unpack1("N")
            fd = io.read(2).unpack1("n")
            [first, fd]
          end
          sentinel = io.read(4).unpack1("N")

          ranges.each_cons(2) do |(first, fd), (next_first, _)|
            assignments.fill(fd, first, next_first - first)
          end
          if ranges.any?
            last_first, last_fd = ranges.last
            assignments.fill(last_fd, last_first, sentinel - last_first)
          end
          assignments
        end
        private_class_method :read_format4

        # @param assignments [Array<Integer>] FD index per glyph (length = numGlyphs)
        # @return [String] FDSelect bytes in the most compact format
        def self.build(assignments)
          return [0].pack("C").to_s + "".b if assignments.empty?

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
