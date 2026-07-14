# frozen_string_literal: true

require "zlib"

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
    #   §5.1; `compLength == origLength`). Metadata is still compressed per
    #   spec §7 ("it is never stored in uncompressed form").
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

        unless font.is_a?(SfntSource)
          raise ArgumentError, "Font must be an SfntSource instance"
        end
      end

      # Write font to WOFF binary.
      #
      # Layout per WOFF 1.0 spec:
      #   [header (44)] [table directory (20 × N)] [font tables, 4-byte aligned]
      #   [optional metadata, 4-byte aligned] [optional private data, 4-byte aligned]
      #
      # Each font table is padded with 0-3 null bytes to a 4-byte boundary
      # (spec §5/§6: "Font data tables in the WOFF file have the same
      # requirement: they MUST begin on 4-byte boundaries and be zero-padded
      # to the next 4-byte boundary"). Padding aligns the next block.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param zlib_level [Integer] 0–9
      # @param uncompressed [Boolean] skip zlib; store tables as-is
      # @param compression_threshold [Integer] skip compression below N bytes
      # @param metadata [String, nil] optional metadata XML (always compressed
      #   per spec §7 — "it is never stored in uncompressed form")
      # @param private_data [String, nil] optional private data
      # @return [Hash{Symbol => String}] `{ woff_binary: <bytes> }`
      def write_font(font, zlib_level:, uncompressed:, compression_threshold:,
                     metadata: nil, private_data: nil)
        tables = collect_tables_data(font)
        compressed_tables = compress_tables(
          tables,
          zlib_level: uncompressed ? 0 : zlib_level,
          skip_compression: uncompressed,
          compression_threshold: compression_threshold,
        )
        # Per spec §7, metadata MUST always be zlib-compressed regardless of
        # the per-table `uncompressed` flag.
        compressed_metadata = compress_metadata(metadata, zlib_level:)
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

      # Collect all table data from font in input-font order (spec §6: tables
      # MUST be stored in the same order as the well-formed input font).
      #
      # @param font [TrueTypeFont, OpenTypeFont]
      # @return [Hash<String, String>]
      def collect_tables_data(font)
        font.table_names.each_with_object({}) do |tag, h|
          data = font.table_data[tag]
          h[tag] = data if data
        end
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

      # Compress metadata with zlib. Per spec §7, metadata MUST always be
      # zlib-compressed — `skip_compression` is intentionally not exposed
      # here. The zlib output is used even when it is larger than the input
      # (e.g. tiny XML payloads where zlib header+checksum overhead exceeds
      # any compression gain); the spec mandates compression, not optimality.
      # Returns nil if no metadata was supplied.
      #
      # @param metadata [String, nil]
      # @param zlib_level [Integer]
      # @return [Hash, nil]
      def compress_metadata(metadata, zlib_level:)
        return nil unless metadata

        original_length = metadata.bytesize
        compressed = Zlib::Deflate.deflate(metadata, zlib_level)
        {
          original_data: metadata,
          compressed_data: compressed,
          original_length: original_length,
          compressed_length: compressed.bytesize,
        }
      end

      # Assemble complete WOFF binary.
      #
      # Computes the full layout (offsets + padding) up front so the header
      # fields (metaOffset, privOffset) point to the correct locations, then
      # emits header → directory → tables → optional metadata → optional
      # private data.
      #
      # @param compressed_tables [Hash<String, Hash>] in input-font order
      # @param font [TrueTypeFont, OpenTypeFont]
      # @param compressed_metadata [Hash, nil]
      # @param private_data [String, nil]
      # @return [String]
      def build_woff_file(compressed_tables, font, compressed_metadata,
                          private_data)
        header_size = 44
        num_tables = compressed_tables.length
        data_start = header_size + (num_tables * 20)

        # Lay out tables in input-font order with 4-byte alignment padding.
        # Each entry: { tag:, info:, offset:, pad_bytes: }
        entries = []
        cursor = data_start
        compressed_tables.each do |tag, info|
          pad = Utilities::Padding.boundary(info[:compressed_length])
          entries << { tag:, info:, offset: cursor, pad_bytes: "\x00" * pad }
          cursor += info[:compressed_length] + pad
        end
        tables_end = cursor

        metadata_size = compressed_metadata ? compressed_metadata[:compressed_length] : 0
        # metaOffset/privOffset are 0 when their block is absent (spec §4:
        # offsets to optional blocks; convention is 0 for "not present").
        metadata_offset = compressed_metadata ? tables_end : 0
        metadata_end = tables_end + metadata_size

        private_size = private_data ? private_data.bytesize : 0
        private_offset = private_data ? metadata_end : 0
        total_size = metadata_end + private_size

        # totalSfntSize: reconstructed SFNT size with per-table 4-byte padding.
        # spec §4: "Total size needed for the uncompressed font data, including
        # the sfnt header, directory, and font tables (including padding)."
        sfnt_header_size = 12
        sfnt_dir_size = num_tables * 16
        sfnt_tables_size = compressed_tables.values.sum do |t|
          Utilities::Padding.aligned_size(t[:original_length])
        end
        total_sfnt_size = sfnt_header_size + sfnt_dir_size + sfnt_tables_size

        io = StringIO.new
        io.set_encoding(Encoding::BINARY)
        write_woff_header(
          io, font, total_size, total_sfnt_size, num_tables,
          compressed_metadata, metadata_offset, metadata_size,
          private_offset, private_size
        )
        write_table_directory(io, entries)
        write_compressed_table_data(io, entries)
        write_metadata(io, compressed_metadata) if compressed_metadata
        write_private_data(io, private_data) if private_data

        io.string
      end

      # Write WOFF header (44 bytes).
      def write_woff_header(io, font, total_size, total_sfnt_size, num_tables,
                           compressed_metadata, metadata_offset, metadata_size,
                           private_offset, private_size)
        flavor = if font.is_a?(SfntSource) && font.cff?
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

      # Write table directory entries (20 bytes each), one per laid-out entry.
      def write_table_directory(io, entries)
        entries.each do |e|
          checksum = Utilities::ChecksumCalculator
            .calculate_table_checksum(e[:info][:original_data])
          io.write(e[:tag])                                    # tag
          io.write([e[:offset]].pack("N"))                     # offset
          io.write([e[:info][:compressed_length]].pack("N"))   # compLength
          io.write([e[:info][:original_length]].pack("N"))     # origLength
          io.write([checksum].pack("N"))                       # origChecksum
        end
      end

      # Write each table's compressed data followed by 4-byte alignment
      # padding (spec §5/§6: tables MUST be zero-padded to next boundary).
      def write_compressed_table_data(io, entries)
        entries.each do |e|
          io.write(e[:info][:compressed_data])
          io.write(e[:pad_bytes])
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
