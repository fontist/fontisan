# frozen_string_literal: true

require_relative "base_strategy"
require_relative "../../variation/instance_generator"
require_relative "../../variation/variation_context"

module Fontisan
  module Pipeline
    module Strategies
      # Strategy for generating static instances from variable fonts
      #
      # This strategy creates a static font instance at specific design space
      # coordinates by applying variation deltas and removing variation tables.
      # It's used for:
      # - Variable TTF → Static TTF at specific weight
      # - Variable OTF → Static OTF at specific coordinates
      # - Variable → Static for any format conversion
      #
      # The strategy uses the InstanceGenerator to:
      # 1. Apply variation deltas (gvar or CFF2 blend)
      # 2. Apply metrics variations (HVAR, VVAR, MVAR)
      # 3. Remove variation tables (fvar, gvar, CFF2, avar, etc.)
      #
      # If no coordinates are provided, uses default coordinates (axis default values).
      #
      # @example Generate instance at specific weight
      #   strategy = InstanceStrategy.new(coordinates: { "wght" => 700.0 })
      #   tables = strategy.resolve(variable_font)
      #   # tables has no variation tables
      #
      # @example Generate instance at default coordinates
      #   strategy = InstanceStrategy.new
      #   tables = strategy.resolve(variable_font)
      class InstanceStrategy < BaseStrategy
        # @return [Hash<String, Float>] Design space coordinates
        attr_reader :coordinates

        # Initialize strategy with coordinates
        #
        # @param options [Hash] Strategy options
        # @option options [Hash<String, Float>] :coordinates Design space coordinates
        #   (axis tag => value). If not provided, uses default coordinates.
        def initialize(options = {})
          super
          @coordinates = options[:coordinates] || {}
        end

        # Resolve by generating static instance
        #
        # Creates a static font instance at the specified coordinates using
        # the InstanceGenerator. If coordinates are not provided, uses the
        # default coordinates from the font's axes.
        #
        # @param font [TrueTypeFont, OpenTypeFont] Variable font
        # @return [Hash<String, String>] Static font tables
        # @raise [Variation::InvalidCoordinatesError] If coordinates out of range
        def resolve(font)
          # Validate coordinates if provided
          validate_coordinates(font) unless @coordinates.empty?

          # Use InstanceGenerator to create static instance
          generator = Variation::InstanceGenerator.new(font, @coordinates)
          generator.generate
        end

        # Check if strategy preserves variation data
        #
        # @return [Boolean] Always false for this strategy
        def preserves_variation?
          false
        end

        # Get strategy name
        #
        # @return [Symbol] :instance
        def strategy_name
          :instance
        end

        private

        # Validate coordinates against font axes
        #
        # @param font [TrueTypeFont, OpenTypeFont] Variable font
        # @raise [Variation::InvalidCoordinatesError] If invalid
        def validate_coordinates(font)
          context = Variation::VariationContext.new(font)
          context.validate_coordinates(@coordinates)
        end
      end
    end
  end
end
