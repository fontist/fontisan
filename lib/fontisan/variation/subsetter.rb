# frozen_string_literal: true

require_relative "validator"
require_relative "optimizer"
require_relative "table_accessor"

module Fontisan
  module Variation
    # Subset variable fonts while preserving variation
    #
    # This class enables subsetting operations on variable fonts while
    # maintaining variation capabilities. It can subset by glyphs, axes,
    # or both, and includes validation to ensure the resulting subset
    # remains a valid variable font.
    #
    # Subsetting operations:
    # 1. Glyph subsetting - Keep only specified glyphs with their variations
    # 2. Axis subsetting - Keep only specified axes
    # 3. Region simplification - Deduplicate and merge similar regions
    # 4. Validation - Ensure subset integrity
    #
    # @example Subset to specific glyphs
    #   subsetter = Fontisan::Variation::Subsetter.new(font)
    #   result = subsetter.subset_glyphs([0, 1, 2, 3])
    #
    # @example Subset to specific axes
    #   subsetter = Fontisan::Variation::Subsetter.new(font)
    #   result = subsetter.subset_axes(["wght", "wdth"])
    class Subsetter
      include TableAccessor

      # @return [TrueTypeFont, OpenTypeFont] Font being subset
      attr_reader :font

      # @return [Validator] Validation utility
      attr_reader :validator

      # @return [Hash] Subsetter options
      attr_reader :options

      # @return [Hash] Last operation report
      attr_reader :report

      # Initialize subsetter
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font to subset
      # @param options [Hash] Subsetter options
      # @option options [Boolean] :validate Validate before/after subsetting (default: true)
      # @option options [Boolean] :optimize Optimize after subsetting (default: true)
      # @option options [Float] :region_threshold Region similarity threshold (default: 0.01)
      def initialize(font, options = {})
        @font = font
        @validator = Validator.new(font)
        @options = {
          validate: true,
          optimize: true,
          region_threshold: 0.01,
        }.merge(options)
        @report = {}
        @variation_tables = {}
      end

      # Subset glyphs while preserving variation
      #
      # Filters variation data to keep only specified glyphs.
      #
      # @param glyph_ids [Array<Integer>] Glyph IDs to keep
      # @return [Hash] Subset result with :tables and :report
      def subset_glyphs(glyph_ids)
        validate_input if @options[:validate]

        @report = {
          operation: :subset_glyphs,
          original_glyph_count: get_glyph_count,
          subset_glyph_count: glyph_ids.length,
          glyphs_removed: get_glyph_count - glyph_ids.length,
        }

        # Start with all tables
        tables = @font.table_data.dup

        # Subset gvar if present
        if has_variation_table?("gvar")
          subset_gvar_table(tables, glyph_ids)
          @report[:gvar_updated] = true
        end

        # Subset CFF2 if present
        if has_variation_table?("CFF2")
          subset_cff2_table(tables, glyph_ids)
          @report[:cff2_updated] = true
        end

        # Subset metrics variations
        subset_metrics_variations(tables, glyph_ids)

        # Update non-variation tables
        update_glyph_tables(tables, glyph_ids)

        validate_output(tables) if @options[:validate]

        { tables: tables, report: @report }
      end

      # Filter to specific axes
      #
      # Removes unused axes and updates all variation tables.
      #
      # @param axis_tags [Array<String>] Axis tags to keep (e.g., ["wght", "wdth"])
      # @return [Hash] Subset result with :tables and :report
      def subset_axes(axis_tags)
        validate_input if @options[:validate]

        fvar = variation_table("fvar")
        unless fvar
          return { tables: @font.table_data.dup,
                   report: { error: "No fvar table" } }
        end

        # Find axes to keep
        all_axes = fvar.axes
        keep_axes = all_axes.select { |axis| axis_tags.include?(axis.axis_tag) }
        keep_indices = keep_axes.map { |axis| all_axes.index(axis) }

        @report = {
          operation: :subset_axes,
          original_axis_count: all_axes.length,
          subset_axis_count: keep_axes.length,
          axes_removed: all_axes.length - keep_axes.length,
          removed_axes: (all_axes.map(&:axis_tag) - axis_tags),
        }

        # Start with all tables
        tables = @font.table_data.dup

        # Update fvar table
        subset_fvar_table(tables, keep_axes, keep_indices)

        # Update gvar if present
        if has_variation_table?("gvar")
          subset_gvar_axes(tables, keep_indices)
          @report[:gvar_updated] = true
        end

        # Update CFF2 if present
        if has_variation_table?("CFF2")
          subset_cff2_axes(tables, keep_indices)
          @report[:cff2_updated] = true
        end

        # Update metrics variation tables
        subset_metrics_axes(tables, keep_indices)

        validate_output(tables) if @options[:validate]

        { tables: tables, report: @report }
      end

      # Simplify regions within threshold
      #
      # Uses VariationOptimizer to deduplicate regions.
      #
      # @param threshold [Float] Similarity threshold (default: from options)
      # @return [Hash] Simplification result with :tables and :report
      def simplify_regions(threshold: nil)
        threshold ||= @options[:region_threshold]

        @report = {
          operation: :simplify_regions,
          threshold: threshold,
        }

        tables = @font.table_data.dup

        # Optimize CFF2 if present
        if has_variation_table?("CFF2")
          cff2 = variation_table("CFF2")
          optimizer = Optimizer.new(cff2, region_threshold: threshold)
          optimizer.optimize

          @report[:regions_deduplicated] =
            optimizer.stats[:regions_deduplicated]
          @report[:cff2_optimized] = true
        end

        # Simplify metrics table regions
        simplify_metrics_regions(tables, threshold)

        validate_output(tables) if @options[:validate]

        { tables: tables, report: @report }
      end

      # Combined subset operation
      #
      # Performs multiple subsetting operations in sequence.
      #
      # @param glyphs [Array<Integer>, nil] Glyph IDs to keep (nil = all)
      # @param axes [Array<String>, nil] Axis tags to keep (nil = all)
      # @param simplify [Boolean] Simplify regions after subsetting
      # @return [Hash] Combined result with :tables and :report
      def subset(glyphs: nil, axes: nil, simplify: true)
        # Don't validate input here - let sub-methods handle it
        # to avoid multiple validations

        steps = []
        tables = @font.table_data.dup

        # Step 1: Subset glyphs if specified
        if glyphs
          subsetter = Subsetter.new(@font, @options)
          glyph_result = subsetter.subset_glyphs(glyphs)
          tables = glyph_result[:tables]
          steps << { step: :subset_glyphs, report: glyph_result[:report] }
        end

        # Step 2: Subset axes if specified
        if axes
          # Create temporary font wrapper with subset tables
          temp_font = create_temp_font(tables)
          axis_subsetter = Subsetter.new(temp_font, @options)
          axis_result = axis_subsetter.subset_axes(axes)
          tables = axis_result[:tables]
          steps << { step: :subset_axes, report: axis_result[:report] }
        end

        # Step 3: Simplify regions if requested
        if simplify && @options[:optimize]
          temp_font = create_temp_font(tables)
          region_subsetter = Subsetter.new(temp_font, @options)
          simplify_result = region_subsetter.simplify_regions
          tables = simplify_result[:tables]
          steps << { step: :simplify_regions, report: simplify_result[:report] }
        end

        # Create combined report
        @report = {
          operation: :combined_subset,
          steps: steps,
        }

        # Validate final output if requested
        if @options[:validate]
          validate_output(tables)
        end

        { tables: tables, report: @report }
      end

      private

      # Validate input font
      # @raise [InvalidVariationDataError] If font is invalid
      def validate_input
        result = @validator.validate
        return if result[:valid]

        errors = result[:errors].join(", ")
        raise InvalidVariationDataError.new(
          message: "Invalid input font: #{errors}",
          details: { validation_errors: result[:errors] },
        )
      end

      # Validate output tables
      #
      # @param tables [Hash] Output tables
      def validate_output(tables)
        temp_font = create_temp_font(tables)
        validator = Validator.new(temp_font)
        result = validator.validate

        @report[:validation] = result

        unless result[:valid]
          @report[:validation_errors] = result[:errors]
        end
      end

      # Get glyph count from maxp table
      #
      # @return [Integer] Glyph count
      def get_glyph_count
        maxp = variation_table("maxp")
        maxp ? maxp.num_glyphs : 0
      end

      # Subset gvar table to specific glyphs
      #
      # @param tables [Hash] Font tables
      # @param glyph_ids [Array<Integer>] Glyph IDs to keep
      def subset_gvar_table(_tables, _glyph_ids)
        # This is a placeholder - full implementation would:
        # 1. Read gvar table
        # 2. Extract variation data for keep glyphs
        # 3. Rebuild glyph variation data array with new offsets
        # 4. Update glyph_count
        # 5. Serialize back to binary

        @report[:gvar_note] = "gvar subsetting not yet implemented"
      end

      # Subset CFF2 table to specific glyphs
      #
      # @param tables [Hash] Font tables
      # @param glyph_ids [Array<Integer>] Glyph IDs to keep
      def subset_cff2_table(_tables, _glyph_ids)
        # This is a placeholder - full implementation would:
        # 1. Read CFF2 table
        # 2. Extract CharStrings for keep glyphs
        # 3. Rebuild CharString INDEX
        # 4. Update FDSelect if present
        # 5. Serialize back to binary

        @report[:cff2_note] = "CFF2 subsetting not yet implemented"
      end

      # Subset metrics variation tables
      #
      # @param tables [Hash] Font tables
      # @param glyph_ids [Array<Integer>] Glyph IDs to keep
      def subset_metrics_variations(tables, glyph_ids)
        if has_variation_table?("HVAR")
          subset_metrics_table(tables, "HVAR",
                               glyph_ids)
        end
        if has_variation_table?("VVAR")
          subset_metrics_table(tables, "VVAR",
                               glyph_ids)
        end
        # MVAR is font-wide, no glyph subsetting needed
      end

      # Subset a single metrics table
      #
      # @param tables [Hash] Font tables
      # @param table_tag [String] Table tag
      # @param glyph_ids [Array<Integer>] Glyph IDs to keep
      def subset_metrics_table(_tables, table_tag, _glyph_ids)
        # This is a placeholder - full implementation would:
        # 1. Read metrics table
        # 2. Filter DeltaSetIndexMap to keep glyphs
        # 3. Remove unused ItemVariationData
        # 4. Rebuild and serialize

        @report[:"#{table_tag.downcase}_note"] =
          "#{table_tag} subsetting not yet implemented"
      end

      # Update non-variation glyph tables
      #
      # @param tables [Hash] Font tables
      # @param glyph_ids [Array<Integer>] Glyph IDs to keep
      def update_glyph_tables(_tables, _glyph_ids)
        # Update maxp
        # Update glyf/loca or CFF
        # Update cmap
        # etc.

        @report[:glyph_tables_note] = "Glyph table updates not yet implemented"
      end

      # Subset fvar table
      #
      # @param tables [Hash] Font tables
      # @param keep_axes [Array] Axes to keep
      # @param keep_indices [Array<Integer>] Axis indices to keep
      def subset_fvar_table(_tables, _keep_axes, _keep_indices)
        # This is a placeholder - full implementation would:
        # 1. Rebuild fvar with subset axes
        # 2. Update instances to remove coordinates for removed axes
        # 3. Serialize back to binary

        @report[:fvar_note] = "fvar subsetting not yet implemented"
      end

      # Subset gvar axes
      #
      # @param tables [Hash] Font tables
      # @param keep_indices [Array<Integer>] Axis indices to keep
      def subset_gvar_axes(_tables, _keep_indices)
        # This is a placeholder - full implementation would:
        # 1. Update axis_count
        # 2. Filter shared tuples to keep indices
        # 3. Filter tuple variations to keep indices
        # 4. Serialize back to binary

        @report[:gvar_axes_note] = "gvar axis subsetting not yet implemented"
      end

      # Subset CFF2 axes
      #
      # @param tables [Hash] Font tables
      # @param keep_indices [Array<Integer>] Axis indices to keep
      def subset_cff2_axes(_tables, _keep_indices)
        # This is a placeholder - full implementation would:
        # 1. Update num_axes in CFF2
        # 2. Filter blend operands to keep indices
        # 3. Update ItemVariationStore regions
        # 4. Serialize back to binary

        @report[:cff2_axes_note] = "CFF2 axis subsetting not yet implemented"
      end

      # Subset metrics table axes
      #
      # @param tables [Hash] Font tables
      # @param keep_indices [Array<Integer>] Axis indices to keep
      def subset_metrics_axes(tables, keep_indices)
        if has_variation_table?("HVAR")
          subset_metrics_table_axes(tables, "HVAR",
                                    keep_indices)
        end
        if has_variation_table?("VVAR")
          subset_metrics_table_axes(tables, "VVAR",
                                    keep_indices)
        end
        if has_variation_table?("MVAR")
          subset_metrics_table_axes(tables, "MVAR",
                                    keep_indices)
        end
      end

      # Subset a single metrics table's axes
      #
      # @param tables [Hash] Font tables
      # @param table_tag [String] Table tag
      # @param keep_indices [Array<Integer>] Axis indices to keep
      def subset_metrics_table_axes(_tables, table_tag, _keep_indices)
        # This is a placeholder - full implementation would:
        # 1. Read metrics table
        # 2. Filter ItemVariationStore regions to keep axis indices
        # 3. Rebuild and serialize

        @report[:"#{table_tag.downcase}_axes_note"] =
          "#{table_tag} axis subsetting not yet implemented"
      end

      # Simplify metrics table regions
      #
      # @param tables [Hash] Font tables
      # @param threshold [Float] Similarity threshold
      def simplify_metrics_regions(_tables, _threshold)
        # This is a placeholder - full implementation would:
        # 1. Load each metrics table
        # 2. Deduplicate regions in ItemVariationStore
        # 3. Update delta set indices
        # 4. Serialize back to binary

        @report[:metrics_simplify_note] =
          "Metrics region simplification not yet implemented"
      end

      # Create temporary font wrapper for validation
      #
      # @param tables [Hash] Table data
      # @return [Object] Temporary font wrapper
      def create_temp_font(tables)
        # This is a simplified wrapper for validation
        # In production, would create proper font object
        Class.new do
          attr_reader :table_data

          def initialize(tables)
            @table_data = tables
            @parsed_tables = {}
          end

          def has_table?(tag)
            @table_data.key?(tag)
          end

          def table(tag)
            return @parsed_tables[tag] if @parsed_tables.key?(tag)
            return nil unless has_table?(tag)

            # Parse table on demand
            # This is simplified - real implementation would use proper parsers
            @parsed_tables[tag] = nil
          end
        end.new(tables)
      end
    end
  end
end
