# frozen_string_literal: true

require_relative "conversion_strategy"
require_relative "table_copier"
require_relative "outline_converter"
require_relative "woff_writer"
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
          WoffWriter.new,
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
      # @option options [Boolean] :preserve_variation Preserve variation data
      #   (default: true)
      # @option options [Boolean] :preserve_hints Preserve rendering hints
      #   (default: false)
      # @option options [Hash] :instance_coordinates Coordinates for variable→SVG
      # @option options [Integer] :instance_index Named instance index for variable→SVG
      # @return [Hash<String, String>] Map of table tags to binary data
      # @raise [ArgumentError] If parameters are invalid
      # @raise [Error] If conversion is not supported
      #
      # @example
      #   tables = converter.convert(font, :otf)
      #
      # @example Variable font to SVG at specific weight
      #   result = converter.convert(variable_font, :svg, instance_coordinates: { "wght" => 700.0 })
      #
      # @example Convert with hint preservation
      #   tables = converter.convert(font, :otf, preserve_hints: true)
      def convert(font, target_format, options = {})
        validate_parameters!(font, target_format)

        source_format = detect_format(font)
        validate_conversion_supported!(source_format, target_format)

        # Special case: Variable font to SVG
        if variable_font?(font) && target_format == :svg
          return convert_variable_to_svg(font, options)
        end

        strategy = select_strategy(source_format, target_format)
        tables = strategy.convert(font,
                                  options.merge(target_format: target_format))

        # Preserve variation data if requested and font is variable
        if options.fetch(:preserve_variation, true) && variable_font?(font)
          tables = preserve_variation_data(
            font,
            tables,
            source_format,
            target_format,
            options,
          )
        end

        tables
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

      # Convert variable font to SVG at specific coordinates
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font
      # @param options [Hash] Conversion options
      # @option options [Hash] :instance_coordinates Design space coordinates
      # @option options [Integer] :instance_index Named instance index
      # @return [Hash] Hash with :svg_xml key
      def convert_variable_to_svg(font, options = {})
        require_relative "../variation/variable_svg_generator"

        coordinates = options[:instance_coordinates] || {}
        generator = Variation::VariableSvgGenerator.new(font, coordinates)

        # Use named instance if specified
        if options[:instance_index]
          generator.generate_named_instance(options[:instance_index], options)
        else
          generator.generate(options)
        end
      end

      # Check if font is a variable font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to check
      # @return [Boolean] True if font has fvar table
      def variable_font?(font)
        font.has_table?("fvar")
      end

      # Preserve variation data from source to target
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param tables [Hash<String, String>] Target tables
      # @param source_format [Symbol] Source format
      # @param target_format [Symbol] Target format
      # @param options [Hash] Preservation options
      # @return [Hash<String, String>] Tables with variation preserved
      def preserve_variation_data(font, tables, source_format, target_format,
options)
        # Case 1: Compatible formats (same outline format) - just copy tables
        if compatible_variation_formats?(source_format, target_format)
          require_relative "../variation/variation_preserver"
          Variation::VariationPreserver.preserve(font, tables, options)

        # Case 2: Different outline formats - convert variation data
        elsif convertible_variation_formats?(source_format, target_format)
          convert_variation_data(font, tables, source_format, target_format,
                                 options)

        # Case 3: Unsupported conversion
        else
          if options[:preserve_variation]
            raise Fontisan::Error,
                  "Cannot preserve variation data for " \
                  "#{source_format} → #{target_format}"
          end
          tables
        end
      end

      # Check if formats have compatible variation (same outline format)
      #
      # @param source [Symbol] Source format
      # @param target [Symbol] Target format
      # @return [Boolean] True if compatible
      def compatible_variation_formats?(source, target)
        # Same format (copy operation)
        return true if source == target

        # Same outline format (just packaging change)
        (source == :ttf && target == :woff) ||
          (source == :otf && target == :woff) ||
          (source == :woff && target == :ttf) ||
          (source == :woff && target == :otf) ||
          (source == :ttf && target == :woff2) ||
          (source == :otf && target == :woff2)
      end

      # Check if formats allow variation conversion (different outline formats)
      #
      # @param source [Symbol] Source format
      # @param target [Symbol] Target format
      # @return [Boolean] True if convertible
      def convertible_variation_formats?(source, target)
        # Different outline formats (need variation conversion)
        (source == :ttf && target == :otf) ||
          (source == :otf && target == :ttf)
      end

      # Convert variation data between outline formats
      #
      # This is a placeholder for full TTF↔OTF variation conversion.
      # Full implementation would:
      # 1. Use Variation::Converter to convert gvar ↔ CFF2 blend
      # 2. Build appropriate variation tables for target format
      # 3. Preserve common tables (fvar, avar, STAT, metrics)
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param tables [Hash<String, String>] Target tables
      # @param source_format [Symbol] Source format
      # @param target_format [Symbol] Target format
      # @param options [Hash] Conversion options
      # @return [Hash<String, String>] Tables with converted variation
      def convert_variation_data(font, tables, source_format, target_format,
_options)
        require_relative "../variation/variation_preserver"
        require_relative "../variation/converter"

        # For now, just preserve common tables and warn about conversion
        warn "WARNING: Full variation conversion (#{source_format} → " \
             "#{target_format}) not yet implemented. " \
             "Preserving common variation tables only."

        # Preserve common tables (fvar, avar, STAT) but not format-specific
        Variation::VariationPreserver.preserve(
          font,
          tables,
          preserve_format_specific: false,
          preserve_metrics: true,
        )
      end

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
