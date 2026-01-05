# frozen_string_literal: true

require_relative "base_command"
require_relative "../collection/builder"
require_relative "../collection/dfont_builder"
require_relative "../font_loader"

module Fontisan
  module Commands
    # Command for packing multiple fonts into a TTC/OTC collection
    #
    # This command provides CLI access to font collection creation functionality.
    # It loads multiple font files and combines them into a single TTC (TrueType Collection)
    # or OTC (OpenType Collection) file with shared table deduplication to save space.
    # It also supports creating dfont (Apple Data Fork Font) suitcases.
    #
    # @example Pack fonts into TTC
    #   command = PackCommand.new(
    #     ['font1.ttf', 'font2.ttf', 'font3.ttf'],
    #     output: 'family.ttc',
    #     format: :ttc,
    #     optimize: true
    #   )
    #   result = command.run
    #   puts "Saved #{result[:space_savings]} bytes through table sharing"
    #
    # @example Pack with analysis
    #   command = PackCommand.new(
    #     ['Regular.otf', 'Bold.otf', 'Italic.otf'],
    #     output: 'family.otc',
    #     format: :otc,
    #     analyze: true
    #   )
    #   result = command.run
    #
    # @example Pack into dfont
    #   command = PackCommand.new(
    #     ['font1.ttf', 'font2.otf'],
    #     output: 'family.dfont',
    #     format: :dfont
    #   )
    #   result = command.run
    class PackCommand
      # Initialize pack command
      #
      # @param font_paths [Array<String>] Paths to input font files
      # @param options [Hash] Command options
      # @option options [String] :output Output file path (required)
      # @option options [Symbol, String] :format Format type (:ttc, :otc, or :dfont, default: auto-detect)
      # @option options [Boolean] :optimize Enable table sharing optimization (default: true)
      # @option options [Boolean] :analyze Show analysis report before building (default: false)
      # @option options [Boolean] :verbose Enable verbose output (default: false)
      # @raise [ArgumentError] if font_paths or output is invalid
      def initialize(font_paths, options = {})
        @font_paths = font_paths
        @options = options
        @output_path = options[:output]
        @format = options[:format] ? parse_format(options[:format]) : nil
        @optimize = options.fetch(:optimize, true)
        @analyze = options.fetch(:analyze, false)
        @verbose = options.fetch(:verbose, false)

        validate_options!
      end

      # Execute the pack command
      #
      # Loads all fonts, analyzes tables, and creates a TTC/OTC/dfont collection.
      # Optionally displays analysis before building.
      #
      # @return [Hash] Result information with:
      #   - :output [String] - Output file path
      #   - :output_size [Integer] - Output file size in bytes
      #   - :num_fonts [Integer] - Number of fonts packed
      #   - :format [Symbol] - Collection format (:ttc, :otc, or :dfont)
      #   - :space_savings [Integer] - Bytes saved through sharing (TTC/OTC only)
      #   - :sharing_percentage [Float] - Percentage of tables shared (TTC/OTC only)
      #   - :analysis [Hash] - Analysis report (if analyze option enabled)
      # @raise [ArgumentError] if options are invalid
      # @raise [Fontisan::Error] if packing fails
      def run
        puts "Loading #{@font_paths.size} fonts..." if @verbose

        # Load all fonts
        fonts = load_fonts

        # Auto-detect format if not specified
        @format ||= auto_detect_format(fonts)
        puts "Auto-detected format: #{@format}" if @verbose && !@options[:format]

        # Build collection based on format
        if @format == :dfont
          build_dfont(fonts)
        else
          build_ttc_otc(fonts)
        end
      rescue Fontisan::Error => e
        raise Fontisan::Error, "Collection packing failed: #{e.message}"
      rescue StandardError => e
        raise Fontisan::Error, "Unexpected error during packing: #{e.message}"
      end

      private

      # Build dfont collection
      #
      # @param fonts [Array] Loaded fonts
      # @return [Hash] Build result
      def build_dfont(fonts)
        puts "Building dfont suitcase..." if @verbose

        builder = Collection::DfontBuilder.new(fonts)
        result = builder.build_to_file(@output_path)

        if @verbose
          display_dfont_results(result)
        end

        result
      end

      # Build TTC/OTC collection
      #
      # @param fonts [Array] Loaded fonts
      # @return [Hash] Build result
      def build_ttc_otc(fonts)
        # Create builder
        builder = Collection::Builder.new(fonts, {
                                            format: @format,
                                            optimize: @optimize,
                                          })

        # Validate before building
        builder.validate!

        # Show analysis if requested
        if @analyze || @verbose
          show_analysis(builder)
        end

        # Build collection
        puts "Building #{@format.upcase} collection..." if @verbose
        result = builder.build_to_file(@output_path)

        # Display results
        if @verbose
          display_results(result)
        end

        result
      end

      # Auto-detect collection format based on fonts
      #
      # @param fonts [Array<TrueTypeFont, OpenTypeFont>] Loaded fonts
      # @return [Symbol] Detected format (:ttc, :otc, or :dfont)
      def auto_detect_format(fonts)
        # Check output extension first
        ext = File.extname(@output_path).downcase
        return :ttc if ext == ".ttc"
        return :otc if ext == ".otc"
        return :dfont if ext == ".dfont"

        # Detect based on font types
        has_truetype = fonts.any? { |f| truetype_font?(f) }
        has_opentype = fonts.any? { |f| opentype_font?(f) }

        if has_truetype && !has_opentype
          :ttc  # All TrueType
        elsif has_opentype
          :otc  # Has OpenType/CFF fonts
        else
          :ttc  # Default to TTC
        end
      end

      # Check if font is TrueType
      #
      # @param font [Object] Font object
      # @return [Boolean]
      def truetype_font?(font)
        return false unless font.respond_to?(:header)

        sfnt = font.header.sfnt_version
        [0x00010000, 0x74727565].include?(sfnt) # 0x74727565 = 'true'
      end

      # Check if font is OpenType/CFF
      #
      # @param font [Object] Font object
      # @return [Boolean]
      def opentype_font?(font)
        return false unless font.respond_to?(:header)

        sfnt = font.header.sfnt_version
        sfnt == 0x4F54544F # 'OTTO'
      end

      # Validate command options
      #
      # @raise [ArgumentError] if options are invalid
      def validate_options!
        # Must have output path
        unless @output_path
          raise ArgumentError, "Output path is required (--output)"
        end

        # Must have at least 2 fonts for collection
        if @font_paths.nil? || @font_paths.empty?
          raise ArgumentError, "Must specify at least 2 font files"
        end

        if @font_paths.size < 2
          raise ArgumentError,
                "Collection requires at least 2 fonts, got #{@font_paths.size}"
        end

        # Validate format if specified
        if @format && !%i[ttc otc dfont].include?(@format)
          raise ArgumentError,
                "Invalid format: #{@format}. Must be :ttc, :otc, or :dfont"
        end

        # Warn if output extension doesn't match format (if format specified)
        if @format
          ext = File.extname(@output_path).downcase
          expected_ext = ".#{@format}"
          if ext != expected_ext
            warn "Warning: Output extension '#{ext}' doesn't match format '#{@format}' (expected '#{expected_ext}')"
          end
        end
      end

      # Load all fonts
      #
      # @return [Array<TrueTypeFont, OpenTypeFont>] Loaded fonts
      # @raise [Fontisan::Error] if any font fails to load
      def load_fonts
        fonts = []

        @font_paths.each_with_index do |path, index|
          puts "  [#{index + 1}/#{@font_paths.size}] Loading #{File.basename(path)}..." if @verbose

          begin
            font = FontLoader.load(path)
            fonts << font
          rescue Errno::ENOENT
            raise Fontisan::Error, "Font file not found: #{path}"
          rescue StandardError => e
            raise Fontisan::Error, "Failed to load font '#{path}': #{e.message}"
          end
        end

        fonts
      end

      # Parse format option
      #
      # @param format [Symbol, String] Format option
      # @return [Symbol] Parsed format (:ttc, :otc, or :dfont)
      # @raise [ArgumentError] if format is invalid
      def parse_format(format)
        return format if format.is_a?(Symbol) && %i[ttc otc dfont].include?(format)

        case format.to_s.downcase
        when "ttc"
          :ttc
        when "otc"
          :otc
        when "dfont"
          :dfont
        else
          raise ArgumentError,
                "Invalid format: #{format}. Must be 'ttc', 'otc', or 'dfont'"
        end
      end

      # Show analysis report
      #
      # @param builder [Collection::Builder] Collection builder
      # @return [void]
      def show_analysis(builder)
        puts "\n=== Collection Analysis ==="

        analysis = builder.analyze

        puts "Total fonts: #{analysis[:total_fonts]}"
        puts "Shared tables: #{analysis[:shared_tables].size}"
        puts "Potential space savings: #{format_bytes(analysis[:space_savings])}"
        puts "Table sharing: #{analysis[:sharing_percentage]}%"

        if @verbose && analysis[:shared_tables].any?
          puts "\nShared table details:"
          analysis[:shared_tables].each do |tag, groups|
            groups.each do |group|
              font_indices = group[:font_indices]
              puts "  #{tag}: shared by fonts #{font_indices.join(', ')}"
            end
          end
        end

        puts ""
      end

      # Display build results
      #
      # @param result [Hash] Build result
      # @return [void]
      def display_results(result)
        puts "\n=== Collection Created ==="
        puts "Output: #{result[:output_path]}"
        puts "Format: #{result[:format].upcase}"
        puts "Fonts: #{result[:num_fonts]}"
        puts "Size: #{format_bytes(result[:output_size])}"
        puts "Space saved: #{format_bytes(result[:space_savings])}"
        puts "Sharing: #{result[:statistics][:sharing_percentage]}%"
        puts ""
      end

      # Display dfont build results
      #
      # @param result [Hash] Build result
      # @return [void]
      def display_dfont_results(result)
        puts "\n=== dfont Suitcase Created ==="
        puts "Output: #{result[:output_path]}"
        puts "Format: #{result[:format].upcase}"
        puts "Fonts: #{result[:num_fonts]}"
        puts "Size: #{format_bytes(result[:total_size])}"
        puts ""
      end

      # Format bytes for display
      #
      # @param bytes [Integer] Byte count
      # @return [String] Formatted string
      def format_bytes(bytes)
        if bytes < 1024
          "#{bytes} B"
        elsif bytes < 1024 * 1024
          "#{(bytes / 1024.0).round(2)} KB"
        else
          "#{(bytes / (1024.0 * 1024)).round(2)} MB"
        end
      end
    end
  end
end
