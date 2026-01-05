# frozen_string_literal: true

require_relative "format_converter"
require_relative "../collection/builder"
require_relative "../collection/dfont_builder"
require_relative "../parsers/dfont_parser"
require_relative "../font_loader"

module Fontisan
  module Converters
    # CollectionConverter handles conversion between collection formats
    #
    # Main responsibility: Convert between TTC, OTC, and dfont collection
    # formats using a three-step strategy:
    # 1. Unpack: Extract individual fonts from source collection
    # 2. Convert: Transform each font's outline format if requested
    # 3. Repack: Rebuild collection in target format
    #
    # Supported conversions:
    # - TTC ↔ OTC (preserves mixed TTF+OTF by default)
    # - TTC → dfont (repackage)
    # - OTC → dfont (repackage)
    # - dfont → TTC (preserves mixed formats)
    # - dfont → OTC (preserves mixed formats)
    #
    # @example Convert TTC to OTC (preserve formats)
    #   converter = CollectionConverter.new
    #   result = converter.convert(ttc_path, target_type: :otc, output: 'family.otc')
    #
    # @example Convert TTC to OTC with outline conversion
    #   converter = CollectionConverter.new
    #   result = converter.convert(ttc_path, target_type: :otc,
    #                              options: { output: 'family.otc', convert_outlines: true })
    #
    # @example Convert dfont to TTC
    #   converter = CollectionConverter.new
    #   result = converter.convert(dfont_path, target_type: :ttc, output: 'family.ttc')
    class CollectionConverter
      # Convert collection to target format
      #
      # @param collection_path [String] Path to source collection
      # @param target_type [Symbol] Target collection type (:ttc, :otc, :dfont)
      # @param options [Hash] Conversion options
      # @option options [String] :output Output file path (required)
      # @option options [String] :target_format Target outline format: 'preserve' (default), 'ttf', or 'otf'
      # @option options [Boolean] :optimize Enable table sharing (default: true, TTC/OTC only)
      # @option options [Boolean] :verbose Enable verbose output (default: false)
      # @return [Hash] Conversion result with:
      #   - :input [String] - Input collection path
      #   - :output [String] - Output collection path
      #   - :source_type [Symbol] - Source collection type
      #   - :target_type [Symbol] - Target collection type
      #   - :num_fonts [Integer] - Number of fonts converted
      #   - :conversions [Array<Hash>] - Per-font conversion details
      # @raise [ArgumentError] if parameters invalid
      # @raise [Error] if conversion fails
      def convert(collection_path, target_type:, options: {})
        validate_parameters!(collection_path, target_type, options)

        verbose = options.fetch(:verbose, false)
        output_path = options[:output]
        target_format = options.fetch(:target_format, 'preserve').to_s

        # Validate target_format
        unless %w[preserve ttf otf].include?(target_format)
          raise ArgumentError, "Invalid target_format: #{target_format}. Must be 'preserve', 'ttf', or 'otf'"
        end

        puts "Converting collection to #{target_type.to_s.upcase}..." if verbose

        # Step 1: Unpack - extract fonts from source collection
        puts "  Unpacking fonts from source collection..." if verbose
        fonts, source_type = unpack_fonts(collection_path)

        # Check if conversion is needed
        if source_type == target_type
          puts "  Source and target formats are the same, copying collection..." if verbose
          FileUtils.cp(collection_path, output_path)
          return build_result(collection_path, output_path, source_type, target_type, fonts.size, [])
        end

        # Step 2: Convert - transform fonts if requested
        puts "  Converting #{fonts.size} font(s)..." if verbose
        converted_fonts, conversions = convert_fonts(fonts, source_type, target_type, options.merge(target_format: target_format))

        # Step 3: Repack - build target collection
        puts "  Repacking into #{target_type.to_s.upcase} format..." if verbose
        repack_fonts(converted_fonts, target_type, output_path, options)

        # Build result
        result = build_result(collection_path, output_path, source_type, target_type, fonts.size, conversions)

        if verbose
          display_result(result)
        end

        result
      end

      private

      # Validate conversion parameters
      #
      # @param collection_path [String] Collection path
      # @param target_type [Symbol] Target type
      # @param options [Hash] Options
      # @raise [ArgumentError] if invalid
      def validate_parameters!(collection_path, target_type, options)
        unless File.exist?(collection_path)
          raise ArgumentError, "Collection file not found: #{collection_path}"
        end

        unless %i[ttc otc dfont].include?(target_type)
          raise ArgumentError, "Invalid target type: #{target_type}. Must be :ttc, :otc, or :dfont"
        end

        unless options[:output]
          raise ArgumentError, "Output path is required (:output option)"
        end
      end

      # Unpack fonts from source collection
      #
      # @param collection_path [String] Collection path
      # @return [Array<(Array<Font>, Symbol)>] Array of [fonts, source_type]
      # @raise [Error] if unpacking fails
      def unpack_fonts(collection_path)
        # Detect collection type
        source_type = detect_collection_type(collection_path)

        fonts = case source_type
                when :ttc, :otc
                  unpack_ttc_otc(collection_path)
                when :dfont
                  unpack_dfont(collection_path)
                else
                  raise Error, "Unknown collection type: #{source_type}"
                end

        [fonts, source_type]
      end

      # Detect collection type from file
      #
      # @param path [String] Collection path
      # @return [Symbol] Collection type (:ttc, :otc, or :dfont)
      def detect_collection_type(path)
        File.open(path, "rb") do |io|
          signature = io.read(4)
          io.rewind

          if signature == "ttcf"
            # TTC or OTC - check extension
            ext = File.extname(path).downcase
            ext == ".otc" ? :otc : :ttc
          elsif Parsers::DfontParser.dfont?(io)
            :dfont
          else
            raise Error, "Not a valid collection file: #{path}"
          end
        end
      end

      # Unpack fonts from TTC/OTC
      #
      # @param path [String] TTC/OTC path
      # @return [Array<Font>] Unpacked fonts
      def unpack_ttc_otc(path)
        collection = FontLoader.load_collection(path)

        File.open(path, "rb") do |io|
          collection.extract_fonts(io)
        end
      end

      # Unpack fonts from dfont
      #
      # @param path [String] dfont path
      # @return [Array<Font>] Unpacked fonts
      def unpack_dfont(path)
        fonts = []

        File.open(path, "rb") do |io|
          count = Parsers::DfontParser.sfnt_count(io)

          count.times do |index|
            sfnt_data = Parsers::DfontParser.extract_sfnt(io, index: index)

            # Load font from SFNT binary
            font = FontLoader.load_from_binary(sfnt_data)
            fonts << font
          end
        end

        fonts
      end

      # Convert fonts if outline format change needed
      #
      # @param fonts [Array<Font>] Source fonts
      # @param source_type [Symbol] Source collection type
      # @param target_type [Symbol] Target collection type
      # @param options [Hash] Conversion options
      # @return [Array<(Array<Font>, Array<Hash>)>] [converted_fonts, conversions]
      def convert_fonts(fonts, source_type, target_type, options)
        converted_fonts = []
        conversions = []

        # Determine if outline conversion is needed
        target_format = options.fetch(:target_format, 'preserve').to_s

        fonts.each_with_index do |font, index|
          source_format = detect_font_format(font)
          needs_conversion = outline_conversion_needed?(source_format, target_format)

          if needs_conversion
            # Convert outline format
            desired_format = target_format == 'preserve' ? source_format : target_format.to_sym
            converter = FormatConverter.new

            begin
              tables = converter.convert(font, desired_format, options)
              converted_font = build_font_from_tables(tables, desired_format)
              converted_fonts << converted_font

              conversions << {
                index: index,
                source_format: source_format,
                target_format: desired_format,
                status: :converted,
              }
            rescue Error => e
              # If conversion fails, keep original for dfont (supports mixed)
              if target_type == :dfont
                converted_fonts << font
                conversions << {
                  index: index,
                  source_format: source_format,
                  target_format: source_format,
                  status: :preserved,
                  note: "Conversion failed, kept original: #{e.message}",
                }
              else
                raise Error, "Font #{index} conversion failed: #{e.message}"
              end
            end
          else
            # No conversion needed, use original
            converted_fonts << font
            conversions << {
              index: index,
              source_format: source_format,
              target_format: source_format,
              status: :preserved,
            }
          end
        end

        [converted_fonts, conversions]
      end

      # Check if outline conversion is needed
      #
      # @param source_format [Symbol] Source font format (:ttf or :otf)
      # @param target_format [String] Target format ('preserve', 'ttf', or 'otf')
      # @return [Boolean] true if conversion needed
      def outline_conversion_needed?(source_format, target_format)
        # 'preserve' means keep original format
        return false if target_format == 'preserve'

        # Convert if target format differs from source
        target_format.to_sym != source_format
      end

      # Determine target outline format for a font
      #
      # @param target_type [Symbol] Target collection type
      # @param font [Font] Font object
      # @return [Symbol] Target outline format (:ttf or :otf)
      def target_outline_format(target_type, font)
        case target_type
        when :ttc
          :ttf  # TTC requires TrueType
        when :otc
          :otf  # OTC requires OpenType/CFF
        when :dfont
          # dfont preserves original format
          detect_font_format(font)
        else
          detect_font_format(font)
        end
      end

      # Detect font outline format
      #
      # @param font [Font] Font object
      # @return [Symbol] Format (:ttf or :otf)
      def detect_font_format(font)
        if font.has_table?("CFF ") || font.has_table?("CFF2")
          :otf
        elsif font.has_table?("glyf")
          :ttf
        else
          raise Error, "Cannot detect font format"
        end
      end

      # Build font object from tables
      #
      # @param tables [Hash] Table data
      # @param format [Symbol] Font format
      # @return [Font] Font object
      def build_font_from_tables(tables, format)
        # Create temporary font from tables
        require_relative "../font_writer"
        require "stringio"

        sfnt_version = format == :otf ? 0x4F54544F : 0x00010000
        binary = FontWriter.write_font(tables, sfnt_version: sfnt_version)

        # Load font from binary using StringIO
        sfnt_io = StringIO.new(binary)
        signature = sfnt_io.read(4)
        sfnt_io.rewind

        # Create font based on signature
        case signature
        when [Constants::SFNT_VERSION_TRUETYPE].pack("N"), "true"
          font = TrueTypeFont.read(sfnt_io)
          font.initialize_storage
          font.loading_mode = LoadingModes::FULL
          font.lazy_load_enabled = false
          font.read_table_data(sfnt_io)
          font
        when "OTTO"
          font = OpenTypeFont.read(sfnt_io)
          font.initialize_storage
          font.loading_mode = LoadingModes::FULL
          font.lazy_load_enabled = false
          font.read_table_data(sfnt_io)
          font
        else
          raise Error, "Invalid SFNT signature: #{signature.inspect}"
        end
      end

      # Repack fonts into target collection
      #
      # @param fonts [Array<Font>] Fonts to pack
      # @param target_type [Symbol] Target type
      # @param output_path [String] Output path
      # @param options [Hash] Packing options
      # @return [void]
      def repack_fonts(fonts, target_type, output_path, options)
        case target_type
        when :ttc, :otc
          repack_ttc_otc(fonts, target_type, output_path, options)
        when :dfont
          repack_dfont(fonts, output_path, options)
        else
          raise Error, "Unknown target type: #{target_type}"
        end
      end

      # Repack fonts into TTC/OTC
      #
      # @param fonts [Array<Font>] Fonts
      # @param target_type [Symbol] :ttc or :otc
      # @param output_path [String] Output path
      # @param options [Hash] Options
      # @return [void]
      def repack_ttc_otc(fonts, target_type, output_path, options)
        optimize = options.fetch(:optimize, true)

        builder = Collection::Builder.new(
          fonts,
          format: target_type,
          optimize: optimize,
        )

        builder.build_to_file(output_path)
      end

      # Repack fonts into dfont
      #
      # @param fonts [Array<Font>] Fonts
      # @param output_path [String] Output path
      # @param options [Hash] Options
      # @return [void]
      def repack_dfont(fonts, output_path, _options)
        builder = Collection::DfontBuilder.new(fonts)
        builder.build_to_file(output_path)
      end

      # Build conversion result
      #
      # @param input [String] Input path
      # @param output [String] Output path
      # @param source_type [Symbol] Source type
      # @param target_type [Symbol] Target type
      # @param num_fonts [Integer] Number of fonts
      # @param conversions [Array<Hash>] Conversion details
      # @return [Hash] Result
      def build_result(input, output, source_type, target_type, num_fonts, conversions)
        {
          input: input,
          output: output,
          source_type: source_type,
          target_type: target_type,
          num_fonts: num_fonts,
          conversions: conversions,
        }
      end

      # Display conversion result
      #
      # @param result [Hash] Result
      # @return [void]
      def display_result(result)
        puts "\n=== Collection Conversion Complete ==="
        puts "Input: #{result[:input]}"
        puts "Output: #{result[:output]}"
        puts "Source format: #{result[:source_type].to_s.upcase}"
        puts "Target format: #{result[:target_type].to_s.upcase}"
        puts "Fonts: #{result[:num_fonts]}"

        if result[:conversions].any?
          converted_count = result[:conversions].count { |c| c[:status] == :converted }
          if converted_count.positive?
            puts "Outline conversions: #{converted_count}"
          end
        end

        puts ""
      end
    end
  end
end
