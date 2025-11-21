# frozen_string_literal: true

require_relative "conversion_strategy"
require_relative "../woff2/header"
require_relative "../woff2/directory"
require_relative "../woff2/table_transformer"
require_relative "../utilities/brotli_wrapper"
require_relative "../utilities/checksum_calculator"
require "yaml"

module Fontisan
  module Converters
    # WOFF2 encoder conversion strategy
    #
    # [`Woff2Encoder`](lib/fontisan/converters/woff2_encoder.rb) implements
    # the ConversionStrategy interface to convert TTF or OTF fonts to WOFF2
    # format with Brotli compression.
    #
    # WOFF2 encoding process:
    # 1. Load configuration settings
    # 2. Determine font flavor (TTF or CFF)
    # 3. Collect and order tables
    # 4. Transform tables (placeholder for glyf/loca/hmtx optimization)
    # 5. Compress all tables with single Brotli stream
    # 6. Build WOFF2 header and table directory
    # 7. Assemble complete WOFF2 binary
    #
    # For Phase 2 Milestone 2.1:
    # - Basic WOFF2 structure generation
    # - Brotli compression of table data
    # - Valid WOFF2 files for web font delivery
    # - Table transformations are architectural placeholders
    #
    # @example Convert TTF to WOFF2
    #   encoder = Woff2Encoder.new
    #   woff2_binary = encoder.convert(font)
    #   File.binwrite('font.woff2', woff2_binary)
    class Woff2Encoder
      include ConversionStrategy

      # @return [Hash] Configuration settings
      attr_reader :config

      # Initialize encoder with configuration
      #
      # @param config_path [String, nil] Path to config file
      def initialize(config_path: nil)
        @config = load_configuration(config_path)
      end

      # Convert font to WOFF2 format
      #
      # Returns a hash with :woff2_binary key containing complete WOFF2 file.
      # This is different from other converters that return table data.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Conversion options
      # @option options [Integer] :quality Brotli quality (0-11)
      # @option options [Boolean] :transform_tables Apply table transformations
      # @return [Hash] Hash with :woff2_binary key containing WOFF2 binary
      # @raise [Error] If encoding fails
      def convert(font, options = {})
        validate(font, :woff2)

        # Get Brotli quality from options or config
        quality = options[:quality] || config["brotli"]["quality"]

        # Detect font flavor
        flavor = detect_flavor(font)

        # Collect all tables
        table_data = collect_tables(font, options)

        # Transform tables (if enabled)
        transformer = Woff2::TableTransformer.new(font)
        transform_enabled = options.fetch(:transform_tables, false)

        # Build table directory entries
        entries = build_table_entries(table_data, transformer,
                                      transform_enabled)

        # Compress all table data into single stream
        compressed_data = compress_tables(entries, table_data, quality)

        # Calculate sizes
        total_sfnt_size = calculate_sfnt_size(table_data)
        total_compressed_size = compressed_data.bytesize

        # Build WOFF2 header
        header = build_header(
          flavor: flavor,
          num_tables: entries.size,
          total_sfnt_size: total_sfnt_size,
          total_compressed_size: total_compressed_size,
        )

        # Assemble WOFF2 binary
        woff2_binary = assemble_woff2(header, entries, compressed_data)

        # Return in special format for ConvertCommand to handle
        { woff2_binary: woff2_binary }
      end

      # Get list of supported conversions
      #
      # @return [Array<Array<Symbol>>] Supported conversion pairs
      def supported_conversions
        [
          %i[ttf woff2],
          %i[otf woff2],
        ]
      end

      # Validate that conversion is possible
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param target_format [Symbol] Target format
      # @return [Boolean] True if valid
      # @raise [Error] If conversion is not possible
      def validate(font, target_format)
        unless target_format == :woff2
          raise Fontisan::Error,
                "Woff2Encoder only supports conversion to woff2, " \
                "got: #{target_format}"
        end

        # Verify font has required tables
        required_tables = %w[head hhea maxp]
        required_tables.each do |tag|
          unless font.table(tag)
            raise Fontisan::Error,
                  "Font is missing required table: #{tag}"
          end
        end

        # Verify font has either glyf or CFF table
        unless font.has_table?("glyf") || font.has_table?("CFF ") || font.has_table?("CFF2")
          raise Fontisan::Error,
                "Font must have either glyf or CFF/CFF2 table"
        end

        true
      end

      private

      # Load configuration from YAML file
      #
      # @param path [String, nil] Path to config file
      # @return [Hash] Configuration settings
      def load_configuration(path)
        config_path = path || default_config_path

        if File.exist?(config_path)
          YAML.load_file(config_path)
        else
          default_configuration
        end
      rescue StandardError => e
        warn "Failed to load WOFF2 configuration: #{e.message}"
        default_configuration
      end

      # Get default configuration path
      #
      # @return [String] Path to config file
      def default_config_path
        File.join(
          __dir__,
          "..",
          "config",
          "woff2_settings.yml",
        )
      end

      # Get default configuration
      #
      # @return [Hash] Default settings
      def default_configuration
        {
          "brotli" => {
            "quality" => 11,
            "mode" => "font",
          },
          "transformations" => {
            "enabled" => false, # Disabled for Milestone 2.1
            "glyf_loca" => false,
            "hmtx" => false,
          },
          "metadata" => {
            "include" => false,
          },
        }
      end

      # Detect font flavor (TTF or CFF)
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to detect
      # @return [Integer] Flavor value
      def detect_flavor(font)
        if font.has_table?("CFF ") || font.has_table?("CFF2")
          0x4F54544F # 'OTTO' for CFF
        elsif font.has_table?("glyf")
          0x00010000 # TrueType
        else
          raise Fontisan::Error,
                "Cannot determine font flavor: missing glyf and CFF tables"
        end
      end

      # Collect all tables from font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Conversion options
      # @return [Hash<String, String>] Map of tag to table data
      def collect_tables(font, _options = {})
        tables = {}

        # Get all table names from font
        table_names = if font.respond_to?(:table_names)
                        font.table_names
                      else
                        # Fallback: try common tables
                        %w[head hhea maxp OS/2 name cmap post hmtx glyf loca
                           CFF]
                      end

        table_names.each do |tag|
          data = get_table_data(font, tag)
          tables[tag] = data if data && !data.empty?
        end

        tables
      end

      # Get table data from font
      #
      # @param font [Object] Font object
      # @param tag [String] Table tag
      # @return [String, nil] Table data
      def get_table_data(font, tag)
        if font.respond_to?(:table_data)
          font.table_data[tag]
        elsif font.respond_to?(:table)
          table = font.table(tag)
          table&.to_binary_s if table.respond_to?(:to_binary_s)
        end
      end

      # Build table directory entries
      #
      # @param table_data [Hash<String, String>] Table data map
      # @param transformer [Woff2::TableTransformer] Table transformer
      # @param transform_enabled [Boolean] Enable transformations
      # @return [Array<Woff2::Directory::Entry>] Table entries
      def build_table_entries(table_data, transformer, transform_enabled)
        entries = []

        # Sort tables by tag for consistent output
        sorted_tags = table_data.keys.sort

        sorted_tags.each do |tag|
          entry = Woff2::Directory::Entry.new
          entry.tag = tag

          # Get original table data
          data = table_data[tag]
          entry.orig_length = data.bytesize

          # Apply transformation if enabled and supported
          if transform_enabled && transformer.transformable?(tag)
            transformed = transformer.transform_table(tag)
            if transformed && transformed.bytesize < data.bytesize
              entry.transform_length = transformed.bytesize
            end
          end

          # Calculate flags
          entry.flags = entry.calculate_flags

          entries << entry
        end

        entries
      end

      # Compress all tables into single Brotli stream
      #
      # @param entries [Array<Woff2::Directory::Entry>] Table entries
      # @param table_data [Hash<String, String>] Original table data
      # @param quality [Integer] Brotli quality
      # @return [String] Compressed data
      def compress_tables(entries, table_data, quality)
        # Concatenate all table data in entry order
        combined_data = String.new(encoding: Encoding::BINARY)

        entries.each do |entry|
          # Get table data
          data = table_data[entry.tag]
          next unless data

          # For this milestone, we don't have transformed data yet
          # Use original table data
          combined_data << data
        end

        # Compress with Brotli
        Utilities::BrotliWrapper.compress(
          combined_data,
          quality: quality,
        )
      end

      # Calculate total SFNT size (uncompressed)
      #
      # @param table_data [Hash<String, String>] Table data map
      # @return [Integer] Total size in bytes
      def calculate_sfnt_size(table_data)
        # Header size (offset table)
        size = 12

        # Table directory size
        size += table_data.size * 16

        # Table data size (with padding)
        table_data.each_value do |data|
          size += data.bytesize
          # Add padding to 4-byte boundary
          padding = (4 - (data.bytesize % 4)) % 4
          size += padding
        end

        size
      end

      # Build WOFF2 header
      #
      # @param flavor [Integer] Font flavor
      # @param num_tables [Integer] Number of tables
      # @param total_sfnt_size [Integer] Uncompressed size
      # @param total_compressed_size [Integer] Compressed size
      # @return [Woff2::Woff2Header] WOFF2 header
      def build_header(flavor:, num_tables:, total_sfnt_size:,
total_compressed_size:)
        header = Woff2::Woff2Header.new
        header.signature = Woff2::Woff2Header::SIGNATURE
        header.flavor = flavor
        header.file_length = 0 # Will be updated later
        header.num_tables = num_tables
        header.reserved = 0
        header.total_sfnt_size = total_sfnt_size
        header.total_compressed_size = total_compressed_size
        header.major_version = 1
        header.minor_version = 0
        header.meta_offset = 0
        header.meta_length = 0
        header.meta_orig_length = 0
        header.priv_offset = 0
        header.priv_length = 0

        header
      end

      # Assemble complete WOFF2 binary
      #
      # @param header [Woff2::Woff2Header] WOFF2 header
      # @param entries [Array<Woff2::Directory::Entry>] Table entries
      # @param compressed_data [String] Compressed table data
      # @return [String] Complete WOFF2 binary
      def assemble_woff2(header, entries, compressed_data)
        woff2_data = String.new(encoding: Encoding::BINARY)

        # Write header (placeholder, we'll update file_length later)
        header_binary = header.to_binary_s
        woff2_data << header_binary

        # Write table directory
        entries.each do |entry|
          woff2_data << [entry.flags].pack("C")

          # Write custom tag if needed
          unless entry.known_tag?
            woff2_data << entry.tag.ljust(4, "\x00")
          end

          # Write orig_length (UIntBase128)
          woff2_data << Woff2::Directory.encode_uint_base128(entry.orig_length)

          # Write transform_length if present
          if entry.transformed?
            woff2_data << Woff2::Directory.encode_uint_base128(entry.transform_length)
          end
        end

        # Write compressed data
        woff2_data << compressed_data

        # Update header file_length field
        update_woff2_length!(woff2_data)

        woff2_data
      end

      # Update WOFF2 file length in header
      #
      # @param woff2_data [String] WOFF2 binary (modified in place)
      # @return [void]
      def update_woff2_length!(woff2_data)
        total_length = woff2_data.bytesize

        # file_length field is at offset 8 in header (uint32)
        woff2_data[8, 4] = [total_length].pack("N")
      end
    end
  end
end
