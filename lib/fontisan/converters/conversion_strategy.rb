# frozen_string_literal: true

module Fontisan
  module Converters
    # Interface module and declarative options DSL for conversion strategies
    #
    # [`ConversionStrategy`](lib/fontisan/converters/conversion_strategy.rb)
    # defines the contract that all conversion strategy classes must implement,
    # plus a declarative DSL for declaring the options each strategy accepts.
    #
    # ## Why a declarative options DSL
    #
    # Each format has its own spec-mandated knobs (WOFF: zlib level,
    # WOFF2: Brotli quality, etc.). Letting each strategy declare its own
    # options keeps the schema with the code that consumes it (encapsulation),
    # and makes adding a new format a pure additive change (OCP): write a new
    # strategy class, declare its options, done — no edits to central option
    # lists, the CLI option parser, or ConversionOptions.
    #
    # The strategy is also the sole validator of its own options. The
    # runtime check at `FormatConverter#convert` calls
    # `strategy.class.validate_options!` to enforce the format ↔ option
    # mapping (e.g., rejecting `--zlib-level` on a WOFF2 conversion). This
    # is the MECE guarantee: every option belongs to exactly one strategy,
    # and a strategy rejects anything it did not declare.
    #
    # @example Declaring options
    #   class WoffWriter
    #     include ConversionStrategy
    #
    #     option :zlib_level, type: :integer, range: 0..9, default: 6,
    #            cli: "--zlib-level", desc: "zlib compression level"
    #     option :uncompressed, type: :boolean, default: false,
    #            cli: "--uncompressed", desc: "store tables uncompressed"
    #
    #     def convert(font, options = {})
    #       self.class.validate_options!(options)
    #       # ...
    #     end
    #   end
    module ConversionStrategy
      # Declarative description of a single strategy option.
      # `allowed_values` is spelled out (not `values`) to avoid shadowing
      # Struct#values.
      Option = Struct.new(:name, :type, :default, :cli, :desc, :range,
                          :allowed_values, keyword_init: true)

      # Class methods mixed into including classes via `included`.
      module ClassMethods
        # Declare an option this strategy accepts.
        #
        # @param name [Symbol] Option name (the hash key used in `convert`)
        # @param type [Symbol] One of :integer, :boolean, :string
        # @param default [Object] Default value when the caller omits the option
        # @param cli [String] CLI flag shape (for help text generation)
        # @param desc [String] Human-readable description
        # @param range [Range, nil] For :integer; valid range
        # @param values [Array, nil] For :string; allowed values
        # @return [void]
        def option(name, type:, default:, cli:, desc:, range: nil, values: nil)
          declared_options << Option.new(
            name: name, type: type, default: default, cli: cli, desc: desc,
            range: range, allowed_values: values
          )
        end

        # All options declared by this class.
        #
        # @return [Array<Option>]
        def declared_options
          @declared_options ||= []
        end

        # Public accessor: the full list of options for this strategy.
        alias supported_options declared_options

        # Find the option schema for a given key (symbol or string).
        #
        # @param name [Symbol, String]
        # @return [Option, nil]
        def option_for(name)
          supported_options.find { |o| o.name == name.to_sym }
        end

        # Default values for every declared option.
        #
        # @return [Hash{Symbol => Object}]
        def default_options
          supported_options.to_h { |o| [o.name, o.default] }
        end

        # Validate a user-provided options hash against this strategy's schema.
        #
        # Raises ArgumentError for any unknown key, wrong type, or
        # out-of-range value. Called by FormatConverter after strategy
        # selection, so cross-format misuse (e.g., `--zlib-level` on a
        # WOFF2 conversion) is caught here.
        #
        # @param user_options [Hash{Symbol, String => Object}]
        # @return [void]
        # @raise [ArgumentError] if any key is unknown or any value is invalid
        def validate_options!(user_options)
          user_options.each_key do |key|
            opt = option_for(key)
            next if opt

            names = supported_options.map(&:name)
            list = names.empty? ? "(none)" : names.join(", ")
            raise ArgumentError,
                  "Unknown option #{key.inspect} for #{name}. " \
                  "Supported: #{list}"
          end

          user_options.each do |key, value|
            opt = option_for(key)
            validate_option_value!(opt, value) unless value.nil?
          end
        end

        private

        # Type-check a single value against its declared schema.
        #
        # @param opt [Option]
        # @param value [Object]
        # @return [void]
        # @raise [ArgumentError] if value fails type or range/values check
        def validate_option_value!(opt, value)
          case opt.type
          when :integer
            unless value.is_a?(Integer)
              raise ArgumentError,
                    "#{opt.name} must be an Integer, got #{value.inspect} " \
                    "(#{value.class})"
            end
            return unless opt.range && !opt.range.cover?(value)

            raise ArgumentError,
                  "#{opt.name} must be in #{opt.range}, got #{value}"
          when :boolean
            return if [true, false].include?(value)

            raise ArgumentError,
                  "#{opt.name} must be true or false, got #{value.inspect}"
          when :string
            unless value.is_a?(String)
              raise ArgumentError,
                    "#{opt.name} must be a String, got #{value.class}"
            end
            return unless opt.allowed_values && !opt.allowed_values.include?(value)

            raise ArgumentError,
                  "#{opt.name} must be one of #{opt.allowed_values.join(', ')}, " \
                  "got #{value.inspect}"
          else
            raise "Unknown option type #{opt.type.inspect} on #{opt.name}"
          end
        end
      end

      # Mix ClassMethods into any class that includes this module.
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Convert font to target format.
      #
      # Strategies must implement this. Subclasses should call
      # `self.class.validate_options!(options)` first to enforce their schema.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Conversion options
      # @return [Hash<String, String>] Map of table tags to binary data
      # @raise [NotImplementedError] If not implemented by strategy
      def convert(font, options = {})
        raise NotImplementedError,
              "#{self.class.name} must implement convert(font, options)"
      end

      # Get list of supported conversions.
      #
      # @return [Array<Array<Symbol>>] Supported [source, target] pairs
      # @raise [NotImplementedError] If not implemented by strategy
      def supported_conversions
        raise NotImplementedError,
              "#{self.class.name} must implement supported_conversions"
      end

      # Validate that conversion is possible.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param target_format [Symbol] Target format
      # @return [Boolean] True if valid
      # @raise [Error] If conversion is not possible
      # @raise [NotImplementedError] If not implemented by strategy
      def validate(font, target_format)
        raise NotImplementedError,
              "#{self.class.name} must implement validate(font, target_format)"
      end

      # Check if strategy supports a given conversion.
      #
      # @param source_format [Symbol]
      # @param target_format [Symbol]
      # @return [Boolean]
      def supports?(source_format, target_format)
        supported_conversions.include?([source_format, target_format])
      end
    end
  end
end
