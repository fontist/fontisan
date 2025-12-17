# frozen_string_literal: true

module Fontisan
  module Variation
    # Validates variable font structure and consistency
    #
    # This class performs comprehensive validation of variable font tables
    # to ensure structural integrity and catch common issues before instance
    # generation or subsetting operations.
    #
    # Validation checks:
    # 1. Table consistency - Verify axis counts match across tables
    # 2. Delta integrity - Check delta sets are complete
    # 3. Region coverage - Ensure regions cover design space
    # 4. Instance definitions - Validate instance coordinates
    #
    # @example Validating a variable font
    #   validator = Fontisan::Variation::Validator.new(font)
    #   report = validator.validate
    #   if report[:valid]
    #     puts "Font is valid"
    #   else
    #     report[:errors].each { |err| puts "Error: #{err}" }
    #   end
    class Validator
      # @return [TrueTypeFont, OpenTypeFont] Font being validated
      attr_reader :font

      # @return [Array<String>] Validation errors
      attr_reader :errors

      # @return [Array<String>] Validation warnings
      attr_reader :warnings

      # Initialize validator
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font to validate
      def initialize(font)
        @font = font
        @errors = []
        @warnings = []
      end

      # Perform full validation
      #
      # Runs all validation checks and returns a detailed report.
      #
      # @return [Hash] Validation report with :valid, :errors, :warnings
      def validate
        @errors.clear
        @warnings.clear

        check_is_variable_font
        check_table_consistency if @errors.empty?
        check_delta_integrity if @errors.empty?
        check_region_coverage if @errors.empty?
        check_instance_definitions if @errors.empty?

        {
          valid: @errors.empty?,
          errors: @errors.dup,
          warnings: @warnings.dup,
        }
      end

      # Quick validation (essential checks only)
      #
      # @return [Boolean] True if font passes basic validation
      def valid?
        validate[:valid]
      end

      private

      # Check if font is actually a variable font
      def check_is_variable_font
        unless @font.has_table?("fvar")
          @errors << "Missing required 'fvar' table - not a variable font"
          return
        end

        fvar = @font.table("fvar")
        unless fvar&.axis_count&.positive?
          @errors << "fvar table has no axes defined"
        end
      end

      # Check consistency across all variation tables
      def check_table_consistency
        fvar = @font.table("fvar")
        return unless fvar

        axis_count = fvar.axis_count

        # Check gvar axis count if present
        if @font.has_table?("gvar")
          gvar = @font.table("gvar")
          if gvar && gvar.axis_count != axis_count
            @errors << "gvar axis count (#{gvar.axis_count}) doesn't match fvar (#{axis_count})"
          end
        end

        # Check CFF2 if present
        if @font.has_table?("CFF2")
          cff2 = @font.table("CFF2")
          if cff2.respond_to?(:num_axes)
            cff2_axes = cff2.num_axes || 0
            if cff2_axes != axis_count && cff2_axes.positive?
              @errors << "CFF2 axis count (#{cff2_axes}) doesn't match fvar (#{axis_count})"
            end
          end
        end

        # Check HVAR region count if present
        check_metrics_table_consistency("HVAR", axis_count)
        check_metrics_table_consistency("VVAR", axis_count)
        check_metrics_table_consistency("MVAR", axis_count)

        # Verify at least one variation table exists
        has_outline_var = @font.has_table?("gvar") || @font.has_table?("CFF2")
        has_metrics_var = @font.has_table?("HVAR") || @font.has_table?("VVAR") || @font.has_table?("MVAR")

        unless has_outline_var || has_metrics_var
          @warnings << "No variation tables found (gvar/CFF2/HVAR/VVAR/MVAR)"
        end
      end

      # Check metrics table consistency
      #
      # @param table_tag [String] Table tag (HVAR, VVAR, MVAR)
      # @param expected_axes [Integer] Expected axis count
      def check_metrics_table_consistency(table_tag, expected_axes)
        return unless @font.has_table?(table_tag)

        table = @font.table(table_tag)
        return unless table.respond_to?(:item_variation_store)

        store = table.item_variation_store
        return unless store

        # Check region list axis count
        if store.respond_to?(:region_list) && store.region_list
          region_list = store.region_list
          if region_list.respond_to?(:axis_count)
            region_axes = region_list.axis_count
            if region_axes != expected_axes
              @errors << "#{table_tag} region axis count (#{region_axes}) doesn't match fvar (#{expected_axes})"
            end
          end
        end
      end

      # Check delta integrity
      def check_delta_integrity
        # Check gvar delta completeness
        if @font.has_table?("gvar") && @font.has_table?("maxp")
          check_gvar_delta_integrity
        end

        # Check HVAR delta coverage
        if @font.has_table?("HVAR")
          check_hvar_delta_integrity
        end
      end

      # Check gvar delta sets are complete
      def check_gvar_delta_integrity
        gvar = @font.table("gvar")
        maxp = @font.table("maxp")
        return unless gvar && maxp

        glyph_count = maxp.num_glyphs
        gvar_count = gvar.glyph_count

        if gvar_count != glyph_count
          @errors << "gvar glyph count (#{gvar_count}) doesn't match maxp (#{glyph_count})"
        end

        # Sample check: verify first and last glyphs have accessible data
        if gvar_count.positive?
          first_data = gvar.glyph_variation_data(0)
          @warnings << "First glyph has no variation data" if first_data.nil?

          if gvar_count > 1
            last_data = gvar.glyph_variation_data(gvar_count - 1)
            @warnings << "Last glyph has no variation data" if last_data.nil?
          end
        end
      rescue StandardError => e
        @errors << "Failed to check gvar delta integrity: #{e.message}"
      end

      # Check HVAR delta coverage
      def check_hvar_delta_integrity
        hvar = @font.table("HVAR")
        return unless hvar

        # Check for item_variation_store
        unless hvar.respond_to?(:item_variation_store)
          @warnings << "HVAR table doesn't support item_variation_store"
          return
        end

        store = hvar.item_variation_store
        unless store
          @warnings << "HVAR has no item variation store"
          return
        end

        # Check that variation data exists
        if store.respond_to?(:item_variation_data)
          data = store.item_variation_data
          if data.nil? || data.empty?
            @warnings << "HVAR has no variation data"
          end
        end
      rescue StandardError => e
        @warnings << "Failed to check HVAR delta integrity: #{e.message}"
      end

      # Check region coverage
      def check_region_coverage
        fvar = @font.table("fvar")
        return unless fvar

        axes = fvar.axes
        return if axes.empty?

        # Check gvar regions if present
        if @font.has_table?("gvar")
          check_gvar_region_coverage(axes)
        end

        # Check metrics table regions
        check_metrics_region_coverage("HVAR", axes) if @font.has_table?("HVAR")
        check_metrics_region_coverage("VVAR", axes) if @font.has_table?("VVAR")
        check_metrics_region_coverage("MVAR", axes) if @font.has_table?("MVAR")
      end

      # Check gvar region coverage
      #
      # @param axes [Array] Variation axes
      def check_gvar_region_coverage(axes)
        gvar = @font.table("gvar")
        return unless gvar

        # Check shared tuples are within axis ranges
        shared = gvar.shared_tuples
        return if shared.empty?

        shared.each_with_index do |tuple, idx|
          next unless tuple

          tuple.each_with_index do |coord, axis_idx|
            next if axis_idx >= axes.length
            next unless coord

            axes[axis_idx]
            # Normalized coords should be in [-1, 1] range
            if coord < -1.0 || coord > 1.0
              @warnings << "gvar shared tuple #{idx} axis #{axis_idx} out of range: #{coord}"
            end
          end
        end
      rescue StandardError => e
        @warnings << "Failed to check gvar region coverage: #{e.message}"
      end

      # Check metrics table region coverage
      #
      # @param table_tag [String] Table tag
      # @param axes [Array] Variation axes
      def check_metrics_region_coverage(table_tag, axes)
        table = @font.table(table_tag)
        return unless table.respond_to?(:item_variation_store)

        store = table.item_variation_store
        return unless store.respond_to?(:region_list)

        region_list = store.region_list
        return unless region_list.respond_to?(:regions)

        # Check each region
        regions = region_list.regions
        regions.each_with_index do |region, idx|
          next unless region.respond_to?(:region_axes)

          region.region_axes.each_with_index do |reg_axis, axis_idx|
            next if axis_idx >= axes.length
            next unless reg_axis

            # Check coordinates are in valid range [-1, 1]
            %i[start_coord peak_coord end_coord].each do |coord_method|
              next unless reg_axis.respond_to?(coord_method)

              coord = reg_axis.send(coord_method)
              if coord < -1.0 || coord > 1.0
                @warnings << "#{table_tag} region #{idx} axis #{axis_idx} #{coord_method} out of range: #{coord}"
              end
            end
          end
        end
      rescue StandardError => e
        @warnings << "Failed to check #{table_tag} region coverage: #{e.message}"
      end

      # Check instance definitions
      def check_instance_definitions
        fvar = @font.table("fvar")
        return unless fvar

        axes = fvar.axes
        instances = fvar.instances

        return if instances.empty?

        instances.each_with_index do |instance, idx|
          next unless instance

          # Check coordinate count matches axis count
          coords = instance[:coordinates]
          if coords.length != axes.length
            @errors << "Instance #{idx} has #{coords.length} coordinates but #{axes.length} axes"
            next
          end

          # Check each coordinate is in axis range
          coords.each_with_index do |coord, axis_idx|
            axis = axes[axis_idx]
            next unless axis

            min = axis.min_value
            max = axis.max_value

            if coord < min || coord > max
              @warnings << "Instance #{idx} axis #{axis.axis_tag} coordinate #{coord} outside range [#{min}, #{max}]"
            end
          end
        end
      rescue StandardError => e
        @errors << "Failed to check instance definitions: #{e.message}"
      end
    end
  end
end
