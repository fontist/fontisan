# frozen_string_literal: true

module Fontisan
  module Pipeline
    module Strategies
      # Base class for variation resolution strategies
      #
      # This abstract class defines the interface that all variation resolution
      # strategies must implement. It follows the Strategy pattern to allow
      # different approaches to handling variable font data during conversion.
      #
      # Subclasses must implement:
      # - resolve(font): Process the font and return tables
      # - preserves_variation?: Indicate if variation data is preserved
      # - strategy_name: Return the strategy identifier
      #
      # @example Implementing a strategy
      #   class MyStrategy < BaseStrategy
      #     def resolve(font)
      #       # Implementation
      #     end
      #
      #     def preserves_variation?
      #       false
      #     end
      #
      #     def strategy_name
      #       :my_strategy
      #     end
      #   end
      class BaseStrategy
        # @return [Hash] Strategy options
        attr_reader :options

        # Initialize strategy with options
        #
        # @param options [Hash] Strategy-specific options
        def initialize(options = {})
          @options = options
        end

        # Resolve variation data
        #
        # This method must be implemented by subclasses to process the font
        # and return the appropriate tables based on the strategy.
        #
        # @param font [TrueTypeFont, OpenTypeFont] Font to process
        # @return [Hash<String, String>] Map of table tags to binary data
        # @raise [NotImplementedError] If not implemented by subclass
        def resolve(font)
          raise NotImplementedError,
                "#{self.class.name} must implement #resolve"
        end

        # Check if strategy preserves variation data
        #
        # @return [Boolean] True if variation data is preserved
        # @raise [NotImplementedError] If not implemented by subclass
        def preserves_variation?
          raise NotImplementedError,
                "#{self.class.name} must implement #preserves_variation?"
        end

        # Get strategy name
        #
        # @return [Symbol] Strategy identifier
        # @raise [NotImplementedError] If not implemented by subclass
        def strategy_name
          raise NotImplementedError,
                "#{self.class.name} must implement #strategy_name"
        end
      end
    end
  end
end
