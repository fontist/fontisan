# frozen_string_literal: true

module Fontisan
  module Validation
    # VariableFontValidator validates variable font structure
    #
    # Validates:
    # - fvar table structure
    # - Axis definitions and ranges
    # - Instance definitions
    # - Variation table consistency
    # - Metrics variation tables
    #
    # @example Validate a variable font
    #   validator = VariableFontValidator.new(font)
    #   errors = validator.validate
    #   puts "Found #{errors.length} errors" if errors.any?
    class VariableFontValidator
      # Initialize validator with font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      def initialize(font)
        @font = font
        @errors = []
      end

      # Validate variable font
      #
      # @return [Array<String>] Array of error messages
      def validate
        return [] unless @font.has_table?("fvar")

        validate_fvar_structure
        validate_axes
        validate_instances
        validate_variation_tables
        validate_metrics_variation

        @errors
      end

      private

      # Validate fvar table structure
      #
      # @return [void]
      def validate_fvar_structure
        fvar = @font.table("fvar")
        return unless fvar

        if !fvar.respond_to?(:axes) || fvar.axes.nil? || fvar.axes.empty?
          @errors << "fvar: No axes defined"
          return
        end

        if fvar.respond_to?(:axis_count) && fvar.axis_count != fvar.axes.length
          @errors << "fvar: Axis count mismatch (expected #{fvar.axis_count}, got #{fvar.axes.length})"
        end
      end

      # Validate all axes
      #
      # @return [void]
      def validate_axes
        fvar = @font.table("fvar")
        return unless fvar.respond_to?(:axes)

        fvar.axes.each_with_index do |axis, index|
          validate_axis_range(axis, index)
          validate_axis_tag(axis, index)
        end
      end

      # Validate axis range values
      #
      # @param axis [Object] Axis object
      # @param index [Integer] Axis index
      # @return [void]
      def validate_axis_range(axis, index)
        return unless axis.respond_to?(:min_value) && axis.respond_to?(:max_value)

        if axis.min_value > axis.max_value
          tag = axis.respond_to?(:axis_tag) ? axis.axis_tag : "axis #{index}"
          @errors << "Axis #{tag}: min_value (#{axis.min_value}) > max_value (#{axis.max_value})"
        end

        if axis.respond_to?(:default_value) && (axis.default_value < axis.min_value || axis.default_value > axis.max_value)
          tag = axis.respond_to?(:axis_tag) ? axis.axis_tag : "axis #{index}"
          @errors << "Axis #{tag}: default_value (#{axis.default_value}) out of range [#{axis.min_value}, #{axis.max_value}]"
        end
      end

      # Validate axis tag format
      #
      # @param axis [Object] Axis object
      # @param index [Integer] Axis index
      # @return [void]
      def validate_axis_tag(axis, index)
        return unless axis.respond_to?(:axis_tag)

        tag = axis.axis_tag
        unless tag.is_a?(String) && tag.length == 4 && tag =~ /^[a-zA-Z]{4}$/
          @errors << "Axis #{index}: invalid tag '#{tag}' (must be 4 ASCII letters)"
        end
      end

      # Validate named instances
      #
      # @return [void]
      def validate_instances
        fvar = @font.table("fvar")
        return unless fvar.respond_to?(:instances)
        return unless fvar.instances

        fvar.instances.each_with_index do |instance, idx|
          validate_instance_coordinates(instance, idx, fvar)
        end
      end

      # Validate instance coordinates
      #
      # @param instance [Object] Instance object
      # @param idx [Integer] Instance index
      # @param fvar [Object] fvar table
      # @return [void]
      def validate_instance_coordinates(instance, idx, fvar)
        return unless instance.is_a?(Hash) && instance[:coordinates]

        coords = instance[:coordinates]
        axis_count = fvar.respond_to?(:axis_count) ? fvar.axis_count : fvar.axes.length

        if coords.length != axis_count
          @errors << "Instance #{idx}: coordinate count mismatch (expected #{axis_count}, got #{coords.length})"
        end

        coords.each_with_index do |value, axis_idx|
          next if axis_idx >= fvar.axes.length

          axis = fvar.axes[axis_idx]
          next unless axis.respond_to?(:min_value) && axis.respond_to?(:max_value)

          if value < axis.min_value || value > axis.max_value
            tag = axis.respond_to?(:axis_tag) ? axis.axis_tag : "axis #{axis_idx}"
            @errors << "Instance #{idx}: coordinate for #{tag} (#{value}) out of range [#{axis.min_value}, #{axis.max_value}]"
          end
        end
      end

      # Validate variation tables
      #
      # @return [void]
      def validate_variation_tables
        has_gvar = @font.has_table?("gvar")
        has_cff2 = @font.has_table?("CFF2")
        has_glyf = @font.has_table?("glyf")
        has_cff = @font.has_table?("CFF ")

        # TrueType variable fonts should have gvar
        if has_glyf && !has_gvar
          @errors << "TrueType variable font missing gvar table"
        end

        # CFF variable fonts should have CFF2
        if has_cff && !has_cff2
          @errors << "CFF variable font missing CFF2 table"
        end

        # Can't have both gvar and CFF2
        if has_gvar && has_cff2
          @errors << "Font has both gvar and CFF2 tables (incompatible)"
        end
      end

      # Validate metrics variation tables
      #
      # @return [void]
      def validate_metrics_variation
        validate_hvar if @font.has_table?("HVAR")
        validate_vvar if @font.has_table?("VVAR")
        validate_mvar if @font.has_table?("MVAR")
      end

      # Validate HVAR table
      #
      # @return [void]
      def validate_hvar
        # HVAR validation would go here
        # For now, just check it exists
        hvar = @font.table_data["HVAR"]
        if hvar.nil? || hvar.empty?
          @errors << "HVAR table is empty"
        end
      end

      # Validate VVAR table
      #
      # @return [void]
      def validate_vvar
        # VVAR validation would go here
        vvar = @font.table_data["VVAR"]
        if vvar.nil? || vvar.empty?
          @errors << "VVAR table is empty"
        end
      end

      # Validate MVAR table
      #
      # @return [void]
      def validate_mvar
        # MVAR validation would go here
        mvar = @font.table_data["MVAR"]
        if mvar.nil? || mvar.empty?
          @errors << "MVAR table is empty"
        end
      end
    end
  end
end
