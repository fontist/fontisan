# frozen_string_literal: true

require_relative "base_command"
require_relative "../pipeline/transformation_pipeline"
require_relative "../converters/collection_converter"
require_relative "../conversion_options"
require_relative "../font_loader"

module Fontisan
  module Commands
    # Command for converting fonts between formats
    #
    # [`ConvertCommand`](lib/fontisan/commands/convert_command.rb) provides
    # CLI interface for font format conversion operations using the universal
    # transformation pipeline. It supports:
    # - Same-format operations (copy/optimize)
    # - TTF ↔ OTF outline format conversion
    # - Variable font operations (preserve/instance generation)
    # - WOFF/WOFF2 compression
    #
    # The command uses [`TransformationPipeline`](lib/fontisan/pipeline/transformation_pipeline.rb)
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
    # @example Generate instance at coordinates
    #   command = ConvertCommand.new(
    #     'variable.ttf',
    #     to: 'ttf',
    #     output: 'bold.ttf',
    #     coordinates: 'wght=700,wdth=100'
    #   )
    #   command.run
    #
    # @example Convert with ConversionOptions
    #   options = ConversionOptions.recommended(from: :ttf, to: :otf)
    #   command = ConvertCommand.new(
    #     'input.ttf',
    #     to: 'otf',
    #     output: 'output.otf',
    #     options: options
    #   )
    #   command.run
    class ConvertCommand < BaseCommand
      # Initialize convert command
      #
      # @param font_path [String] Path to input font file
      # @param options [Hash] Conversion options
      # @option options [String] :to Target format (ttf, otf, woff, woff2)
      # @option options [String] :output Output file path (required)
      # @option options [Integer] :font_index Index for TTC/OTC (default: 0)
      # @option options [String] :coordinates Coordinate string (e.g., "wght=700,wdth=100")
      # @option options [Hash] :instance_coordinates Axis coordinates hash (e.g., {"wght" => 700.0})
      # @option options [Integer] :instance_index Named instance index
      # @option options [Boolean] :preserve_variation Preserve variation data (default: auto)
      # @option options [Boolean] :preserve_hints Preserve rendering hints (default: false)
      # @option options [String] :target_format Target outline format for collections: 'preserve' (default), 'ttf', or 'otf'
      # @option options [Boolean] :no_validate Skip output validation
      # @option options [Boolean] :verbose Verbose output
      # @option options [ConversionOptions] :options ConversionOptions object
      def initialize(font_path, options = {})
        super(font_path, options)

        # Convert string keys to symbols for Thor compatibility
        opts = options.transform_keys(&:to_sym)

        @output_path = opts[:output]

        # Parse target format
        @target_format = parse_target_format(opts[:to])

        # Extract ConversionOptions if provided
        @conv_options = extract_conversion_options(opts)

        # Parse coordinates if string provided
        @coordinates = if opts[:coordinates]
                         parse_coordinates(opts[:coordinates])
                       elsif opts[:instance_coordinates]
                         opts[:instance_coordinates]
                       end

        @instance_index = opts[:instance_index]
        @preserve_variation = opts[:preserve_variation]
        @preserve_hints = opts.fetch(:preserve_hints, false)
        @collection_target_format = opts.fetch(:target_format, "preserve").to_s
        @validate = !opts[:no_validate]
      end

      # Execute the conversion
      #
      # @return [Hash] Result information
      # @raise [ArgumentError] If output path is not specified
      # @raise [Error] If conversion fails
      def run
        validate_options!

        # Check if input is a collection
        if collection_file?
          convert_collection
        else
          convert_single_font
        end
      rescue ArgumentError
        # Let ArgumentError propagate for validation errors
        raise
      rescue StandardError => e
        raise Error, "Conversion failed: #{e.message}"
      end

      private

      # Check if input file is a collection
      #
      # @return [Boolean] true if collection
      def collection_file?
        FontLoader.collection?(font_path)
      rescue StandardError
        # If detection fails, assume single font
        false
      end

      # Convert a single font (original implementation)
      #
      # @return [Hash] Result information
      def convert_single_font
        puts "Converting #{File.basename(font_path)} to #{@target_format}..." unless @options[:quiet]

        # Build pipeline options
        pipeline_options = {
          target_format: @target_format,
          validate: @validate,
          verbose: @options[:verbose],
        }

        # Add ConversionOptions if available
        pipeline_options[:conversion_options] = @conv_options if @conv_options

        # Add variation options if specified
        pipeline_options[:coordinates] = @coordinates if @coordinates
        pipeline_options[:instance_index] = @instance_index if @instance_index
        unless @preserve_variation.nil?
          pipeline_options[:preserve_variation] =
            @preserve_variation
        end

        # Add hint preservation option
        pipeline_options[:preserve_hints] = @preserve_hints if @preserve_hints

        # Use TransformationPipeline for universal conversion
        pipeline = Pipeline::TransformationPipeline.new(
          font_path,
          @output_path,
          pipeline_options,
        )

        result = pipeline.transform

        # Display results
        unless @options[:quiet]
          output_size = File.size(@output_path)
          input_size = File.size(font_path)

          puts "Conversion complete!"
          puts "  Input:  #{font_path} (#{format_size(input_size)})"
          puts "  Output: #{@output_path} (#{format_size(output_size)})"
          puts "  Format: #{result[:details][:source_format]} → #{result[:details][:target_format]}"

          if result[:details][:variation_preserved]
            puts "  Variation: Preserved (#{result[:details][:variation_strategy]})"
          elsif result[:details][:variation_strategy] != :preserve
            puts "  Variation: Instance generated (#{result[:details][:variation_strategy]})"
          end
        end

        {
          success: true,
          input_path: font_path,
          output_path: @output_path,
          source_format: result[:details][:source_format],
          target_format: result[:details][:target_format],
          input_size: File.size(font_path),
          output_size: File.size(@output_path),
          variation_strategy: result[:details][:variation_strategy],
        }
      end

      # Convert a collection
      #
      # @return [Hash] Result information
      def convert_collection
        # Determine target collection type from target format
        target_type = collection_type_from_format(@target_format)

        unless target_type
          raise ArgumentError,
                "Target format #{@target_format} is not a collection format. " \
                "Use ttc, otc, or dfont for collection conversion."
        end

        puts "Converting collection to #{target_type.to_s.upcase}..." unless @options[:quiet]

        # Use CollectionConverter
        converter = Converters::CollectionConverter.new
        result = converter.convert(
          font_path,
          target_type: target_type,
          options: {
            output: @output_path,
            target_format: @collection_target_format,
            verbose: @options[:verbose],
            options: @conv_options, # Pass ConversionOptions
          },
        )

        # Display results
        unless @options[:quiet]
          output_size = File.size(@output_path)
          input_size = File.size(font_path)

          puts "Conversion complete!"
          puts "  Input:  #{font_path} (#{format_size(input_size)})"
          puts "  Output: #{@output_path} (#{format_size(output_size)})"
          puts "  Format: #{result[:source_type].to_s.upcase} → #{result[:target_type].to_s.upcase}"
          puts "  Fonts:  #{result[:num_fonts]}"
        end

        {
          success: true,
          input_path: font_path,
          output_path: @output_path,
          source_format: result[:source_type],
          target_format: result[:target_type],
          input_size: File.size(font_path),
          output_size: File.size(@output_path),
          num_fonts: result[:num_fonts],
        }
      end

      # Determine collection type from format
      #
      # @param format [Symbol] Target format
      # @return [Symbol, nil] Collection type (:ttc, :otc, :dfont) or nil
      def collection_type_from_format(format)
        case format
        when :ttc
          :ttc
        when :otc
          :otc
        when :dfont
          :dfont
        else
          # Check output extension
          ext = File.extname(@output_path).downcase
          case ext
          when ".ttc"
            :ttc
          when ".otc"
            :otc
          when ".dfont"
            :dfont
          end
        end
      end

      # Parse coordinates string to hash
      #
      # Parses strings like "wght=700,wdth=100" into {"wght" => 700.0, "wdth" => 100.0}
      #
      # @param coord_string [String] Coordinate string
      # @return [Hash] Parsed coordinates
      def parse_coordinates(coord_string)
        coords = {}
        coord_string.split(",").each do |pair|
          key, value = pair.split("=")
          next unless key && value

          coords[key.strip] = value.to_f
        end
        coords
      rescue StandardError => e
        raise ArgumentError,
              "Invalid coordinates format '#{coord_string}': #{e.message}"
      end

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
        when "ttc"
          :ttc
        when "otc"
          :otc
        when "dfont"
          :dfont
        when "svg"
          :svg
        when "woff"
          :woff
        when "woff2"
          :woff2
        when "type1", "type-1", "t1", "pfb", "pfa"
          :type1
        else
          raise ArgumentError,
                "Unknown target format: #{format}. " \
                "Supported: ttf, otf, type1, t1, ttc, otc, dfont, svg, woff, woff2"
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

      # Extract ConversionOptions from options hash
      #
      # @param options [Hash, ConversionOptions] Options or hash containing :options key
      # @return [ConversionOptions, nil] Extracted ConversionOptions or nil
      def extract_conversion_options(options)
        return options if options.is_a?(ConversionOptions)

        options[:options] if options.is_a?(Hash)
      end
    end
  end
end
