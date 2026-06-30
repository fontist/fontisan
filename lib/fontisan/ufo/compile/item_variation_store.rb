# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Shared builder for the ItemVariationStore structure used by
      # HVAR, MVAR, and other variation tables.
      #
      # The ItemVariationStore consists of:
      #   1. A VariationRegionList (defines axis regions)
      #   2. One or more ItemVariationData (delta sets per item)
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats
      module ItemVariationStore
        # @param axis_count [Integer]
        # @param master_count [Integer] number of masters (one region per master)
        # @param item_count [Integer] number of items (glyphs for HVAR, metrics for MVAR)
        # @param deltas [Array<Array<Integer>>] deltas[item][master] = delta value
        # @return [String] ItemVariationStore bytes
        def self.build(axis_count:, master_count:, item_count:, deltas:)
          # Build regions: one per master, each with peak=1.0 on its axis
          regions = build_regions(axis_count, master_count)
          region_list = serialize_region_list(regions, axis_count)

          # Build ItemVariationData: one data block covering all items
          var_data = serialize_variation_data(item_count, master_count, deltas)

          # Assemble the store
          # Header layout: format(uint16) + variationRegionListOffset(uint32)
          # + itemVariationDataCount(uint16) + itemVariationDataOffsets[1](uint32)
          #             = 2 + 4 + 2 + 4 = 12 bytes total before region list
          header_size = 8 # format(2) + regionListOffset(4) + itemVariationDataCount(2)
          offsets_array_size = 4 # one data block → one offset
          region_list_offset = header_size + offsets_array_size
          var_data_offset = region_list_offset + region_list.bytesize

          store = +""
          store << [1].pack("n")                    # format = 1
          store << [region_list_offset].pack("N")   # variationRegionListOffset
          store << [1].pack("n")                    # itemVariationDataCount
          store << [var_data_offset].pack("N")      # itemVariationDataOffsets[0]
          store << region_list
          store << var_data
          store
        end

        def self.build_regions(axis_count, master_count)
          Array.new(master_count) do |master_idx|
            Array.new(axis_count) do |axis_idx|
              if axis_idx == master_idx
                { start: -1.0, peak: 1.0, end: 1.0 }
              else
                { start: -1.0, peak: 0.0, end: 1.0 }
              end
            end
          end
        end

        def self.serialize_region_list(regions, axis_count)
          io = +""
          io << [axis_count].pack("n") # axisCount
          io << [regions.size].pack("n") # regionCount
          regions.each do |region|
            region.each do |coords|
              io << [f2dot14(coords[:start]), f2dot14(coords[:peak]), f2dot14(coords[:end])].pack("nnn")
            end
          end
          io
        end

        def self.serialize_variation_data(item_count, region_count, deltas)
          # Determine if all deltas fit in int8 (-128..127)
          all_short = deltas.flatten.any? { |d| !d.between?(-127, 127) }
          short_count = all_short ? region_count : 0

          io = +""
          io << [item_count].pack("n")     # itemCount
          io << [short_count].pack("n")    # shortDeltaCount
          io << [region_count].pack("n")   # regionIndexCount (all regions)
          region_count.times { |i| io << [i].pack("n") } # regionIndices

          deltas.each do |item_deltas|
            item_deltas.each_with_index do |delta, i|
              io << (i < short_count ? [delta].pack("s>") : [delta].pack("c"))
            end
          end

          io
        end

        def self.f2dot14(value)
          (value.to_f * 16384).to_i.clamp(-16384, 16384)
        end
        private_class_method :build_regions, :serialize_region_list,
                             :serialize_variation_data, :f2dot14
      end
    end
  end
end
