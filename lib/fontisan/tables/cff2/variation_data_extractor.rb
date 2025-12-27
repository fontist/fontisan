# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff2
      # Variation data extractor for CFF2 Variable Store
      #
      # Extracts regions and deltas from the Variable Store and provides
      # utilities for working with variation data.
      #
      # Reference: OpenType spec - Item Variation Store
      # Reference: Adobe Technical Note #5177 (CFF2)
      #
      # @example Extracting variation data
      #   extractor = VariationDataExtractor.new(variable_store)
      #   regions = extractor.regions
      #   deltas = extractor.deltas_for_item(item_index)
      class VariationDataExtractor
        # @return [Hash] Variable Store data
        attr_reader :variable_store

        # @return [Array<Hash>] Extracted regions
        attr_reader :regions

        # @return [Array<Hash>] Item variation data
        attr_reader :item_variation_data

        # Initialize extractor with Variable Store data
        #
        # @param variable_store [Hash] Variable Store from CFF2TableReader
        def initialize(variable_store)
          @variable_store = variable_store
          @regions = variable_store[:regions] || []
          @item_variation_data = variable_store[:item_variation_data] || []
        end

        # Get deltas for a specific item
        #
        # @param item_index [Integer] Item index
        # @param data_index [Integer] Item variation data index (default 0)
        # @return [Array<Integer>, nil] Deltas for the item, or nil if not found
        def deltas_for_item(item_index, data_index: 0)
          return nil if data_index >= @item_variation_data.size

          item_data = @item_variation_data[data_index]
          return nil if item_index >= item_data[:delta_sets].size

          item_data[:delta_sets][item_index]
        end

        # Get region indices for item variation data
        #
        # @param data_index [Integer] Item variation data index (default 0)
        # @return [Array<Integer>] Region indices
        def region_indices(data_index: 0)
          return [] if data_index >= @item_variation_data.size

          @item_variation_data[data_index][:region_indices] || []
        end

        # Get number of items in item variation data
        #
        # @param data_index [Integer] Item variation data index (default 0)
        # @return [Integer] Number of items
        def item_count(data_index: 0)
          return 0 if data_index >= @item_variation_data.size

          @item_variation_data[data_index][:item_count] || 0
        end

        # Get all deltas for all items
        #
        # @param data_index [Integer] Item variation data index (default 0)
        # @return [Array<Array<Integer>>] Array of delta sets
        def all_deltas(data_index: 0)
          return [] if data_index >= @item_variation_data.size

          @item_variation_data[data_index][:delta_sets] || []
        end

        # Calculate blended value for an item at specific coordinates
        #
        # @param item_index [Integer] Item index
        # @param base_value [Numeric] Base value to blend
        # @param scalars [Array<Float>] Region scalars for each region
        # @param data_index [Integer] Item variation data index (default 0)
        # @return [Float] Blended value
        def blend_value(item_index, base_value, scalars, data_index: 0)
          deltas = deltas_for_item(item_index, data_index: data_index)
          return base_value.to_f unless deltas

          indices = region_indices(data_index: data_index)

          # Apply blend: result = base + Σ(delta[i] * scalar[region_index[i]])
          result = base_value.to_f
          deltas.each_with_index do |delta, i|
            region_index = indices[i]
            next unless region_index

            scalar = scalars[region_index] || 0.0
            result += delta.to_f * scalar
          end

          result
        end

        # Get region by index
        #
        # @param region_index [Integer] Region index
        # @return [Hash, nil] Region data or nil if not found
        def region(region_index)
          return nil if region_index >= @regions.size

          @regions[region_index]
        end

        # Get number of regions
        #
        # @return [Integer] Total number of regions
        def region_count
          @regions.size
        end

        # Get number of axes from first region
        #
        # @return [Integer] Number of axes
        def axis_count
          return 0 if @regions.empty?

          @regions.first[:axis_count] || 0
        end

        # Check if Variable Store has data
        #
        # @return [Boolean] True if Variable Store contains data
        def has_data?
          !@regions.empty? && !@item_variation_data.empty?
        end

        # Extract all region coordinates as arrays
        #
        # Useful for debugging and validation
        #
        # @return [Array<Array<Hash>>] Array of regions with axis coordinates
        def region_coordinates
          @regions.map do |region|
            region[:axes].map do |axis|
              {
                start: axis[:start_coord],
                peak: axis[:peak_coord],
                end: axis[:end_coord]
              }
            end
          end
        end

        # Validate Variable Store structure
        #
        # @return [Array<String>] Array of validation errors (empty if valid)
        def validate
          errors = []

          # Check regions consistency
          if @regions.any?
            expected_axes = @regions.first[:axis_count]
            @regions.each_with_index do |region, i|
              unless region[:axis_count] == expected_axes
                errors << "Region #{i} has inconsistent axis_count: " \
                          "#{region[:axis_count]} vs #{expected_axes}"
              end

              unless region[:axes].size == expected_axes
                errors << "Region #{i} has #{region[:axes].size} axes, " \
                          "expected #{expected_axes}"
              end
            end
          end

          # Check item variation data
          @item_variation_data.each_with_index do |item_data, i|
            item_count = item_data[:item_count]
            delta_sets = item_data[:delta_sets]
            region_indices = item_data[:region_indices]

            unless delta_sets.size == item_count
              errors << "Item variation data #{i} has #{delta_sets.size} " \
                        "delta sets, expected #{item_count}"
            end

            # Check each delta set has correct number of deltas
            delta_sets.each_with_index do |deltas, j|
              unless deltas.size == region_indices.size
                errors << "Delta set #{j} in data #{i} has #{deltas.size} " \
                          "deltas, expected #{region_indices.size}"
              end
            end

            # Check region indices are valid
            region_indices.each_with_index do |idx, j|
              if idx >= @regions.size
                errors << "Region index #{idx} at position #{j} in data #{i} " \
                          "exceeds region count #{@regions.size}"
              end
            end
          end

          errors
        end
      end
    end
  end
end