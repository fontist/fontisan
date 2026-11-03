# frozen_string_literal: true

module Fontisan
  module Variation
    module Instancing
      # Evaluates HVAR advance-width deltas (ItemVariationStore plus the
      # optional DeltaSetIndexMap) at a normalized location.
      class ItemVariationStore
        # @param hvar [String] raw HVAR table
        def initialize(hvar)
          @hvar = hvar
          store_offset, @advance_map_offset = hvar[4, 8].unpack("NN")
          @store = hvar.byteslice(store_offset..)
          region_list_offset, data_count = @store[2, 6].unpack("Nn")
          @regions = parse_regions(region_list_offset)
          @data_offsets = @store[8, data_count * 4].unpack("N*")
        end

        # @return [Float] advance-width delta for +gid+
        def advance_delta(gid, coords)
          outer, inner = delta_index(gid)
          delta(outer, inner, coords)
        end

        private

        def parse_regions(offset)
          axis_count, region_count = @store[offset, 4].unpack("nn")
          Array.new(region_count) do |r|
            pos = offset + 4 + (r * axis_count * 6)
            @store[pos, axis_count * 6].unpack("s>*").map { |v| v / 16384.0 }
              .each_slice(3).to_a
          end
        end

        def delta_index(gid)
          return [0, gid] if @advance_map_offset.zero?

          format, entry_format = @hvar[@advance_map_offset, 2].unpack("CC")
          if format.zero?
            count = @hvar[@advance_map_offset + 2, 2].unpack1("n")
            pos = @advance_map_offset + 4
          else
            count = @hvar[@advance_map_offset + 2, 4].unpack1("N")
            pos = @advance_map_offset + 6
          end
          inner_bits = (entry_format & 0x0F) + 1
          size = ((entry_format & 0x30) >> 4) + 1
          entry_gid = [gid, count - 1].min
          entry = @hvar[pos + (entry_gid * size), size].bytes.inject(0) { |a, b| (a << 8) | b }
          [entry >> inner_bits, entry & ((1 << inner_bits) - 1)]
        end

        def delta(outer, inner, coords)
          offset = @data_offsets[outer]
          return 0.0 unless offset

          item_count, word_field, region_count = @store[offset, 6].unpack("nnn")
          return 0.0 if inner >= item_count

          long = word_field.anybits?(0x8000)
          word_count = word_field & 0x7FFF
          indexes = @store[offset + 6, region_count * 2].unpack("n*")
          big = long ? 4 : 2
          small = long ? 2 : 1
          row_size = (word_count * big) + ((region_count - word_count) * small)
          pos = offset + 6 + (region_count * 2) + (inner * row_size)
          words = @store[pos, word_count * big].unpack(long ? "l>*" : "s>*")
          rest = @store[pos + (word_count * big), (region_count - word_count) * small]
            .unpack(long ? "s>*" : "c*")
          (words + rest).each_with_index.sum do |d, i|
            d * region_scalar(@regions[indexes[i]], coords)
          end
        end

        def region_scalar(region, coords)
          scalar = 1.0
          region.each_with_index do |(lower, peak, upper), i|
            v = coords[i]
            next if peak.zero? || lower > peak || peak > upper
            next if lower.negative? && upper.positive?
            next if v == peak
            return 0.0 if v <= lower || upper <= v

            scalar *= v < peak ? (v - lower) / (peak - lower) : (upper - v) / (upper - peak)
          end
          scalar
        end
      end
    end
  end
end
