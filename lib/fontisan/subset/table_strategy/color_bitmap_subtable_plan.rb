# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Plan for one IndexSubTable emitted by [ColorBitmapSubsetter]:
      # a contiguous run of new GIDs at a single strike, with the
      # CBDT offsets and lengths needed to emit a format 1 IndexSubTable.
      class ColorBitmapSubtablePlan
        attr_reader :placements, :strike_ppem, :image_format

        def initialize(strike_ppem:, image_format:)
          @strike_ppem = strike_ppem
          @image_format = image_format
          @placements = []
        end

        def add(placement)
          @placements << placement
        end

        def first_new_gid
          @placements.first.new_gid
        end

        def last_new_gid
          @placements.last.new_gid
        end

        # Absolute CBDT offset where this subtable's first glyph's
        # bitmap begins. Assigned during CBDT emission.
        #
        # @return [Integer]
        def first_new_offset
          @placements.first.new_offset
        end

        # IndexSubTable format 1 offset array (relative to
        # imageDataOffset). offsets[0] is 0 (first glyph starts at
        # imageDataOffset); offsets[i+1] = offsets[i] + byte_length.
        #
        # @return [Array<Integer>]
        def offset_array
          arr = [0]
          @placements.each do |p|
            arr << (arr.last + p.byte_length)
          end
          arr
        end

        # Byte length of this IndexSubTable in the output CBLC:
        # 8-byte header + (count + 1) × 4-byte offsets.
        def byte_length
          8 + (@placements.size + 1) * 4
        end
      end
    end
  end
end
