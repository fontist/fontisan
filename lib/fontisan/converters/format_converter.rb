# frozen_string_literal: true

require_relative "conversion_strategy"
require_relative "table_copier"
require_relative "outline_converter"
require_relative "woff2_encoder"
require_relative "svg_generator"
require "yaml"

module Fontisan
  module Converters
    # Main orchestrator for font format conversions
    #
    # [`FormatConverter`](lib/fontisan/converters/format_converter.rb) is the
    # primary entry point for all format conversion operations. It:
    # - Selects appropriate conversion strategy based on source/target formats
    # - Validates conversions against the conversion matrix
    # - Delegates actual conversion to strategy implementations
    # - Provides clean error messages for unsupported conversions
    #
    # The converter uses a strategy pattern with pluggable strategies for
    # different conversion types:
    # - OutlineConverter: TTF ↔ OTF conversions
    # - TableCopier: Same-format operations
    # - Woff2Encoder: TTF/OTF → WOFF2 compression
    # - SvgGenerator: TTF/OTF → SVG font generation
    #
    # Supported conversions are defined in the conversion matrix configuration
    # file, making it easy to extend without modifying code.
    #
    # @example Converting TTF to OTF
    #   converter = Fontisan::Converters::FormatConverter.new
    #   tables = converter.convert(font, :otf)
    #   FontWriter.write_to_file(tables, 'output.otf',
    #                            sfnt_version: 0x4F54544F)
    #
    # @example Same-format copy
    #   converter = Fontisan::Converters::FormatConverter.new
    #   tables = converter.convert(font, :ttf)  # TTF to TTF
    #   FontWriter.write_to_file(tables, 'copy.ttf')
    class FormatConverter
      # @return [Hash] Conversion matrix loaded from config
      attr_reader :conversion_matrix

      # @return [Array] Available conversion strategies
      attr_reader :strategies

      # Initialize converter with strategies
      #
      # @param conversion_matrix_path [String, nil] Path to conversion matrix
      #   config. If nil, uses default.
      def initialize(conversion_matrix_path: nil)
        @strategies = [
          TableCopier.new,
          OutlineConverter.new,
          Woff2Encoder.new,
          SvgGenerator.new,
        ]

        load_conversion_matrix(conversion_matrix_path)
      end

      # Convert font to target format
      #
      # This is the main entry point for format conversion. It:
      # 1. Detects source format from font
      # 2. Validates conversion is supported
      # 3. Selects appropriate strategy
      # 4. Delegates conversion to strategy
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param target_format [Symbol] Target format (:ttf, :otf, :woff2, :svg)
      # @param options [Hash] Additional conversion options
      # @return [Hash<String, String>] Map of table tags to binary data
      # @raise [ArgumentError] If parameters are invalid
      # @raise [Error] If conversion is not supported
      #
      # @example
      #   tables = converter.convert(font, :otf)
      def convert(font, target_format, options = {})
        validate_parameters!(font, target_format)

        source_format = detect_format(font)
        validate_conversion_supported!(source_format, target_format)

        strategy = select_strategy(source_format, target_format)
        strategy.convert(font, options.merge(target_format: target_format))
      end

      # Check if a conversion is supported
      #
      # @param source_format [Symbol] Source format
      # @param target_format [Symbol] Target format
      # @return [Boolean] True if conversion is supported
      def supported?(source_format, target_format)
        return false unless conversion_matrix

        conversions = conversion_matrix["conversions"]
        return false unless conversions

        conversions.any? do |conv|
          conv["from"] == source_format.to_s &&
            conv["to"] == target_format.to_s
        end
      end

      # Get list of supported target formats for a source format
      #
      # @param source_format [Symbol] Source format
      # @return [Array<Symbol>] Supported target formats
      def supported_targets(source_format)
        return [] unless conversion_matrix

        conversions = conversion_matrix["conversions"]
        return [] unless conversions

        conversions
          .select { |conv| conv["from"] == source_format.to_s }
          .map { |conv| conv["to"].to_sym }
      end

      # Get all supported conversions
      #
      # @return [Array<Hash>] Array of conversion hashes with :from and :to
      def all_conversions
        return [] unless conversion_matrix

        conversions = conversion_matrix["conversions"]
        return [] unless conversions

        conversions.map do |conv|
          { from: conv["from"].to_sym, to: conv["to"].to_sym }
        end
      end

      private

      # Load conversion matrix from YAML config
      #
      # @param path [String, nil] Path to config file
      def load_conversion_matrix(path)
        config_path = path || default_conversion_matrix_path

        @conversion_matrix = if File.exist?(config_path)
                               YAML.load_file(config_path)
                             else
                               # Use default inline matrix if file doesn't exist
                               default_conversion_matrix
                             end
      rescue StandardError => e
        warn "Failed to load conversion matrix: #{e.message}"
        @conversion_matrix = default_conversion_matrix
      end

      # Get default conversion matrix path
      #
      # @return [String] Path to conversion matrix config
      def default_conversion_matrix_path
        File.join(
          __dir__,
          "..",
          "config",
          "conversion_matrix.yml",
        )
      end

      # Get default conversion matrix (fallback)
      #
      # @return [Hash] Default conversion matrix
      def default_conversion_matrix
        {
          "conversions" => [
            { "from" => "ttf", "to" => "ttf" },
            { "from" => "otf", "to" => "otf" },
            { "from" => "ttf", "to" => "otf" },
            { "from" => "otf", "to" => "ttf" },
          ],
        }
      end

      # Validate conversion parameters
      #
      # @param font [Object] Font object
      # @param target_format [Symbol] Target format
      # @raise [ArgumentError] If parameters are invalid
      def validate_parameters!(font, target_format)
        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:table)
          raise ArgumentError, "Font must respond to :table method"
        end

        unless target_format.is_a?(Symbol)
          raise ArgumentError,
                "target_format must be a Symbol, got: #{target_format.class}"
        end
      end

      # Validate conversion is supported
      #
      # @param source_format [Symbol] Source format
      # @param target_format [Symbol] Target format
      # @raise [Error] If conversion is not supported
      def validate_conversion_supported!(source_format, target_format)
        unless supported?(source_format, target_format)
          available = supported_targets(source_format)
          message = "Conversion from #{source_format} to #{target_format} " \
                    "is not supported."
          message += if available.any?
                       " Available targets for #{source_format}: " \
                                  "#{available.join(', ')}"
                     else
                       " No conversions available from #{source_format}."
                     end
          raise Fontisan::Error, message
        end
      end

      # Select conversion strategy
      #
      # @param source_format [Symbol] Source format
      # @param target_format [Symbol] Target format
      # @return [ConversionStrategy] Selected strategy
      # @raise [Error] If no strategy supports the conversion
      def select_strategy(source_format, target_format)
        strategy = strategies.find do |s|
          s.supports?(source_format, target_format)
        end

        unless strategy
          raise Fontisan::Error,
                "No strategy available for #{source_format} → #{target_format}"
        end

        strategy
      end

      # Detect font format from tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to detect
      # @return [Symbol] Format (:ttf or :otf)
      # @raise [Error] If format cannot be detected
      def detect_format(font)
        # Check for CFF/CFF2 tables (OpenType/CFF)
        if font.has_table?("CFF ") || font.has_table?("CFF2")
          :otf
        # Check for glyf table (TrueType)
        elsif font.has_table?("glyf")
          :ttf
        else
          raise Fontisan::Error,
                "Cannot detect font format: missing both CFF and glyf tables"
        end
      end
    end
  end
end
