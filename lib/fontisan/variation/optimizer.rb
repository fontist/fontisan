# frozen_string_literal: true

require_relative "../optimizers/pattern_analyzer"
require_relative "../optimizers/subroutine_optimizer"

module Fontisan
  module Variation
    # Optimizes CFF subroutines for variable fonts
    #
    # This class analyzes CharStrings in CFF2 variable fonts and optimizes
    # blend operations by extracting common blend sequences into subroutines,
    # deduplicating variation regions, and minimizing ItemVariationStore data.
    #
    # Optimization strategies:
    # 1. Blend pattern extraction - Find repeating blend sequences
    # 2. Region deduplication - Merge identical variation regions
    # 3. ItemVariationStore optimization - Compact delta storage
    # 4. Subroutine reordering - Place frequent blends in low IDs
    #
    # @example Optimizing a variable font
    #   optimizer = Fontisan::Variation::Optimizer.new(cff2_table)
    #   optimized = optimizer.optimize
    #   # => Optimized CFF2 table with reduced file size
    #
    # @see docs/SUBROUTINE_ARCHITECTURE.md
    # @see docs/CFF2_ARCHITECTURE.md
    class Optimizer
      # @return [CFF2] CFF2 table being optimized
      attr_reader :cff2

      # @return [Hash] Optimization statistics
      attr_reader :stats

      # Initialize optimizer
      #
      # @param cff2 [CFF2] CFF2 table with blend operators
      # @param options [Hash] Optimization options
      # @option options [Integer] :max_subrs Maximum subroutines (default: 65535)
      # @option options [Float] :region_threshold Region similarity threshold (default: 0.001)
      # @option options [Boolean] :deduplicate_regions Enable region deduplication (default: true)
      def initialize(cff2, options = {})
        @cff2 = cff2
        @options = {
          max_subrs: 65535,
          region_threshold: 0.001,
          deduplicate_regions: true,
        }.merge(options)

        @stats = {
          original_size: 0,
          optimized_size: 0,
          blend_patterns_found: 0,
          subroutines_created: 0,
          regions_deduplicated: 0,
        }
      end

      # Optimize CFF2 table
      #
      # Performs all optimization passes and returns optimized table.
      #
      # @return [CFF2] Optimized CFF2 table
      def optimize
        @stats[:original_size] = estimate_table_size(@cff2)

        # Step 1: Analyze blend patterns across all CharStrings
        blend_patterns = analyze_blend_patterns

        # Step 2: Extract common blend sequences into subroutines
        subroutines = extract_blend_subroutines(blend_patterns)

        # Step 3: Deduplicate variation regions
        deduplicate_regions if @options[:deduplicate_regions]

        # Step 4: Optimize ItemVariationStore
        optimize_item_variation_store

        # Step 5: Rebuild CharStrings with subroutine calls
        rebuild_charstrings(subroutines)

        @stats[:optimized_size] = estimate_table_size(@cff2)
        @stats[:savings_percent] = calculate_savings_percent

        @cff2
      end

      # Analyze blend patterns in CharStrings
      #
      # Scans all CharStrings to find repeating blend operator sequences
      # that can be extracted into subroutines.
      #
      # @return [Array<BlendPattern>] Identified blend patterns
      def analyze_blend_patterns
        patterns = []
        glyph_count = @cff2.glyph_count

        glyph_count.times do |glyph_id|
          charstring = @cff2.charstring(glyph_id)
          next unless charstring

          # Extract blend operator sequences
          blend_sequences = extract_blend_sequences(charstring)
          patterns.concat(blend_sequences)
        end

        # Group identical patterns
        grouped = group_patterns(patterns)
        @stats[:blend_patterns_found] = grouped.length

        grouped
      end

      # Extract blend sequences from CharString
      #
      # @param charstring [String] Binary CharString data
      # @return [Array<BlendPattern>] Blend patterns found
      def extract_blend_sequences(charstring)
        patterns = []
        operators = parse_charstring_operators(charstring)

        operators.each_with_index do |op, index|
          next unless blend_operator?(op)

          # Extract blend and surrounding context
          pattern = extract_pattern_context(operators, index)
          patterns << pattern if pattern
        end

        patterns
      end

      # Extract common blend sequences into subroutines
      #
      # @param patterns [Array<BlendPattern>] Blend patterns
      # @return [Array<Subroutine>] Created subroutines
      def extract_blend_subroutines(patterns)
        # Filter patterns by frequency and savings
        candidates = patterns.select do |pattern|
          pattern[:frequency] >= 2 && pattern[:savings].positive?
        end

        # Convert patterns to format expected by SubroutineOptimizer
        # The optimizer expects objects with methods, but we have hashes
        # For now, just select and order them directly
        selected = candidates.sort_by { |p| -p[:savings] }
          .take(@options[:max_subrs])

        # Order by frequency for efficient encoding
        ordered = selected.sort_by { |p| -p[:frequency] }

        @stats[:subroutines_created] = ordered.length
        ordered
      end

      # Deduplicate variation regions
      #
      # Merges regions that are functionally identical (within threshold).
      def deduplicate_regions
        return unless @cff2.variation_store

        regions = @cff2.variation_store.region_list
        original_count = regions.length

        # Find duplicate regions
        unique_regions = []
        region_mapping = {}

        regions.each_with_index do |region, index|
          # Check if region matches any existing unique region
          match_index = find_matching_region(region, unique_regions)

          if match_index
            region_mapping[index] = match_index
          else
            region_mapping[index] = unique_regions.length
            unique_regions << region
          end
        end

        # Update references in ItemVariationStore
        update_region_references(region_mapping) if regions.length > unique_regions.length

        @cff2.variation_store.region_list = unique_regions
        @stats[:regions_deduplicated] = original_count - unique_regions.length
      end

      # Find matching region within threshold
      #
      # @param region [RegionAxisCoordinates] Region to match
      # @param unique_regions [Array<RegionAxisCoordinates>] Existing unique regions
      # @return [Integer, nil] Index of matching region or nil
      def find_matching_region(region, unique_regions)
        unique_regions.each_with_index do |unique, index|
          return index if regions_match?(region, unique)
        end
        nil
      end

      # Check if two regions match within threshold
      #
      # @param r1 [RegionAxisCoordinates] First region
      # @param r2 [RegionAxisCoordinates] Second region
      # @return [Boolean] True if regions match
      def regions_match?(r1, r2)
        return false unless r1.axis_count == r2.axis_count

        r1.axis_count.times do |i|
          coords1 = r1.region_axes[i]
          coords2 = r2.region_axes[i]

          # Compare start, peak, end coordinates
          return false unless coords_similar?(coords1.start_coord,
                                              coords2.start_coord)
          return false unless coords_similar?(coords1.peak_coord,
                                              coords2.peak_coord)
          return false unless coords_similar?(coords1.end_coord,
                                              coords2.end_coord)
        end

        true
      end

      # Check if coordinates are similar within threshold
      #
      # @param c1 [Float] First coordinate
      # @param c2 [Float] Second coordinate
      # @return [Boolean] True if similar
      def coords_similar?(c1, c2)
        (c1 - c2).abs <= @options[:region_threshold]
      end

      # Optimize ItemVariationStore
      #
      # Compacts delta storage by removing unused data and optimizing encoding.
      def optimize_item_variation_store
        return unless @cff2.variation_store

        store = @cff2.variation_store

        # Remove unused variation data
        compact_variation_data(store)

        # Optimize delta encoding (use shortest representation)
        optimize_delta_encoding(store)
      end

      # Compact variation data by removing unused entries
      #
      # @param store [ItemVariationStore] Variation store
      def compact_variation_data(store)
        # Identify used variation indices from CharStrings
        used_indices = collect_used_variation_indices

        # Remove unused data
        store.item_variation_data.each do |data|
          data.compact_unused(used_indices)
        end
      end

      # Optimize delta encoding for efficiency
      #
      # @param store [ItemVariationStore] Variation store
      def optimize_delta_encoding(store)
        store.item_variation_data.each(&:optimize_encoding)
      end

      # Rebuild CharStrings with subroutine calls
      #
      # @param subroutines [Array<Subroutine>] Subroutines to use
      def rebuild_charstrings(subroutines)
        return if subroutines.empty?

        glyph_count = @cff2.glyph_count

        glyph_count.times do |glyph_id|
          charstring = @cff2.charstring(glyph_id)
          next unless charstring

          # Rewrite CharString to use subroutines
          optimized = rewrite_with_subroutines(charstring, subroutines)
          @cff2.set_charstring(glyph_id, optimized)
        end

        # Update subroutine index in CFF2
        @cff2.local_subr_index = subroutines
      end

      # Get optimization statistics
      #
      # @return [Hash] Statistics about optimization
      def statistics
        @stats
      end

      private

      # Parse CharString to operators
      #
      # @param charstring [String] Binary CharString data
      # @return [Array<Hash>] Operators with operands
      def parse_charstring_operators(_charstring)
        # Placeholder - would parse binary CharString format
        # Returns array of { operator:, operands:, position: }
        []
      end

      # Check if operator is a blend operator
      #
      # @param operator [Hash] Operator data
      # @return [Boolean] True if blend operator
      def blend_operator?(operator)
        operator[:operator] == :blend
      end

      # Extract pattern with surrounding context
      #
      # @param operators [Array<Hash>] All operators
      # @param blend_index [Integer] Index of blend operator
      # @return [Hash, nil] Pattern data
      def extract_pattern_context(_operators, _blend_index)
        # Extract blend and preceding operands
        # Returns { sequence:, frequency:, savings:, positions: }
        nil
      end

      # Group identical patterns
      #
      # @param patterns [Array<BlendPattern>] Raw patterns
      # @return [Array<BlendPattern>] Grouped patterns with frequency
      def group_patterns(patterns)
        grouped = {}

        patterns.each do |pattern|
          key = pattern_key(pattern)
          grouped[key] ||= pattern.dup
          grouped[key][:frequency] ||= 0
          grouped[key][:frequency] += 1
        end

        grouped.values
      end

      # Generate key for pattern grouping
      #
      # @param pattern [Hash] Pattern data
      # @return [String] Unique key
      def pattern_key(pattern)
        pattern[:sequence].join(",")
      end

      # Collect variation indices used in CharStrings
      #
      # @return [Set<Integer>] Set of used indices
      def collect_used_variation_indices
        require "set"
        used = Set.new

        glyph_count = @cff2.glyph_count
        glyph_count.times do |glyph_id|
          charstring = @cff2.charstring(glyph_id)
          next unless charstring

          # Extract variation indices from CharString
          indices = extract_variation_indices(charstring)
          used.merge(indices)
        end

        used
      end

      # Extract variation indices from CharString
      #
      # @param charstring [String] Binary CharString
      # @return [Array<Integer>] Variation indices
      def extract_variation_indices(_charstring)
        # Placeholder - would parse vsindex operators
        []
      end

      # Update region references after deduplication
      #
      # @param mapping [Hash<Integer, Integer>] Old index => new index
      def update_region_references(mapping)
        store = @cff2.variation_store

        store.item_variation_data.each do |data|
          data.update_region_indices(mapping)
        end
      end

      # Rewrite CharString with subroutine calls
      #
      # @param charstring [String] Original CharString
      # @param subroutines [Array<Subroutine>] Available subroutines
      # @return [String] Optimized CharString
      def rewrite_with_subroutines(charstring, _subroutines)
        # Placeholder - would replace patterns with callsubr operators
        charstring
      end

      # Estimate table size in bytes
      #
      # @param cff2 [CFF2] CFF2 table
      # @return [Integer] Estimated size
      def estimate_table_size(_cff2)
        # Placeholder - would calculate actual binary size
        0
      end

      # Calculate savings percentage
      #
      # @return [Float] Percentage saved
      def calculate_savings_percent
        return 0.0 if @stats[:original_size].zero?

        saved = @stats[:original_size] - @stats[:optimized_size]
        (saved.to_f / @stats[:original_size]) * 100.0
      end
    end
  end
end
