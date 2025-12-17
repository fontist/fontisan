# frozen_string_literal: true

require_relative "variation_context"

module Fontisan
  module Variation
    # Extracts variation data from OpenType variable fonts
    #
    # This class provides a unified interface to extract variation information
    # from variable fonts, including:
    # - Variation axes (from fvar table)
    # - Named instances (from fvar table)
    # - Variation type (TrueType gvar or PostScript CFF2)
    #
    # @example Extracting variation data
    #   extractor = Fontisan::Variation::DataExtractor.new(font)
    #   data = extractor.extract
    #   if data
    #     puts "Axes: #{data[:axes].map(&:axis_tag).join(', ')}"
    #     puts "Instances: #{data[:instances].length}"
    #   end
    class DataExtractor
      # Initialize extractor with a font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to extract from
      def initialize(font)
        @font = font
        @context = VariationContext.new(font)
      end

      # Extract variation data from the font
      #
      # @return [Hash, nil] Variation data or nil if not a variable font
      def extract
        return nil unless @context.variable_font?

        {
          axes: extract_axes,
          instances: extract_instances,
          has_gvar: @font.has_table?("gvar"),
          has_cff2: @font.has_table?("CFF2"),
          variation_type: @context.variation_type,
        }
      end

      # Check if font is a variable font
      #
      # @return [Boolean] True if font has fvar table
      def variable_font?
        @context.variable_font?
      end

      private

      # Extract variation axes from fvar table
      #
      # @return [Array<VariationAxisRecord>] Array of axis records
      # @raise [VariationDataCorruptedError] If axes cannot be extracted
      def extract_axes
        return [] unless @context.fvar

        @context.axes
      rescue StandardError => e
        raise VariationDataCorruptedError.new(
          message: "Failed to extract variation axes: #{e.message}",
          details: { error_class: e.class.name },
        )
      end

      # Extract named instances from fvar table
      #
      # @return [Array<Hash>] Array of instance information
      # @raise [VariationDataCorruptedError] If instances cannot be extracted
      def extract_instances
        return [] unless @context.fvar

        @context.fvar.instances || []
      rescue StandardError => e
        raise VariationDataCorruptedError.new(
          message: "Failed to extract instances: #{e.message}",
          details: { error_class: e.class.name },
        )
      end
    end
  end
end
