# frozen_string_literal: true

require "zlib"
require_relative "conversion_strategy"
require_relative "../utilities/checksum_calculator"

module Fontisan
  module Converters
    # WOFF font writer for creating WOFF files from TTF/OTF fonts
    #
    # [`WoffWriter`](lib/fontisan/converters/woff_writer.rb) converts
    # TrueType/OpenType fonts to WOFF 1.0 format. The WOFF spec mandates zlib
    # compression; this writer exposes the spec-legal knobs only:
    #
    # - `zlib_level` (0–9) — zlib compression level
    # - `uncompressed` (bool) — store tables uncompressed (legal per WOFF 1.0
    #   §5.1; `compLength == origLength`)
    # - `compression_threshold` (bytes) — skip compression for tables smaller
    #   than N bytes (rarely needed; keeps tiny tables uncompressed)
    # - `metadata_xml` (string) — optional metadata block
    # - `private_data` (string) — optional private data block
    #
    # Cross-format options (e.g., `brotli_quality`) are rejected by
    # ConversionStrategy#validate_options! — see {ConversionStrategy}.
    #
    # @example Convert TTF to WOFF with max zlib
    #   writer = WoffWriter.new
    #   woff = writer.convert(ttf_font, zlib_level: 9)
    #   File.binwrite("out.woff", woff)
    #
    # @example Uncompressed WOFF (legal per spec; useful for tooling pipelines)
    #   writer = WoffWriter.new
    #   woff = writer.convert(ttf_font, uncompressed: true)
    class WoffWriter
      include ConversionStrategy

      # WOFF signature constant
      WOFF_SIGNATURE = 0x774F4646 # 'wOFF'

      # WOFF version 1.0
      WOFF_VERSION_MAJOR = 1
      WOFF_VERSION_MINOR = 0

      option :zlib_level, type: :integer, range: 0..9, default: 6,
                          cli: "--zlib-level=N",
                          desc: "zlib compression level (0=fastest, 9=smallest)"
      option :uncompressed, type: :boolean, default: false,
                            cli: "--uncompressed",
                            desc: "store tables uncompressed (legal per WOFF 1.0 §5.1)"
      option :compression_threshold, type: :integer,
                                     range: 0..(2**31 - 1),
                                     default: 100,
                                     cli: "--compression-threshold=N",
                                     desc: "skip compression for tables smaller than N bytes"
      option :metadata_xml, type: :string, default: nil,
                            cli: "--metadata-xml=XML",
                            desc: "optional metadata XML block"
      option :private_data, type: :string, default: nil,
                            cli: "--private-data=DATA",
                            desc: "optional private data block"

      # Initialize writer. The writer is stateless per call; all knobs come
      # through the per-convert options hash.
      def initialize; end

      # Convert font to WOFF format.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash{Symbol => Object}] Per-call options; see declared
      #   options above. Unknown keys (framework metadata like
      #   `target_format`) are tolerated silently. Cross-format misuse
      #   (`brotli_quality` on a WOFF target) is caught upstream by
      #   `FormatConverter.validate_options_for_target!`.
      # @return [String] WOFF file data as binary string
      # @raise [ArgumentError] if any declared option fails validation
      # @raise [ArgumentError] if font does not respond to required methods
      def convert(font, options = {})
        self.class.validate_options!(strategy_options(options))
        validate(font, :woff)

        opts = self.class.default_options.merge(strategy_options(options))
        write_font(
          font,
          zlib_level: opts[:zlib_level],
          uncompressed: opts[:uncompressed],
          compression_threshold: opts[:compression_threshold],
          metadata: opts[:metadata_xml],
          private_data: opts[:private_data],
        )[:woff_binary]
      end

      # Get supported conversions.
      #
      # @return [Array<Array<Symbol>>] Pairs this strategy handles
      def supported_conversions
        [
          %i[ttf woff],
          %i[otf woff],
        ]
      end

      # Validate that the given font can be converted to WOFF.
      #
      # @param font [Object] Font to validate
      # @param target_format [Symbol] Must be :woff
      # @return [Boolean]
      # @raise [ArgumentError] if font is nil or missing required methods
      # @raise [Fontisan::Error] if target_format is not :woff
      def validate(font, target_format)
        unless target_format == :woff
          raise Fontisan::Error,
                "WoffWriter only supports conversion to woff, got: #{target_format}"
        end

        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:tables) && font.respond_to?(:table_data)
          raise ArgumentError, "Font must respond to :tables and :table_data"
        end
      end

      # Write font to WOFF binary.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param zlib_level [Integer] 0–9
      # @param uncompressed [Boolean] skip zlib; store as-is
      # @param compression_threshold [Integer] skip compression below N bytes
      # @param metadata [String, nil] optional metadata XML
      # @param private_data [String, nil] optional private data
      # @return [Hash{Symbol => String}] `{ woff_binary: <bytes> }`
      def write_font(font, zlib_level:, uncompressed:, compression_threshold:,
                     metadata: nil, private_data: nil)
        tables_data = collect_tables_data(font)
        compressed_tables = compress_tables(
          tables_data,
          zlib_level: uncompressed ? 0 : zlib_level,
          skip_compression: uncompressed,
          compression_threshold: compression_threshold,
        )
        compressed_metadata = compress_metadata(metadata, zlib_level: zlib_level,
                                                          skip_compression: uncompressed)
        binary = build_woff_file(compressed_tables, font, compressed_metadata,
                                 private_data)
        { woff_binary: binary }
      end

      private

      # Slice options to those declared by this strategy. Tolerates extra
      # keys (e.g., `target_format`) silently so FormatConverter can pass the
      # full options hash through.
      def strategy_options(options)
        names = self.class.supported_options.to_set(&:name)
        options.select { |k, _| names.include?(k.to_sym) }
      end

      # Collect all table data from font.
      #
      # @param font [TrueTypeFont, OpenTypeFont]
      # @return [Hash<String, String>]
      def collect_tables_data(font)
        font.table_names.to_h do |tag|
          [tag, font.table_data[tag]]
        end.compact
      end

      # Compress tables with zlib (or skip compression entirely).
      #
      # @param tables_data [Hash<String, String>]
      # @param zlib_level [Integer] 0–9 (ignored if skip_compression)
      # @param skip_compression [Boolean] store all tables uncompressed
      # @param compression_threshold [Integer] tables below this size are kept
      #   uncompressed even when skip_compression is false
      # @return [Hash<String, Hash>] per-table compressed info
      def compress_tables(tables_data, zlib_level:, skip_compression:,
                          compression_threshold:)
        tables_data.to_h do |tag, data|
          original_size = data.bytesize
          should_compress =
            !skip_compression && original_size >= compression_threshold

          if should_compress
            compressed = Zlib::Deflate.deflate(data, zlib_level)
            use_compressed = compressed.bytesize < original_size
          else
            use_compressed = false
          end

          [
            tag,
            {
              original_data: data,
              compressed_data: use_compressed ? compressed : data,
              original_length: original_size,
              compressed_length: use_compressed ? compressed.bytesize : original_size,
              is_compressed: use_compressed,
            },
          ]
        end
      end

      # Compress metadata with zlib.
      #
      # @param metadata [String, nil]
      # @param zlib_level [Integer]
      # @param skip_compression [Boolean]
      # @return [Hash, nil]
      def compress_metadata(metadata, zlib_level:, skip_compression:)
        return nil unless metadata

        original_length = metadata.bytesize
        if skip_compression
          return {
            original_data: metadata,
            compressed_data: metadata,
            original_length: original_length,
            compressed_length: original_length,
          }
        end

        compressed = Zlib::Deflate.deflate(metadata, zlib_level)
        use_compressed = compressed.bytesize < original_length
        {
          original_data: metadata,
          compressed_data: use_compressed ? compressed : metadata,
          original_length: original_length,
          compressed_length: use_compressed ? compressed.bytesize : original_length,
        }
      end

      # Assemble complete WOFF binary.
      #
      # @param compressed_tables [Hash]
      # @param font [TrueTypeFont, OpenTypeFont]
      # @param compressed_metadata [Hash, nil]
      # @param private_data [String, nil]
      # @return [String]
      def build_woff_file(compressed_tables, font, compressed_metadata,
                          private_data)
        io = StringIO.new
        io.set_encoding(Encoding::BINARY)

        header_size = 44
        num_tables = compressed_tables.length
        table_dir_size = num_tables * 20
        data_offset = header_size + table_dir_size
        metadata_offset = data_offset
        metadata_size = compressed_metadata ? compressed_metadata[:compressed_length] : 0
        total_compressed_size = compressed_tables.values.sum do |t|
          t[:compressed_length]
        end
        private_offset = data_offset + total_compressed_size + metadata_size
        private_size = private_data ? private_data.bytesize : 0
        total_size = private_offset + private_size
        total_sfnt_size = compressed_tables.values.sum do |t|
          t[:original_length]
        end +
          header_size + table_dir_size

        write_woff_header(
          io, font, total_size, total_sfnt_size, num_tables,
          compressed_metadata, metadata_offset, metadata_size,
          private_offset, private_size
        )
        write_table_directory(io, compressed_tables, data_offset)
        write_compressed_table_data(io, compressed_tables)
        write_metadata(io, compressed_metadata) if compressed_metadata
        write_private_data(io, private_data) if private_data

        io.string
      end

      # Write WOFF header (44 bytes).
      def write_woff_header(io, font, total_size, total_sfnt_size, num_tables,
                           compressed_metadata, metadata_offset, metadata_size,
                           private_offset, private_size)
        flavor = if font.respond_to?(:cff?) && font.cff?
                   Constants::SFNT_VERSION_OTTO
                 else
                   Constants::SFNT_VERSION_TRUETYPE
                 end

        io.write([WOFF_SIGNATURE].pack("N"))           # signature
        io.write([flavor].pack("N"))                   # flavor
        io.write([total_size].pack("N"))               # length
        io.write([num_tables].pack("n"))               # numTables
        io.write([0].pack("n"))                        # reserved
        io.write([total_sfnt_size].pack("N"))          # totalSfntSize
        io.write([WOFF_VERSION_MAJOR].pack("n"))       # majorVersion
        io.write([WOFF_VERSION_MINOR].pack("n"))       # minorVersion
        io.write([metadata_offset].pack("N"))          # metaOffset
        io.write([metadata_size].pack("N"))            # metaLength
        io.write([compressed_metadata ? compressed_metadata[:original_length] : 0].pack("N")) # metaOrigLength
        io.write([private_offset].pack("N"))           # privOffset
        io.write([private_size].pack("N"))             # privLength
      end

      # Write table directory entries (20 bytes each).
      def write_table_directory(io, compressed_tables, data_offset)
        current_offset = data_offset
        compressed_tables.sort_by { |tag, _| tag }.each do |tag, info|
          checksum = Utilities::ChecksumCalculator
            .calculate_table_checksum(info[:original_data])
          io.write(tag)                                  # tag
          io.write([current_offset].pack("N"))           # offset
          io.write([info[:compressed_length]].pack("N")) # compLength
          io.write([info[:original_length]].pack("N"))   # origLength
          io.write([checksum].pack("N"))                 # origChecksum
          current_offset += info[:compressed_length]
        end
      end

      # Write compressed table data, sorted by tag (matches directory order).
      def write_compressed_table_data(io, compressed_tables)
        compressed_tables.sort_by { |tag, _| tag }.each do |_, info|
          io.write(info[:compressed_data])
        end
      end

      def write_metadata(io, compressed_metadata)
        io.write(compressed_metadata[:compressed_data])
      end

      def write_private_data(io, private_data)
        io.write(private_data)
      end
    end
  end
end
