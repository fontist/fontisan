# frozen_string_literal: true

require "yaml"
require "stringio"

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
    # 4. Apply WOFF2 spec encoder rules (drop DSIG, mark head.flags)
    # 5. Transform tables (placeholder for glyf/loca/hmtx optimization)
    # 6. Compress all tables with single Brotli stream
    # 7. Build WOFF2 header and table directory
    # 8. Assemble complete WOFF2 binary
    #
    # @example Convert TTF to WOFF2
    #   encoder = Woff2Encoder.new
    #   result = encoder.convert(font)
    #   File.binwrite('font.woff2', result[:woff2_binary])
    class Woff2Encoder
      include ConversionStrategy

      # @return [Hash] Configuration settings
      attr_reader :config

      # Initialize encoder with configuration.
      #
      # The encoder is stateless per call; all conversion knobs come through
      # the per-convert options hash. The config file supplies default values
      # only for fields not expressed via the DSL.
      #
      # @param config_path [String, nil] Path to config file
      def initialize(config_path: nil)
        @config = load_configuration(config_path)
      end

      option :brotli_quality, type: :integer, range: 0..11, default: 11,
                              cli: "--brotli-quality=N",
                              desc: "Brotli quality (0=fastest, 11=smallest)"
      option :transform_tables, type: :boolean, default: false,
                                cli: "--[no-]transform-tables",
                                desc: "apply glyf/loca and hmtx transformations"

      # Convert font to WOFF2 format.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash{Symbol => Object}] Per-call options:
      #   - `:brotli_quality` (0–11, default from config or 11)
      #   - `:transform_tables` (bool, default false)
      #   - `:quality` — legacy alias for `:brotli_quality` (backward compat)
      # @return [Hash{Symbol => String}] `{ woff2_binary: <bytes> }`
      # @raise [ArgumentError] if any option fails validation
      # @raise [Fontisan::Error] if encoding fails
      def convert(font, options = {})
        validate(font, :woff2)

        resolved = normalize_legacy_quality(options)
        self.class.validate_options!(strategy_options(resolved))

        quality = resolved.fetch(:brotli_quality) do
          config["brotli"]["quality"]
        end

        flavor = detect_flavor(font)
        table_data = collect_tables(font, options)
        Woff2::EncoderRules.apply!(table_data)

        transformer = Woff2::TableTransformer.new(font)
        transform_enabled = resolved.fetch(:transform_tables, false)
        entries, transformed_data = build_table_entries(table_data,
                                                        transformer,
                                                        transform_enabled)

        compressed_data = compress_tables(entries, table_data,
                                          transformed_data, quality)

        total_sfnt_size = calculate_sfnt_size(table_data)
        header = build_header(
          flavor: flavor,
          num_tables: entries.size,
          total_sfnt_size: total_sfnt_size,
          total_compressed_size: compressed_data.bytesize,
        )

        { woff2_binary: assemble_woff2(header, entries, compressed_data) }
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

        required_tables = %w[head hhea maxp]
        required_tables.each do |tag|
          unless font.table(tag)
            raise Fontisan::Error,
                  "Font is missing required table: #{tag}"
          end
        end

        unless font.has_table?("glyf") || font.has_table?("CFF ") || font.has_table?("CFF2")
          raise Fontisan::Error,
                "Font must have either glyf or CFF/CFF2 table"
        end

        true
      end

      private

      # Normalize legacy `:quality` option to `:brotli_quality`.
      #
      # Internal callers and older specs use `:quality`; the public DSL uses
      # `:brotli_quality`. Returns a new hash; does not mutate the input.
      def normalize_legacy_quality(options)
        return options unless options.key?(:quality) && !options.key?(:brotli_quality)

        options.merge(brotli_quality: options[:quality])
      end

      # Slice options to those declared by this strategy.
      def strategy_options(options)
        names = self.class.supported_options.to_set(&:name)
        options.select { |k, _| names.include?(k.to_sym) }
      end

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

      def default_config_path
        File.join(__dir__, "..", "config", "woff2_settings.yml")
      end

      def default_configuration
        {
          "brotli" => {
            "quality" => 11,
            "mode" => "font",
          },
          "transformations" => {
            "enabled" => true,
            "glyf_loca" => true,
            "hmtx" => true,
          },
          "metadata" => {
            "include" => false,
          },
        }
      end

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

      # Collect all tables from font.
      #
      # Spec-mandated exclusions (DSIG) and adjustments (head.flags bit 11)
      # are applied by `Woff2::EncoderRules`, not here — this method is a
      # pure reader.
      def collect_tables(font, _options = {})
        table_names = if font.respond_to?(:table_names)
                        font.table_names
                      else
                        %w[head hhea maxp OS/2 name cmap post hmtx glyf loca
                           CFF]
                      end

        table_names.each_with_object({}) do |tag, tables|
          data = get_table_data(font, tag)
          tables[tag] = data if data && !data.empty?
        end
      end

      def get_table_data(font, tag)
        if font.respond_to?(:table_data)
          font.table_data[tag]
        elsif font.respond_to?(:table)
          table = font.table(tag)
          table&.to_binary_s if table.respond_to?(:to_binary_s)
        end
      end

      # Build table directory entries.
      #
      # @return [Array(Array<Entry>, Hash<String, String>)]
      #   Pair of entries and the transformed-by-tag data map.
      def build_table_entries(table_data, transformer, transform_enabled)
        entries = []
        transformed_data = {}

        table_data.keys.sort.each do |tag|
          # loca is combined into glyf during transformation.
          next if tag == "loca" && transform_enabled && transformer.transformable?("glyf")

          entry = Woff2::Directory::Entry.new
          entry.tag = tag

          data = table_data[tag]
          entry.orig_length = data.bytesize

          if transform_enabled && transformer.transformable?(tag)
            transformed = transformer.transform_table(tag)
            if transformed&.bytesize&.positive? && transformed.bytesize < data.bytesize
              entry.transform_length = transformed.bytesize
              transformed_data[tag] = transformed
            end
          end

          entry.flags = entry.calculate_flags
          entries << entry
        end

        [entries, transformed_data]
      end

      def compress_tables(entries, table_data, transformed_data, quality)
        combined_data = String.new(encoding: Encoding::BINARY)

        entries.each do |entry|
          data = transformed_data[entry.tag] || table_data[entry.tag]
          next unless data

          combined_data << data
        end

        Utilities::BrotliWrapper.compress(combined_data, quality: quality)
      end

      def calculate_sfnt_size(table_data)
        size = 12 # offset table
        size += table_data.size * 16 # table directory

        table_data.each_value do |data|
          size += data.bytesize
          size += (4 - (data.bytesize % 4)) % 4 # pad to 4-byte boundary
        end

        size
      end

      def build_header(flavor:, num_tables:, total_sfnt_size:,
                       total_compressed_size:)
        header = Woff2::Woff2Header.new
        header.signature = Woff2::Woff2Header::SIGNATURE
        header.flavor = flavor
        header.file_length = 0 # updated by update_woff2_length!
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

      def assemble_woff2(header, entries, compressed_data)
        woff2_data = String.new(encoding: Encoding::BINARY)
        woff2_data << header.to_binary_s

        entries.each do |entry|
          woff2_data << [entry.flags].pack("C")
          woff2_data << entry.tag.ljust(4, "\x00") unless entry.known_tag?
          woff2_data << Woff2::Directory.encode_uint_base128(entry.orig_length)
          if entry.transformed?
            woff2_data << Woff2::Directory.encode_uint_base128(entry.transform_length)
          end
        end

        woff2_data << compressed_data
        update_woff2_length!(woff2_data)
        woff2_data
      end

      def update_woff2_length!(woff2_data)
        woff2_data[8, 4] = [woff2_data.bytesize].pack("N")
      end
    end
  end
end
