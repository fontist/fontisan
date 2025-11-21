# frozen_string_literal: true

module Fontisan
  module Converters
    # Interface module for font format conversion strategies
    #
    # [`ConversionStrategy`](lib/fontisan/converters/conversion_strategy.rb)
    # defines the contract that all conversion strategy classes must implement.
    # This follows the Strategy pattern to enable polymorphic handling of
    # different conversion types (TTF→OTF, OTF→TTF, same-format copying).
    #
    # Each strategy must implement:
    # - convert(font, options) - Perform the actual conversion
    # - supported_conversions - Return array of [source, target] format pairs
    # - validate(font, target_format) - Validate conversion is possible
    #
    # Strategies are selected by [`FormatConverter`](lib/fontisan/converters/format_converter.rb)
    # based on source and target formats.
    #
    # @example Implementing a strategy
    #   class MyStrategy
    #     include Fontisan::Converters::ConversionStrategy
    #
    #     def convert(font, options = {})
    #       # Perform conversion
    #       tables = {...}
    #       tables
    #     end
    #
    #     def supported_conversions
    #       [[:ttf, :otf], [:otf, :ttf]]
    #     end
    #
    #     def validate(font, target_format)
    #       # Validate font can be converted
    #       raise Error unless valid
    #     end
    #   end
    module ConversionStrategy
      # Convert font to target format
      #
      # This method must return a hash of table tags to binary data,
      # which will be assembled into a complete font by FontWriter.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Conversion options
      # @return [Hash<String, String>] Map of table tags to binary data
      # @raise [NotImplementedError] If not implemented by strategy
      def convert(font, options = {})
        raise NotImplementedError,
              "#{self.class.name} must implement convert(font, options)"
      end

      # Get list of supported conversions
      #
      # Returns an array of [source_format, target_format] pairs that
      # this strategy can handle.
      #
      # @return [Array<Array<Symbol>>] Supported conversion pairs
      # @raise [NotImplementedError] If not implemented by strategy
      #
      # @example
      #   strategy.supported_conversions
      #   # => [[:ttf, :otf], [:otf, :ttf]]
      def supported_conversions
        raise NotImplementedError,
              "#{self.class.name} must implement supported_conversions"
      end

      # Validate that conversion is possible
      #
      # Checks if the given font can be converted to the target format.
      # Should raise an error with a clear message if conversion is not
      # possible.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param target_format [Symbol] Target format (:ttf, :otf, etc.)
      # @return [Boolean] True if valid
      # @raise [Error] If conversion is not possible
      # @raise [NotImplementedError] If not implemented by strategy
      def validate(font, target_format)
        raise NotImplementedError,
              "#{self.class.name} must implement validate(font, target_format)"
      end

      # Check if strategy supports a conversion
      #
      # @param source_format [Symbol] Source format
      # @param target_format [Symbol] Target format
      # @return [Boolean] True if supported
      def supports?(source_format, target_format)
        supported_conversions.include?([source_format, target_format])
      end
    end
  end
end
