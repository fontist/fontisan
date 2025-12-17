# frozen_string_literal: true

require_relative "interpolator"
require_relative "region_matcher"

module Fontisan
  module Variation
    # Provides shared context for variation operations
    #
    # This class centralizes the initialization of common variation components
    # (axes, interpolator, region matcher) that are needed by most variation
    # operations. It ensures consistent initialization and validation.
    #
    # @example Creating a variation context
    #   context = VariationContext.new(font)
    #   context.validate!
    #   puts "Axes: #{context.axes.map(&:axis_tag)}"
    #
    # @example Using in a variation class
    #   class MyGenerator
    #     def initialize(font)
    #       @context = VariationContext.new(font)
    #       @context.validate!
    #     end
    #
    #     def generate
    #       @context.interpolator.normalize_coordinate(value, "wght")
    #     end
    #   end
    class VariationContext
      # @return [TrueTypeFont, OpenTypeFont] Font instance
      attr_reader :font

      # @return [Fvar, nil] fvar table
      attr_reader :fvar

      # @return [Array<VariationAxisRecord>] Variation axes
      attr_reader :axes

      # @return [Interpolator] Coordinate interpolator
      attr_reader :interpolator

      # @return [RegionMatcher] Region matcher
      attr_reader :region_matcher

      # Initialize variation context
      #
      # Loads fvar table and initializes all common variation components.
      # Does not validate - call validate! explicitly if needed.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font
      def initialize(font)
        @font = font
        @fvar = font.has_table?("fvar") ? font.table("fvar") : nil
        @axes = @fvar ? @fvar.axes : []
        @interpolator = Interpolator.new(@axes)
        @region_matcher = RegionMatcher.new(@axes)
      end

      # Validate that font is a proper variable font
      #
      # Checks for fvar table and axes definition. Raises errors if
      # font is not a valid variable font.
      #
      # @return [void]
      # @raise [MissingVariationTableError] If fvar table missing
      # @raise [InvalidVariationDataError] If no axes defined
      #
      # @example Validate before processing
      #   context = VariationContext.new(font)
      #   context.validate!
      #   # Safe to proceed
      def validate!
        unless @fvar
          raise MissingVariationTableError.new(
            table: "fvar",
            message: "Font is not a variable font (missing fvar table)",
          )
        end

        if @axes.empty?
          raise InvalidVariationDataError.new(
            message: "Variable font has no axes defined in fvar table",
          )
        end
      end

      # Check if font is a variable font
      #
      # @return [Boolean] True if fvar table exists
      def variable_font?
        !@fvar.nil?
      end

      # Get number of axes
      #
      # @return [Integer] Axis count
      def axis_count
        @axes.length
      end

      # Find axis by tag
      #
      # @param axis_tag [String] Axis tag (e.g., "wght", "wdth")
      # @return [VariationAxisRecord, nil] Axis or nil if not found
      #
      # @example Find weight axis
      #   wght_axis = context.find_axis("wght")
      #   puts "Range: #{wght_axis.min_value} - #{wght_axis.max_value}"
      def find_axis(axis_tag)
        @axes.find { |axis| axis.axis_tag == axis_tag }
      end

      # Get axis tags
      #
      # @return [Array<String>] Array of axis tags
      def axis_tags
        @axes.map(&:axis_tag)
      end

      # Validate coordinates against axes
      #
      # Checks that all coordinate values are within valid axis ranges.
      #
      # @param coordinates [Hash<String, Float>] Design space coordinates
      # @return [void]
      # @raise [InvalidCoordinatesError] If any coordinate out of range
      #
      # @example Validate coordinates
      #   context.validate_coordinates({ "wght" => 700 })
      def validate_coordinates(coordinates)
        coordinates.each do |axis_tag, value|
          axis = find_axis(axis_tag)

          unless axis
            raise InvalidCoordinatesError.new(
              axis: axis_tag,
              value: value,
              range: [],
              message: "Unknown axis '#{axis_tag}'",
            )
          end

          if value < axis.min_value || value > axis.max_value
            raise InvalidCoordinatesError.new(
              axis: axis_tag,
              value: value,
              range: [axis.min_value, axis.max_value],
              message: "Coordinate #{value} for axis '#{axis_tag}' outside valid range [#{axis.min_value}, #{axis.max_value}]",
            )
          end
        end
      end

      # Get default coordinates
      #
      # Returns coordinates at default values for all axes.
      #
      # @return [Hash<String, Float>] Default coordinates
      def default_coordinates
        coordinates = {}
        @axes.each do |axis|
          coordinates[axis.axis_tag] = axis.default_value
        end
        coordinates
      end

      # Normalize coordinates to [-1, 1] range
      #
      # Convenience method that delegates to interpolator.
      #
      # @param coordinates [Hash<String, Float>] User-space coordinates
      # @return [Hash<String, Float>] Normalized coordinates
      def normalize_coordinates(coordinates)
        @interpolator.normalize_coordinates(coordinates)
      end

      # Get variation type
      #
      # Determines whether font uses TrueType (gvar) or PostScript (CFF2)
      # variation format.
      #
      # @return [Symbol] :truetype, :postscript, or :none
      def variation_type
        if @font.has_table?("CFF2")
          :postscript
        elsif @font.has_table?("gvar")
          :truetype
        else
          :none
        end
      end

      # Check if font has glyph variations
      #
      # @return [Boolean] True if gvar or CFF2 present
      def has_glyph_variations?
        @font.has_table?("gvar") || @font.has_table?("CFF2")
      end

      # Check if font has metrics variations
      #
      # @return [Boolean] True if HVAR, VVAR, or MVAR present
      def has_metrics_variations?
        @font.has_table?("HVAR") ||
          @font.has_table?("VVAR") ||
          @font.has_table?("MVAR")
      end
    end
  end
end
