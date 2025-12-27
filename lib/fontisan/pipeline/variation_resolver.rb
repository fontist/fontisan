# frozen_string_literal: true

require_relative "strategies/base_strategy"
require_relative "strategies/preserve_strategy"
require_relative "strategies/instance_strategy"
require_relative "strategies/named_strategy"

module Fontisan
  module Pipeline
    # Resolves variation data using strategy pattern
    #
    # This class orchestrates variation resolution during font conversion by
    # selecting and executing the appropriate strategy based on user intent.
    # It follows the Strategy pattern to allow different approaches to handling
    # variable font data.
    #
    # Three strategies are available:
    # - PreserveStrategy: Keep variation data intact (for compatible formats)
    # - InstanceStrategy: Generate static instance at coordinates
    # - NamedStrategy: Use named instance from fvar table
    #
    # Strategy selection is explicit through the :strategy option. Each strategy
    # has its own required and optional parameters.
    #
    # @example Preserve variation data
    #   resolver = VariationResolver.new(font, strategy: :preserve)
    #   tables = resolver.resolve
    #
    # @example Generate instance at coordinates
    #   resolver = VariationResolver.new(
    #     font,
    #     strategy: :instance,
    #     coordinates: { "wght" => 700.0 }
    #   )
    #   tables = resolver.resolve
    #
    # @example Use named instance
    #   resolver = VariationResolver.new(
    #     font,
    #     strategy: :named,
    #     instance_index: 0
    #   )
    #   tables = resolver.resolve
    class VariationResolver
      # @return [TrueTypeFont, OpenTypeFont] Font to process
      attr_reader :font

      # @return [Strategies::BaseStrategy] Selected strategy
      attr_reader :strategy

      # Initialize resolver with font and strategy
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to process
      # @param options [Hash] Resolution options
      # @option options [Symbol] :strategy Strategy to use (:preserve, :instance, :named)
      # @option options [Hash] :coordinates Design space coordinates (for :instance)
      # @option options [Integer] :instance_index Named instance index (for :named)
      # @raise [ArgumentError] If strategy is missing or invalid
      def initialize(font, options = {})
        @font = font

        strategy_type = options[:strategy]
        raise ArgumentError, "strategy is required" unless strategy_type

        @strategy = build_strategy(strategy_type, options)

        # Validate strategy-specific requirements
        validate_strategy_requirements(strategy_type, options)
      end

      # Resolve variation data
      #
      # Delegates to the selected strategy to process the font and return
      # the appropriate tables.
      #
      # @return [Hash<String, String>] Font tables after resolution
      def resolve
        @strategy.resolve(@font)
      end

      # Check if resolution preserves variation data
      #
      # @return [Boolean] True if variation is preserved
      def preserves_variation?
        @strategy.preserves_variation?
      end

      # Get strategy name
      #
      # @return [Symbol] Strategy identifier
      def strategy_name
        @strategy.strategy_name
      end

      private

      # Build strategy instance based on type
      #
      # @param type [Symbol] Strategy type (:preserve, :instance, :named)
      # @param options [Hash] Strategy options
      # @return [Strategies::BaseStrategy] Strategy instance
      # @raise [ArgumentError] If strategy type is unknown
      def build_strategy(type, options)
        case type
        when :preserve
          Strategies::PreserveStrategy.new(options)
        when :instance
          Strategies::InstanceStrategy.new(options)
        when :named
          Strategies::NamedStrategy.new(options)
        else
          raise ArgumentError,
                "Unknown strategy: #{type}. " \
                "Valid strategies: :preserve, :instance, :named"
        end
      end

      # Validate strategy-specific requirements
      #
      # @param type [Symbol] Strategy type
      # @param options [Hash] Strategy options
      # @raise [ArgumentError, InvalidCoordinatesError] If validation fails
      def validate_strategy_requirements(type, options)
        case type
        when :instance
          validate_instance_coordinates(options[:coordinates]) if options[:coordinates]
        when :named
          validate_named_instance_index(options[:instance_index]) if options[:instance_index]
        end
      end

      # Validate coordinates for instance strategy
      #
      # @param coordinates [Hash] Coordinates to validate
      # @raise [InvalidCoordinatesError] If coordinates invalid
      def validate_instance_coordinates(coordinates)
        return if coordinates.empty?

        require_relative "../variation/variation_context"
        context = Variation::VariationContext.new(@font)
        context.validate_coordinates(coordinates)
      end

      # Validate instance index for named strategy
      #
      # @param instance_index [Integer] Instance index to validate
      # @raise [ArgumentError] If index invalid
      def validate_named_instance_index(instance_index)
        require_relative "../variation/variation_context"
        context = Variation::VariationContext.new(@font)

        unless context.fvar
          raise ArgumentError, "Font is not a variable font (no fvar table)"
        end

        instances = context.fvar.instances
        if instance_index.negative? || instance_index >= instances.length
          raise ArgumentError,
                "Invalid instance index #{instance_index}. " \
                "Font has #{instances.length} named instances."
        end
      end
    end
  end
end
