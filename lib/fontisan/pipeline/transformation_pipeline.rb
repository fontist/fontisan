# frozen_string_literal: true

require_relative "format_detector"
require_relative "variation_resolver"
require_relative "../converters/format_converter"
require_relative "../font_loader"
require_relative "../font_writer"
require_relative "output_writer"

module Fontisan
  module Pipeline
    # Orchestrates universal font transformation pipeline
    #
    # This is the main entry point for font conversion operations. It coordinates:
    # 1. Format detection (via FormatDetector)
    # 2. Font loading (via FontLoader)
    # 3. Variation resolution (via VariationResolver)
    # 4. Format conversion (via FormatConverter)
    # 5. Output writing (via OutputWriter)
    # 6. Validation (optional, via Validation::Validator)
    #
    # The pipeline follows a clear MECE architecture where each phase has a
    # single responsibility and produces well-defined outputs.
    #
    # @example Basic TTF to OTF conversion
    #   pipeline = TransformationPipeline.new("input.ttf", "output.otf")
    #   result = pipeline.transform
    #   puts result[:success] # => true
    #
    # @example Variable font instance generation
    #   pipeline = TransformationPipeline.new(
    #     "variable.ttf",
    #     "bold.ttf",
    #     coordinates: { "wght" => 700.0 }
    #   )
    #   result = pipeline.transform
    class TransformationPipeline
      # @return [String] Input file path
      attr_reader :input_path

      # @return [String] Output file path
      attr_reader :output_path

      # @return [Hash] Transformation options
      attr_reader :options

      # Initialize transformation pipeline
      #
      # @param input_path [String] Path to input font
      # @param output_path [String] Path to output font
      # @param options [Hash] Transformation options
      # @option options [Symbol] :target_format Target format (:ttf, :otf, :woff, :woff2)
      # @option options [Hash] :coordinates Instance coordinates (for variable fonts)
      # @option options [Integer] :instance_index Named instance index
      # @option options [Boolean] :preserve_variation Preserve variation data (default: auto)
      # @option options [Boolean] :validate Validate output (default: true)
      # @option options [Boolean] :verbose Verbose output (default: false)
      def initialize(input_path, output_path, options = {})
        @input_path = input_path
        @output_path = output_path
        @options = default_options.merge(options)
        @variation_strategy = nil

        validate_paths!
      end

      # Execute transformation pipeline
      #
      # This is the main entry point. It orchestrates:
      # 1. Format detection
      # 2. Font loading
      # 3. Variation resolution
      # 4. Format conversion
      # 5. Output writing
      # 6. Validation (optional)
      #
      # @return [Hash] Transformation result with :success, :output_path, :details
      # @raise [Error] If transformation fails
      def transform
        log "Starting transformation: #{@input_path} → #{@output_path}"

        # Phase 1: Detect input format
        detection = detect_input_format
        log "Detected: #{detection[:format]} (#{detection[:variation_type]})"

        # Phase 2: Load font
        font = load_font(detection)
        log "Loaded: #{font.class.name}"

        # Phase 3: Resolve variation
        tables = resolve_variation(font, detection)
        log "Resolved variation using #{@variation_strategy} strategy"

        # Phase 4: Convert format
        tables = convert_format(tables, detection)
        log "Converted to #{target_format}"

        # Phase 5: Write output
        write_output(tables, detection)
        log "Written to #{@output_path}"

        # Phase 6: Validate (optional)
        validate_output if @options[:validate] && !same_format_conversion? && !export_only_format?
        log "Validation passed" if @options[:validate] && !export_only_format?

        {
          success: true,
          output_path: @output_path,
          details: build_details(detection),
        }
      rescue StandardError => e
        handle_error(e)
      end

      private

      # Detect input format and capabilities
      #
      # @return [Hash] Detection results from FormatDetector
      def detect_input_format
        detector = FormatDetector.new(@input_path)
        detector.detect
      end

      # Load font with appropriate mode
      #
      # @param detection [Hash] Detection results
      # @return [Font] Loaded font object
      def load_font(_detection)
        FontLoader.load(@input_path, mode: :full)
      end

      # Resolve variation data
      #
      # @param font [Font] Loaded font
      # @param detection [Hash] Detection results
      # @return [Hash] Processed font tables
      def resolve_variation(font, detection)
        # Static fonts - use preserve strategy (just copy tables)
        return resolve_static_font(font) if detection[:variation_type] == :static

        # Variable fonts - determine strategy
        strategy = determine_variation_strategy(detection)
        @variation_strategy = strategy

        resolver = VariationResolver.new(
          font,
          strategy: strategy,
          **variation_options,
        )

        resolver.resolve
      end

      # Resolve static font (just copy tables)
      #
      # @param font [Font] Static font
      # @return [Hash] Font tables
      def resolve_static_font(font)
        @variation_strategy = :preserve

        # Get all tables from font - use table_data directly
        font.table_data.dup
      end

      # Determine variation strategy based on options and compatibility
      #
      # @param detection [Hash] Detection results
      # @return [Symbol] Strategy type (:preserve, :instance, :named)
      def determine_variation_strategy(detection)
        # User explicitly requested instance generation
        if @options[:coordinates] || @options[:instance_index]
          return @options[:instance_index] ? :named : :instance
        end

        # Check if preservation is possible
        if can_preserve_variation?(detection)
          @options.fetch(:preserve_variation, true) ? :preserve : :instance
        else
          # Cannot preserve - must generate instance
          :instance
        end
      end

      # Check if variation can be preserved for target format
      #
      # @param detection [Hash] Detection results
      # @return [Boolean] True if variation preservable
      def can_preserve_variation?(detection)
        source_format = detection[:format]
        target = target_format

        # Same format
        return true if source_format == target

        # Same outline family (packaging change only)
        same_outline_family?(source_format, target)
      end

      # Check if formats are in same outline family
      #
      # @param source [Symbol] Source format
      # @param target [Symbol] Target format
      # @return [Boolean] True if same family
      def same_outline_family?(source, target)
        truetype_formats = %i[ttf ttc woff woff2]
        opentype_formats = %i[otf otc woff woff2]

        (truetype_formats.include?(source) && truetype_formats.include?(target)) ||
          (opentype_formats.include?(source) && opentype_formats.include?(target))
      end

      # Convert format if needed
      #
      # @param tables [Hash] Font tables
      # @param detection [Hash] Detection results
      # @return [Hash] Converted tables
      def convert_format(tables, detection)
        source_format = detection[:format]
        target = target_format

        # No conversion needed for same format
        return tables if source_format == target

        # Use FormatConverter for outline conversion
        if needs_outline_conversion?(source_format, target) || target == :svg
          converter = Converters::FormatConverter.new
          # Create temporary font object from tables
          font = build_font_from_tables(tables, source_format)
          converter.convert(font, target, @options)
        else
          # Just packaging change - tables can be used as-is
          tables
        end
      end

      # Check if outline conversion is needed
      #
      # @param source [Symbol] Source format
      # @param target [Symbol] Target format
      # @return [Boolean] True if outline conversion needed
      def needs_outline_conversion?(source, target)
        # TTF ↔ OTF requires outline conversion
        ttf_formats = %i[ttf ttc woff woff2]
        otf_formats = %i[otf otc]

        (ttf_formats.include?(source) && otf_formats.include?(target)) ||
          (otf_formats.include?(source) && ttf_formats.include?(target))
      end

      # Write output font file
      #
      # @param tables [Hash] Font tables
      # @param detection [Hash] Detection results
      def write_output(tables, _detection)
        writer = OutputWriter.new(@output_path, target_format, @options)
        writer.write(tables)
      end

      # Validate output file
      #
      # @raise [ValidationError] If validation fails
      def validate_output
        return unless File.exist?(@output_path)

        require_relative "../validation/validator"

        # Load font for validation
        font = FontLoader.load(@output_path, mode: :full)
        validator = Validation::Validator.new
        result = validator.validate(font, @output_path)

        return if result.valid

        error_messages = result.errors.map(&:message).join(", ")
        raise Error, "Output validation failed: #{error_messages}"
      end

      # Get target format
      #
      # @return [Symbol] Target format
      def target_format
        @options[:target_format] || detect_target_from_extension
      end

      # Detect target format from output path extension
      #
      # @return [Symbol] Detected format
      def detect_target_from_extension
        ext = File.extname(@output_path).downcase
        case ext
        when ".ttf" then :ttf
        when ".otf" then :otf
        when ".woff" then :woff
        when ".woff2" then :woff2
        else
          raise ArgumentError,
                "Cannot determine target format from extension: #{ext}"
        end
      end

      # Get variation options for VariationResolver
      #
      # @return [Hash] Variation options
      def variation_options
        opts = {}
        opts[:coordinates] = @options[:coordinates] if @options[:coordinates]
        if @options[:instance_index]
          opts[:instance_index] =
            @options[:instance_index]
        end
        opts
      end

      # Validate input and output paths
      #
      # @raise [ArgumentError] If paths invalid
      def validate_paths!
        unless File.exist?(@input_path)
          raise ArgumentError, "Input file not found: #{@input_path}"
        end

        output_dir = File.dirname(@output_path)
        unless File.directory?(output_dir)
          raise ArgumentError, "Output directory not found: #{output_dir}"
        end
      end

      # Build font object from tables
      #
      # @param tables [Hash] Font tables
      # @param format [Symbol] Font format
      # @return [Font] Font object
      def build_font_from_tables(tables, format)
        # Detect outline type from tables
        has_cff = tables.key?("CFF ") || tables.key?("CFF2")
        has_glyf = tables.key?("glyf")

        if has_cff
          OpenTypeFont.from_tables(tables)
        elsif has_glyf
          TrueTypeFont.from_tables(tables)
        else
          # Default based on format
          case format
          when :ttf, :woff, :woff2
            TrueTypeFont.from_tables(tables)
          when :otf
            OpenTypeFont.from_tables(tables)
          else
            raise ArgumentError,
                  "Cannot determine font type: format=#{format}, has_cff=#{has_cff}, has_glyf=#{has_glyf}"
          end
        end
      end

      # Build transformation details
      #
      # @param detection [Hash] Detection results
      # @return [Hash] Transformation details
      def build_details(detection)
        {
          source_format: detection[:format],
          source_variation: detection[:variation_type],
          target_format: target_format,
          variation_strategy: @variation_strategy,
          variation_preserved: @variation_strategy == :preserve,
        }
      end

      # Handle transformation error
      #
      # @param error [StandardError] Error that occurred
      # @raise [Error] Re-raises with context
      def handle_error(error)
        log "ERROR: #{error.message}"
        log error.backtrace.first(5).join("\n") if @options[:verbose]

        raise Error, "Transformation failed: #{error.message}"
      end

      # Log message if verbose
      #
      # @param message [String] Message to log
      def log(message)
        puts "[TransformationPipeline] #{message}" if @options[:verbose]
      end

      # Default options
      #
      # @return [Hash] Default options
      def default_options
        {
          validate: true,
          verbose: false,
          preserve_variation: nil, # Auto-determine
        }
      end

      # Check if this is a same-format conversion
      #
      # @return [Boolean] True if source and target formats are the same
      def same_format_conversion?
        detection = detect_input_format
        detection[:format] == target_format
      end

      # Check if target format is export-only (cannot be validated)
      #
      # @return [Boolean] True if format is export-only
      def export_only_format?
        %i[svg woff woff2].include?(target_format)
      end
    end
  end
end
