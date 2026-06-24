# frozen_string_literal: true

module Fontisan
  module Audit
    # Value object carrying everything an extractor needs to do its job.
    #
    # Extractors never reach back into AuditCommand state — they read
    # exclusively from the Context. Shared derived data (codepoints,
    # UCD indices, source format) is memoized here so multiple
    # extractors don't recompute it.
    class Context
      attr_reader :font, :font_path, :font_index, :num_fonts_in_source,
                  :options

      def initialize(font:, font_path:, font_index:, num_fonts_in_source:,
                     options:)
        @font = font
        @font_path = font_path
        @font_index = font_index
        @num_fonts_in_source = num_fonts_in_source
        @options = options
      end

      def codepoints
        @codepoints ||= extract_codepoints
      end

      def ucd
        @ucd ||= resolve_ucd
      end

      def source_format
        @source_format ||= FontLoader.detect_format(@font_path)&.to_s
      end

      def all_codepoints?
        @options[:all_codepoints] == true
      end

      private

      def extract_codepoints
        return [] unless @font.has_table?(Constants::CMAP_TAG)

        @font.table(Constants::CMAP_TAG).unicode_mappings.keys
      end

      def resolve_ucd
        version = Ucd::VersionResolver.resolve(@options[:ucd_version])

        with_local_indices(version) do |blocks_path, scripts_path|
          {
            version: version,
            blocks_index: Ucd::Index.load(blocks_path),
            scripts_index: Ucd::Index.load(scripts_path),
            warning: nil,
          }
        end
      rescue Ucd::UnknownVersionError => e
        { version: nil, blocks_index: nil, scripts_index: nil,
          warning: "UCD version rejected: #{e.message}" }
      rescue StandardError => e
        version_ref = @ucd&.fetch(:version, nil)
        {
          version: version_ref,
          blocks_index: nil,
          scripts_index: nil,
          warning: "UCD unavailable for version #{version_ref}: #{e.message}",
        }
      end

      def with_local_indices(version)
        unless Ucd::CacheManager.cached?(version)
          Ucd::Downloader.download(version)
        end
        unless Ucd::CacheManager.blocks_index_path(version).exist?
          Ucd::IndexBuilder.build(version)
        end
        yield Ucd::CacheManager.blocks_index_path(version),
          Ucd::CacheManager.scripts_index_path(version)
      end
    end
  end
end
