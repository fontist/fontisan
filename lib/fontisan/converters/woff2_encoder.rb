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
      #   - `:transform_tables` (bool, default false; glyf/loca are always
      #     transformed per WOFF2 spec section 5.3 regardless of this flag)
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

        glyf_transform = apply_glyf_loca_transform!(table_data, font)

        transformer = Woff2::TableTransformer.new(font)
        transform_enabled = resolved.fetch(:transform_tables, false)
        entries, transformed_data = build_table_entries(table_data,
                                                        transformer,
                                                        transform_enabled,
                                                        glyf_transform:)

        compressed_data = compress_tables(entries, table_data,
                                          transformed_data, quality)

        total_sfnt_size = calculate_sfnt_size(table_data,
                                              glyf_transform:)
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

      # Apply the WOFF2 glyf/loca paired transform per spec section 5.1/5.3.
      #
      # Returns a hash with the transformed glyf bytes and the original
      # loca length needed to emit its synthetic directory entry, or nil
      # for CFF fonts or fonts missing glyf/loca. The original glyf bytes
      # are kept in `table_data` so its `origLength` is preserved; the
      # transformed bytes are passed to the entries builder separately.
      #
      # @return [Hash{Symbol => Object}, nil]
      def apply_glyf_loca_transform!(table_data, font)
        return nil unless font.respond_to?(:has_table?)
        return nil unless font.has_table?("glyf") && font.has_table?("loca")

        glyf_data = table_data["glyf"]
        loca_data = table_data["loca"]
        return nil unless glyf_data && loca_data

        maxp = font.table("maxp")
        head = font.table("head")
        return nil unless maxp && head

        transformed = Woff2::GlyfLocaTransform.new(
          glyf_data:,
          loca_data:,
          num_glyphs: maxp.num_glyphs,
          index_format: head.index_to_loc_format,
        ).transform

        loca_orig_length = loca_data.bytesize
        table_data.delete("loca")

        { transformed_glyf: transformed, loca_orig_length: }
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
      # When `glyf_transform` is provided, glyf gets a transformLength entry
      # (transformed bytes via Woff2::GlyfLocaTransform) and a synthetic
      # loca entry follows glyf per spec section 5.5 with transformLength=0.
      #
      # @return [Array(Array<Entry>, Hash<String, String>)]
      #   Pair of entries and the transformed-by-tag data map.
      def build_table_entries(table_data, transformer, transform_enabled,
                              glyf_transform: nil)
        entries = []
        transformed_data = {}

        table_data.keys.sort.each do |tag|
          if tag == "glyf" && glyf_transform
            entries << build_glyf_entry(table_data["glyf"],
                                        glyf_transform[:transformed_glyf])
            entries << build_loca_entry(glyf_transform[:loca_orig_length])
            transformed_data["glyf"] = glyf_transform[:transformed_glyf]
          else
            entry = build_entry(tag:, data: table_data[tag], transformer:,
                                transform_enabled:, transformed_data:)
            entries << entry if entry
          end
        end

        [entries, transformed_data]
      end

      def build_entry(tag:, data:, transformer:, transform_enabled:,
                      transformed_data:)
        return nil unless data

        # loca is combined into glyf during transformation.
        return nil if tag == "loca" && transform_enabled && transformer.transformable?("glyf")

        entry = Woff2::Directory::Entry.new
        entry.tag = tag
        entry.orig_length = data.bytesize

        if transform_enabled && transformer.transformable?(tag) && tag != "glyf" && tag != "loca"
          transformed = transformer.transform_table(tag)
          if transformed&.bytesize&.positive? && transformed.bytesize < data.bytesize
            entry.transform_length = transformed.bytesize
            transformed_data[tag] = transformed
          end
        end

        entry.flags = entry.calculate_flags
        entry
      end

      # Build the glyf directory entry. origLength is the original (input)
      # glyf size; transformLength is the size of the WOFF2-transformed
      # glyf stream per spec section 5.1.
      def build_glyf_entry(orig_data, transformed_data)
        entry = Woff2::Directory::Entry.new
        entry.tag = "glyf"
        entry.orig_length = orig_data.bytesize
        entry.transform_length = transformed_data.bytesize
        entry.flags = entry.calculate_flags
        entry
      end

      # Build the synthetic loca directory entry for transformed glyf/loca.
      # Per spec section 5.3, transformLength MUST be 0 and the data is
      # omitted from the brotli-compressed block.
      def build_loca_entry(orig_length)
        entry = Woff2::Directory::Entry.new
        entry.tag = "loca"
        entry.orig_length = orig_length
        entry.transform_length = 0
        entry.flags = entry.calculate_flags
        entry
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

      # Calculate total SFNT size (uncompressed) per spec.
      #
      # When glyf/loca are transformed, loca's data is omitted from the
      # brotli-compressed block but is reconstructed by the decoder. The
      # SFNT size still includes the reconstructed loca table.
      def calculate_sfnt_size(table_data, glyf_transform: nil)
        size = 12 # offset table
        size += table_data.size * 16 # table directory
        size += 16 if glyf_transform # synthetic loca directory entry

        table_data.each_value do |data|
          size += data.bytesize
          size += (4 - (data.bytesize % 4)) % 4 # pad to 4-byte boundary
        end

        if glyf_transform
          loca_len = glyf_transform[:loca_orig_length]
          size += loca_len
          size += (4 - (loca_len % 4)) % 4
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
