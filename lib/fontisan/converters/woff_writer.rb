# frozen_string_literal: true

require "zlib"
require_relative "conversion_strategy"
require_relative "../utilities/checksum_calculator"

module Fontisan
  module Converters
    # WOFF font writer for creating WOFF files from TTF/OTF fonts
    #
    # [`WoffWriter`](lib/fontisan/converters/woff_writer.rb) handles conversion
    # from TrueType/OpenType fonts to WOFF format using zlib compression.
    # This implements the WOFF 1.0 specification for web font optimization.
    #
    # **WOFF Format Features:**
    # - Individual table compression with zlib
    # - Optional metadata block (compressed XML)
    # - Optional private data block
    # - Proper header and table directory structure
    # - Cross-platform compatibility
    #
    # **Compression Strategy:**
    # - Each table is compressed individually for optimal ratios
    # - Tables smaller than compression threshold remain uncompressed
    # - Metadata and private data are compressed when present
    # - All data is properly aligned and padded
    #
    # @example Converting TTF to WOFF
    #   writer = Fontisan::Converters::WoffWriter.new
    #   woff_data = writer.write_font(ttf_font, metadata: xml_metadata)
    #   File.write("output.woff", woff_data)
    #
    # @example With compression options
    #   writer = Fontisan::Converters::WoffWriter.new(
    #     compression_level: 9,  # Maximum compression
    #     compression_threshold: 100  # Bytes - tables smaller than this stay uncompressed
    #   )
    #   woff_data = writer.write_font(ttf_font)
    class WoffWriter
      include ConversionStrategy

      # WOFF signature constant
      WOFF_SIGNATURE = 0x774F4646 # 'wOFF'

      # WOFF version 1.0
      WOFF_VERSION_MAJOR = 1
      WOFF_VERSION_MINOR = 0

      # Default compression settings
      DEFAULT_COMPRESSION_LEVEL = 6
      DEFAULT_COMPRESSION_THRESHOLD = 100 # bytes - don't compress smaller tables

      # Compression level (0-9, where 9 is maximum)
      attr_accessor :compression_level

      # Minimum table size to compress (bytes)
      attr_accessor :compression_threshold

      # Optional metadata XML
      attr_accessor :metadata_xml

      # Optional private data
      attr_accessor :private_data

      # Initialize writer with compression options
      #
      # @param options [Hash] Writer options
      # @option options [Integer] :compression_level zlib compression level (0-9)
      # @option options [Integer] :compression_threshold minimum table size to compress
      # @option options [String] :metadata_xml optional metadata XML
      # @option options [String] :private_data optional private data
      def initialize(options = {})
        @compression_level = options[:compression_level] || DEFAULT_COMPRESSION_LEVEL
        @compression_threshold = options[:compression_threshold] || DEFAULT_COMPRESSION_THRESHOLD
        @metadata_xml = options[:metadata_xml]
        @private_data = options[:private_data]

        validate_compression_level!
      end

      # Convert font to WOFF format
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Additional options for this conversion
      # @return [String] WOFF file data as binary string
      # @raise [ArgumentError] if font is invalid
      def convert(font, options = {})
        validate_font(font)

        # Override instance options with per-conversion options
        metadata = options[:metadata_xml] || @metadata_xml
        private_data = options[:private_data] || @private_data

        write_font(font, metadata: metadata, private_data: private_data)
      end

      # Get supported conversions
      #
      # @return [Array<Array<Symbol>>] Supported conversion pairs
      def supported_conversions
        [
          %i[ttf woff],
          %i[otf woff],
        ]
      end

      # Write font data to WOFF format
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param metadata [String, nil] Optional metadata XML
      # @param private_data [String, nil] Optional private data
      # @return [String] WOFF file data
      def write_font(font, metadata: nil, private_data: nil)
        # Collect all table data from font
        tables_data = collect_tables_data(font)

        # Compress tables
        compressed_tables = compress_tables(tables_data)

        # Build WOFF file
        build_woff_file(compressed_tables, font, metadata, private_data)
      end

      private

      # Validate compression level
      #
      # @raise [ArgumentError] if compression level is invalid
      def validate_compression_level!
        unless @compression_level.between?(0, 9)
          raise ArgumentError,
                "Compression level must be between 0 and 9, got #{@compression_level}"
        end
      end

      # Validate font for conversion
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @raise [ArgumentError] if font is invalid
      def validate_font(font)
        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:tables) && font.respond_to?(:table_data)
          raise ArgumentError, "Font must respond to :tables and :table_data"
        end
      end

      # Collect all table data from font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @return [Hash<String, String>] Map of table tags to binary data
      def collect_tables_data(font)
        tables_data = {}

        font.table_names.each do |tag|
          data = font.table_data[tag]
          tables_data[tag] = data if data
        end

        tables_data
      end

      # Compress tables with zlib
      #
      # @param tables_data [Hash<String, String>] Original table data
      # @return [Hash<String, Hash>] Compressed table info with original/compressed sizes
      def compress_tables(tables_data)
        compressed_tables = {}

        tables_data.each do |tag, data|
          original_size = data.bytesize

          # Only compress if table is large enough and compression is beneficial
          if original_size >= @compression_threshold
            compressed_data = Zlib::Deflate.deflate(data, @compression_level)
            compressed_size = compressed_data.bytesize

            # Only use compression if it actually reduces size
            compressed_tables[tag] = if compressed_size < original_size
                                       {
                                         original_data: data,
                                         compressed_data: compressed_data,
                                         original_length: original_size,
                                         compressed_length: compressed_size,
                                         is_compressed: true,
                                       }
                                     else
                                       # Compression didn't help, store uncompressed
                                       {
                                         original_data: data,
                                         compressed_data: data,
                                         original_length: original_size,
                                         compressed_length: original_size,
                                         is_compressed: false,
                                       }
                                     end
          else
            # Table too small to compress
            compressed_tables[tag] = {
              original_data: data,
              compressed_data: data,
              original_length: original_size,
              compressed_length: original_size,
              is_compressed: false,
            }
          end
        end

        compressed_tables
      end

      # Build complete WOFF file
      #
      # @param compressed_tables [Hash] Compressed table information
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param metadata [String, nil] Optional metadata XML
      # @param private_data [String, nil] Optional private data
      # @return [String] Complete WOFF file data
      def build_woff_file(compressed_tables, font, metadata, private_data)
        io = StringIO.new
        io.set_encoding(Encoding::BINARY)

        # Compress metadata if provided
        compressed_metadata = compress_metadata(metadata)

        # Calculate offsets and sizes
        header_size = 44 # WOFF header size
        num_tables = compressed_tables.length
        table_dir_size = num_tables * 20 # Each table directory entry is 20 bytes

        # Calculate data offset (after header + table directory)
        data_offset = header_size + table_dir_size

        # Calculate metadata and private data offsets
        metadata_offset = data_offset
        metadata_size = compressed_metadata ? compressed_metadata[:compressed_length] : 0

        # Calculate total compressed data size
        total_compressed_size = compressed_tables.values.sum do |table|
          table[:compressed_length]
        end

        # Calculate private data offset (after table data + metadata)
        private_offset = data_offset + total_compressed_size + metadata_size
        private_size = private_data ? private_data.bytesize : 0

        # Calculate total WOFF file size
        total_size = private_offset + private_size

        # Calculate total SFNT size (uncompressed)
        total_sfnt_size = compressed_tables.values.sum do |table|
          table[:original_length]
        end +
          header_size + table_dir_size

        # Write WOFF header
        write_woff_header(io, font, total_size, total_sfnt_size, num_tables,
                          compressed_metadata, metadata_offset, metadata_size,
                          private_offset, private_size)

        # Write table directory
        write_table_directory(io, compressed_tables, data_offset)

        # Write compressed table data
        write_compressed_table_data(io, compressed_tables)

        # Write compressed metadata if present
        write_metadata(io, compressed_metadata) if compressed_metadata

        # Write private data if present
        write_private_data(io, private_data) if private_data

        io.string
      end

      # Compress metadata with zlib
      #
      # @param metadata [String, nil] Metadata XML
      # @return [Hash, nil] Compressed metadata info or nil
      def compress_metadata(metadata)
        return nil unless metadata

        original_length = metadata.bytesize
        compressed_data = Zlib::Deflate.deflate(metadata, @compression_level)
        compressed_length = compressed_data.bytesize

        {
          original_data: metadata,
          compressed_data: compressed_data,
          original_length: original_length,
          compressed_length: compressed_length,
        }
      end

      # Write WOFF header
      #
      # @param io [StringIO] Output stream
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param total_size [Integer] Total WOFF file size
      # @param total_sfnt_size [Integer] Uncompressed SFNT size
      # @param num_tables [Integer] Number of tables
      # @param compressed_metadata [Hash, nil] Compressed metadata info
      # @param metadata_offset [Integer] Metadata offset
      # @param metadata_size [Integer] Compressed metadata size
      # @param private_offset [Integer] Private data offset
      # @param private_size [Integer] Private data size
      # @return [void]
      def write_woff_header(io, font, total_size, total_sfnt_size, num_tables,
                           compressed_metadata, metadata_offset, metadata_size,
                           private_offset, private_size)
        # Determine flavor from font
        flavor = if font.respond_to?(:cff?) && font.cff?
                   Constants::SFNT_VERSION_OTTO
                 else
                   # Default to TrueType for TrueType fonts and unknown types
                   Constants::SFNT_VERSION_TRUETYPE
                 end

        # Write WOFF header (44 bytes total)
        io.write([WOFF_SIGNATURE].pack("N"))           # signature (4 bytes)
        io.write([flavor].pack("N"))                   # flavor (4 bytes)
        io.write([total_size].pack("N"))               # length (4 bytes)
        io.write([num_tables].pack("n"))               # numTables (2 bytes)
        io.write([0].pack("n"))                        # reserved (2 bytes)
        io.write([total_sfnt_size].pack("N"))          # totalSfntSize (4 bytes)
        io.write([WOFF_VERSION_MAJOR].pack("n"))       # majorVersion (2 bytes)
        io.write([WOFF_VERSION_MINOR].pack("n"))       # minorVersion (2 bytes)
        io.write([metadata_offset].pack("N"))          # metaOffset (4 bytes)
        io.write([metadata_size].pack("N"))            # metaLength (4 bytes)
        io.write([compressed_metadata ? compressed_metadata[:original_length] : 0].pack("N")) # metaOrigLength (4 bytes)
        io.write([private_offset].pack("N"))           # privOffset (4 bytes)
        io.write([private_size].pack("N"))             # privLength (4 bytes)
      end

      # Write table directory
      #
      # @param io [StringIO] Output stream
      # @param compressed_tables [Hash] Compressed table information
      # @param data_offset [Integer] Starting offset for table data
      # @return [void]
      def write_table_directory(io, compressed_tables, data_offset)
        current_offset = data_offset

        # Sort tables by tag for consistent output
        sorted_tables = compressed_tables.sort_by { |tag, _| tag }

        sorted_tables.each do |tag, table_info|
          # Calculate checksum of original table data
          checksum = Utilities::ChecksumCalculator.calculate_table_checksum(table_info[:original_data])

          # Write table directory entry (20 bytes)
          io.write(tag)                                    # tag (4 bytes)
          io.write([current_offset].pack("N"))             # offset (4 bytes)
          io.write([table_info[:compressed_length]].pack("N")) # compLength (4 bytes)
          io.write([table_info[:original_length]].pack("N"))   # origLength (4 bytes)
          io.write([checksum].pack("N")) # origChecksum (4 bytes)

          # Update offset for next table
          current_offset += table_info[:compressed_length]
        end
      end

      # Write compressed table data
      #
      # @param io [StringIO] Output stream
      # @param compressed_tables [Hash] Compressed table information
      # @return [void]
      def write_compressed_table_data(io, compressed_tables)
        # Sort tables by tag for consistent output (same order as directory)
        sorted_tables = compressed_tables.sort_by { |tag, _| tag }

        sorted_tables.each do |_tag, table_info|
          io.write(table_info[:compressed_data])
        end
      end

      # Write metadata to output
      #
      # @param io [StringIO] Output stream
      # @param compressed_metadata [Hash] Compressed metadata info
      # @return [void]
      def write_metadata(io, compressed_metadata)
        io.write(compressed_metadata[:compressed_data])
      end

      # Write private data to output
      #
      # @param io [StringIO] Output stream
      # @param private_data [String] Private data
      # @return [void]
      def write_private_data(io, private_data)
        io.write(private_data)
      end
    end
  end
end
