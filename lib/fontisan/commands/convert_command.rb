# frozen_string_literal: true

require_relative "base_command"
require_relative "../converters/format_converter"
require_relative "../font_writer"

module Fontisan
  module Commands
    # Command for converting fonts between formats
    #
    # [`ConvertCommand`](lib/fontisan/commands/convert_command.rb) provides
    # CLI interface for font format conversion operations. It supports:
    # - Same-format operations (copy/optimize)
    # - TTF ↔ OTF outline format conversion (foundation)
    # - Future: WOFF/WOFF2 compression, SVG export
    #
    # The command uses [`FormatConverter`](lib/fontisan/converters/format_converter.rb)
    # to orchestrate conversions with appropriate strategies.
    #
    # @example Convert TTF to OTF
    #   command = ConvertCommand.new(
    #     'input.ttf',
    #     to: 'otf',
    #     output: 'output.otf'
    #   )
    #   command.run
    #
    # @example Copy/optimize same format
    #   command = ConvertCommand.new(
    #     'input.ttf',
    #     to: 'ttf',
    #     output: 'optimized.ttf'
    #   )
    #   command.run
    class ConvertCommand < BaseCommand
      # Initialize convert command
      #
      # @param font_path [String] Path to input font file
      # @param options [Hash] Conversion options
      # @option options [String] :to Target format (ttf, otf, woff2, svg)
      # @option options [String] :output Output file path (required)
      # @option options [Integer] :font_index Index for TTC/OTC (default: 0)
      # @option options [Boolean] :optimize Enable subroutine optimization (TTF→OTF only)
      # @option options [Integer] :min_pattern_length Minimum pattern length for subroutines
      # @option options [Integer] :max_subroutines Maximum number of subroutines
      # @option options [Boolean] :optimize_ordering Optimize subroutine ordering
      def initialize(font_path, options = {})
        super(font_path, options)
        @target_format = parse_target_format(options[:to])
        @output_path = options[:output]
        @converter = Converters::FormatConverter.new

        # Optimization options
        @optimize = options[:optimize] || false
        @min_pattern_length = options[:min_pattern_length] || 10
        @max_subroutines = options[:max_subroutines] || 65_535
        @optimize_ordering = options[:optimize_ordering] != false
      end

      # Execute the conversion
      #
      # @return [Hash] Result information
      # @raise [ArgumentError] If output path is not specified
      # @raise [Error] If conversion fails
      def run
        validate_options!

        puts "Converting #{File.basename(font_path)} to #{@target_format}..."

        # Build converter options
        converter_options = {
          target_format: @target_format,
          optimize_subroutines: @optimize,
          min_pattern_length: @min_pattern_length,
          max_subroutines: @max_subroutines,
          optimize_ordering: @optimize_ordering,
          verbose: options[:verbose],
        }

        # Perform conversion with options
        result = @converter.convert(font, @target_format, converter_options)

        # Handle special formats that return complete binary/text
        if @target_format == :woff && result.is_a?(String)
          # WOFF returns complete binary
          File.binwrite(@output_path, result)
        elsif @target_format == :woff2 && result.is_a?(Hash) && result[:woff2_binary]
          File.binwrite(@output_path, result[:woff2_binary])
        elsif @target_format == :svg && result.is_a?(Hash) && result[:svg_xml]
          File.write(@output_path, result[:svg_xml])
        else
          # Standard table-based conversion
          tables = result

          # Determine sfnt version for output
          sfnt_version = determine_sfnt_version(@target_format)

          # Write output font
          FontWriter.write_to_file(tables, @output_path,
                                   sfnt_version: sfnt_version)

          # Display optimization results if available
          display_optimization_results(tables) if @optimize && options[:verbose]
        end

        output_size = File.size(@output_path)
        input_size = File.size(font_path)

        puts "Conversion complete!"
        puts "  Input:  #{font_path} (#{format_size(input_size)})"
        puts "  Output: #{@output_path} (#{format_size(output_size)})"

        {
          success: true,
          input_path: font_path,
          output_path: @output_path,
          source_format: detect_source_format,
          target_format: @target_format,
          input_size: input_size,
          output_size: output_size,
        }
      rescue NotImplementedError
        # Let NotImplementedError propagate for tests that expect it
        raise
      rescue Converters::ConversionStrategy => e
        handle_conversion_error(e)
      rescue ArgumentError
        # Let ArgumentError propagate for validation errors
        raise
      rescue StandardError => e
        raise Error, "Conversion failed: #{e.message}"
      end

      # Get list of supported conversions
      #
      # @return [Array<Hash>] List of supported conversions
      def self.supported_conversions
        converter = Converters::FormatConverter.new
        converter.all_conversions
      end

      # Check if a conversion is supported
      #
      # @param source [Symbol] Source format
      # @param target [Symbol] Target format
      # @return [Boolean] True if supported
      def self.supported?(source, target)
        converter = Converters::FormatConverter.new
        converter.supported?(source, target)
      end

      private

      # Validate command options
      #
      # @raise [ArgumentError] If required options are missing
      def validate_options!
        unless @output_path
          raise ArgumentError,
                "Output path is required. Use --output option."
        end

        unless @target_format
          raise ArgumentError,
                "Target format is required. Use --to option."
        end

        # Check if conversion is supported
        source_format = detect_source_format
        unless @converter.supported?(source_format, @target_format)
          available = @converter.supported_targets(source_format)
          message = "Conversion from #{source_format} to #{@target_format} " \
                    "is not supported."
          if available.any?
            message += " Available targets: #{available.join(', ')}"
          end
          raise ArgumentError, message
        end
      end

      # Parse target format from string/symbol
      #
      # @param format [String, Symbol, nil] Target format
      # @return [Symbol, nil] Parsed format symbol
      def parse_target_format(format)
        return nil if format.nil?

        format_str = format.to_s.downcase
        case format_str
        when "ttf", "truetype"
          :ttf
        when "otf", "opentype", "cff"
          :otf
        when "woff"
          :woff
        when "woff2"
          :woff2
        when "svg"
          :svg
        else
          raise ArgumentError,
                "Unknown target format: #{format}. " \
                "Supported: ttf, otf, woff2, svg"
        end
      end

      # Detect source font format
      #
      # @return [Symbol] Source format
      def detect_source_format
        # Check for CFF/CFF2 tables (OpenType/CFF)
        if font.has_table?("CFF ") || font.has_table?("CFF2")
          :otf
        # Check for glyf table (TrueType)
        elsif font.has_table?("glyf")
          :ttf
        else
          :unknown
        end
      end

      # Determine sfnt version for target format
      #
      # @param format [Symbol] Target format
      # @return [Integer] sfnt version
      def determine_sfnt_version(format)
        case format
        when :otf
          0x4F54544F # 'OTTO' for OpenType/CFF
        when :ttf
          0x00010000 # 1.0 for TrueType
        else
          0x00010000 # Default to TrueType
        end
      end

      # Format file size for display
      #
      # @param bytes [Integer] Size in bytes
      # @return [String] Formatted size
      def format_size(bytes)
        if bytes < 1024
          "#{bytes} bytes"
        elsif bytes < 1024 * 1024
          "#{(bytes / 1024.0).round(1)} KB"
        else
          "#{(bytes / (1024.0 * 1024)).round(1)} MB"
        end
      end

      # Handle conversion errors with helpful messages
      #
      # @param error [StandardError] The error that occurred
      # @raise [Error] Wrapped error with helpful message
      def handle_conversion_error(error)
        message = "Conversion failed: #{error.message}"

        # Add helpful hints based on error type
        if error.is_a?(NotImplementedError)
          message += "\n\nNote: Some conversions are not yet fully " \
                     "implemented. Check the conversion matrix configuration " \
                     "for implementation status."
        end

        raise Error, message
      end

      # Display optimization results from subroutine generation
      #
      # @param tables [Hash] Table data with optimization metadata
      def display_optimization_results(tables)
        optimization = tables.instance_variable_get(:@subroutine_optimization)
        return unless optimization

        puts "\n=== Subroutine Optimization Results ==="
        puts "  Patterns found: #{optimization[:pattern_count]}"
        puts "  Patterns selected: #{optimization[:selected_count]}"
        puts "  Subroutines generated: #{optimization[:local_subrs].length}"
        puts "  Estimated bytes saved: #{optimization[:savings]}"
        puts "  CFF bias: #{optimization[:bias]}"

        if optimization[:selected_count].zero?
          puts "  Note: No beneficial patterns found for optimization"
        elsif optimization[:savings].positive?
          savings_kb = (optimization[:savings] / 1024.0).round(1)
          puts "  Estimated space savings: #{savings_kb} KB"
        end
      end
    end
  end
end
