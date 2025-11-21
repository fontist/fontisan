# frozen_string_literal: true

require_relative "base_command"
require_relative "../font_loader"
require_relative "../font_writer"
require "fileutils"

module Fontisan
  module Commands
    # Command for unpacking fonts from TTC/OTC collections
    #
    # This command extracts individual font files from a TTC (TrueType Collection)
    # or OTC (OpenType Collection) file. It can extract all fonts or a specific
    # font by index, optionally converting to different formats during extraction.
    #
    # @example Extract all fonts
    #   command = UnpackCommand.new(
    #     'family.ttc',
    #     output_dir: 'fonts/',
    #     format: :ttf
    #   )
    #   result = command.run
    #   puts "Extracted #{result[:fonts_extracted]} fonts"
    #
    # @example Extract specific font
    #   command = UnpackCommand.new(
    #     'family.ttc',
    #     output_dir: 'fonts/',
    #     font_index: 2
    #   )
    #   result = command.run
    class UnpackCommand
      # Initialize unpack command
      #
      # @param collection_path [String] Path to TTC/OTC file
      # @param options [Hash] Command options
      # @option options [String] :output_dir Output directory (required)
      # @option options [Integer] :font_index Extract specific font index (optional)
      # @option options [Symbol, String] :format Output format (ttf, otf, woff, woff2)
      # @option options [String] :prefix Filename prefix for extracted fonts
      # @option options [Boolean] :verbose Enable verbose output (default: false)
      # @raise [ArgumentError] if collection_path or output_dir is invalid
      def initialize(collection_path, options = {})
        @collection_path = collection_path
        @options = options
        @output_dir = options[:output_dir]
        @font_index = options[:font_index]
        @format = parse_format(options[:format])
        @prefix = options[:prefix]
        @verbose = options.fetch(:verbose, false)

        validate_options!
      end

      # Execute the unpack command
      #
      # Extracts fonts from the collection and writes them as individual files.
      #
      # @return [Hash] Result information with:
      #   - :collection [String] - Input collection path
      #   - :output_dir [String] - Output directory
      #   - :num_fonts [Integer] - Total fonts in collection
      #   - :fonts_extracted [Integer] - Number of fonts extracted
      #   - :extracted_files [Array<String>] - Paths to extracted files
      # @raise [Fontisan::Error] if unpacking fails
      def run
        puts "Loading collection from #{File.basename(@collection_path)}..." if @verbose

        # Load collection
        collection = load_collection

        # Create output directory
        FileUtils.mkdir_p(@output_dir) unless Dir.exist?(@output_dir)

        # Determine which fonts to extract
        indices_to_extract = determine_indices(collection)

        puts "Extracting #{indices_to_extract.size} font(s)..." if @verbose

        # Extract fonts
        extracted_files = extract_fonts(collection, indices_to_extract)

        # Display results
        if @verbose
          display_results(collection, extracted_files)
        end

        {
          collection: @collection_path,
          output_dir: @output_dir,
          num_fonts: collection.font_count,
          fonts_extracted: extracted_files.size,
          extracted_files: extracted_files,
        }
      rescue Fontisan::Error => e
        raise Fontisan::Error, "Collection unpacking failed: #{e.message}"
      rescue ArgumentError
        # Let ArgumentError propagate for validation errors
        raise
      rescue StandardError => e
        raise Fontisan::Error, "Unexpected error during unpacking: #{e.message}"
      end

      private

      # Validate command options
      #
      # @raise [ArgumentError] if options are invalid
      def validate_options!
        # Must have output directory
        unless @output_dir
          raise ArgumentError, "Output directory is required (--output-dir)"
        end

        # Check collection file exists
        unless File.exist?(@collection_path)
          raise ArgumentError, "Collection file not found: #{@collection_path}"
        end

        # Validate font index if provided
        if @font_index&.negative?
          raise ArgumentError, "Font index must be >= 0, got #{@font_index}"
        end
      end

      # Load collection file
      #
      # @return [TrueTypeCollection, OpenTypeCollection] Loaded collection
      # @raise [Fontisan::Error] if loading fails
      def load_collection
        # Try to detect format from extension
        ext = File.extname(@collection_path).downcase

        File.open(@collection_path, "rb") do |io|
          # Read tag to determine type
          tag = io.read(4)
          io.rewind

          unless tag == "ttcf"
            raise Fontisan::Error,
                  "Not a valid TTC/OTC file (invalid signature)"
          end

          # Load as TTC or OTC based on extension hint
          # Both use same structure, main difference is expected font types
          if ext == ".otc"
            require_relative "../open_type_collection"
            OpenTypeCollection.read(io)
          else
            require_relative "../true_type_collection"
            TrueTypeCollection.read(io)
          end
        end
      rescue Errno::ENOENT
        raise Fontisan::Error, "Collection file not found: #{@collection_path}"
      rescue BinData::ValidityError => e
        raise Fontisan::Error, "Invalid collection file: #{e.message}"
      end

      # Determine which font indices to extract
      #
      # @param collection [TrueTypeCollection, OpenTypeCollection] Collection
      # @return [Array<Integer>] Array of font indices
      # @raise [ArgumentError] if font_index is out of range
      def determine_indices(collection)
        if @font_index
          # Extract specific font
          if @font_index >= collection.font_count
            raise ArgumentError,
                  "Font index #{@font_index} out of range (collection has #{collection.font_count} fonts)"
          end
          [@font_index]
        else
          # Extract all fonts
          (0...collection.font_count).to_a
        end
      end

      # Extract fonts from collection
      #
      # @param collection [TrueTypeCollection, OpenTypeCollection] Collection
      # @param indices [Array<Integer>] Indices to extract
      # @return [Array<String>] Paths to extracted files
      def extract_fonts(collection, indices)
        extracted_files = []

        File.open(@collection_path, "rb") do |io|
          fonts = collection.extract_fonts(io)

          indices.each do |index|
            font = fonts[index]
            filename = generate_filename(font, index)
            output_path = File.join(@output_dir, filename)

            puts "  [#{index + 1}/#{indices.size}] Extracting to #{filename}..." if @verbose

            # Write font
            write_font(font, output_path)

            extracted_files << output_path
          end
        end

        extracted_files
      end

      # Generate output filename for extracted font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font object
      # @param index [Integer] Font index
      # @return [String] Filename
      def generate_filename(font, index)
        # Try to get font name from name table
        base_name = nil
        if font.respond_to?(:table) && font.table("name")
          name_table = font.table("name")
          # Try to get PostScript name, then family name
          base_name = name_table.english_name(Tables::Name::POSTSCRIPT_NAME) ||
            name_table.english_name(Tables::Name::FAMILY)
        end

        # Fallback to prefix or generic name
        base_name ||= @prefix || "font"
        base_name = "#{base_name}_#{index}" unless @font_index

        # Clean filename
        base_name = base_name.gsub(/[^a-zA-Z0-9_-]/, "_")

        # Add extension based on format
        ext = format_extension
        "#{base_name}#{ext}"
      end

      # Write font to file
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font object
      # @param output_path [String] Output file path
      # @return [void]
      def write_font(font, output_path)
        if @format
          # Convert to specified format
          convert_and_write(font, output_path)
        else
          # Write in native format
          font.to_file(output_path)
        end
      end

      # Convert font and write to file
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font object
      # @param output_path [String] Output file path
      # @return [void]
      def convert_and_write(font, output_path)
        require_relative "../converters/format_converter"

        converter = Converters::FormatConverter.new
        converter.convert(font, @format, output_path: output_path)
      rescue StandardError => e
        raise Fontisan::Error, "Format conversion failed: #{e.message}"
      end

      # Parse format option
      #
      # @param format [Symbol, String, nil] Format option
      # @return [Symbol, nil] Parsed format
      def parse_format(format)
        return nil unless format

        return format if format.is_a?(Symbol)

        case format.to_s.downcase
        when "ttf"
          :ttf
        when "otf"
          :otf
        when "woff"
          :woff
        when "woff2"
          :woff2
        end
      end

      # Get file extension for format
      #
      # @return [String] File extension with dot
      def format_extension
        case @format
        when :ttf
          ".ttf"
        when :otf
          ".otf"
        when :woff
          ".woff"
        when :woff2
          ".woff2"
        else
          # Detect from collection type
          ext = File.extname(@collection_path).downcase
          ext == ".otc" ? ".otf" : ".ttf"
        end
      end

      # Display extraction results
      #
      # @param collection [TrueTypeCollection, OpenTypeCollection] Collection
      # @param extracted_files [Array<String>] Extracted file paths
      # @return [void]
      def display_results(collection, extracted_files)
        puts "\n=== Extraction Complete ==="
        puts "Collection: #{File.basename(@collection_path)}"
        puts "Total fonts: #{collection.font_count}"
        puts "Extracted: #{extracted_files.size}"
        puts "Output directory: #{@output_dir}"
        puts "\nExtracted files:"
        extracted_files.each do |path|
          size = File.size(path)
          puts "  - #{File.basename(path)} (#{format_bytes(size)})"
        end
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
