# frozen_string_literal: true

require "digest"
require "time"

module Fontisan
  module Commands
    # Produces a complete per-face font audit report.
    #
    # One AuditReport per face. For standalone fonts (TTF/OTF/WOFF/WOFF2),
    # #run returns a single AuditReport. For collections (TTC/OTC/dfont),
    # #run returns an Array<AuditReport> — one per face, in source order.
    #
    # The report combines:
    # - Provenance (sha256, source format, fontisan version, generated_at)
    # - Identity (name table)
    # - Style (OS/2 + head + fvar via Audit::StyleExtractor)
    # - Coverage (cmap mappings, glyph count, cmap subtable formats)
    # - Aggregations (Unicode blocks/scripts via local UCD cache;
    #   OpenType scripts/features via GSUB/GPOS)
    #
    # UCD is auto-downloaded on first use; failures degrade gracefully with
    # a recorded warning rather than aborting the audit.
    class AuditCommand < BaseCommand
      # @return [Models::Audit::AuditReport, Array<Models::Audit::AuditReport>]
      def run
        if FontLoader.collection?(@font_path)
          audit_collection
        else
          audit_face(@font, 0, 1)
        end
      end

      # Write one file per face under `to` (a directory). Pure utility —
      # operates on a pre-built reports array, no font_path required.
      #
      # @param reports [Array<Models::Audit::AuditReport>]
      # @param to [String] output directory; created if missing
      # @param format [Symbol] :yaml or :json
      # @return [Array<String>] written file paths
      def self.write_reports(reports, to:, format: :yaml)
        require "fileutils"
        FileUtils.mkdir_p(to)

        reports.map do |report|
          path = File.join(to, output_filename(report, format))
          content = format == :json ? report.to_json : report.to_yaml
          File.write(path, content)
          path
        end
      end

      # Compute the per-face filename for a report.
      #
      # @param report [Models::Audit::AuditReport]
      # @param format [Symbol] :yaml or :json
      # @return [String] filename only (no directory)
      def self.output_filename(report, format)
        ext = format == :json ? "json" : "yaml"
        base = if report.num_fonts_in_source == 1
                 safe_filename(report.postscript_name || report.family_name || "font")
               else
                 format("%<idx>02d-%<name>s",
                        idx: report.font_index,
                        name: safe_filename(report.postscript_name || "face"))
               end
        "#{base}.#{ext}"
      end

      # Sanitize an arbitrary string into a filesystem-safe basename.
      #
      # @param name [String, nil]
      # @return [String]
      def self.safe_filename(name)
        return "font" if name.nil? || name.empty?

        name.gsub(/[^A-Za-z0-9._-]/, "_")
      end

      private

      def audit_collection
        collection = FontLoader.load_collection(@font_path)
        num = collection.num_fonts
        Array.new(num) do |index|
          font = FontLoader.load(@font_path, font_index: index,
                                             mode: LoadingModes::FULL)
          audit_face(font, index, num)
        end
      end

      def audit_face(font, font_index, num_fonts_in_source)
        style = Audit::StyleExtractor.new(font)
        codepoints = extract_codepoints(font)
        ucd = ensure_ucd(@options[:ucd_version])

        Models::Audit::AuditReport.new(
          generated_at: Time.now.utc.iso8601,
          fontisan_version: Fontisan::VERSION,
          source_file: File.expand_path(@font_path),
          source_sha256: Digest::SHA256.file(@font_path).hexdigest,
          source_format: source_format,
          font_index: font_index,
          num_fonts_in_source: num_fonts_in_source,
          **identity_fields(font),
          weight_class: style.weight_class,
          width_class: style.width_class,
          italic: style.italic,
          bold: style.bold,
          panose: style.panose,
          is_variable: style.variable?,
          axes: style.axes,
          total_codepoints: codepoints.length,
          total_glyphs: total_glyphs(font),
          cmap_subtables: cmap_subtable_formats(font),
          codepoints: codepoints_for_report(codepoints),
          **aggregation_fields(codepoints, ucd),
          opentype_scripts: opentype_scripts(font),
          features: all_features(font),
          warning: ucd[:warning],
        )
      end

      def source_format
        FontLoader.detect_format(@font_path)&.to_s
      end

      def identity_fields(font)
        return type1_identity_fields(font) if font.is_a?(Type1Font)

        sfnt_identity_fields(font)
      end

      def sfnt_identity_fields(font)
        name_table = font.table(Constants::NAME_TAG) if font.has_table?(Constants::NAME_TAG)
        head_table = font.table(Constants::HEAD_TAG) if font.has_table?(Constants::HEAD_TAG)

        {
          family_name: name_table&.english_name(Tables::Name::FAMILY),
          subfamily_name: name_table&.english_name(Tables::Name::SUBFAMILY),
          full_name: name_table&.english_name(Tables::Name::FULL_NAME),
          postscript_name: name_table&.english_name(Tables::Name::POSTSCRIPT_NAME),
          version: name_table&.english_name(Tables::Name::VERSION),
          font_revision: head_table&.font_revision,
        }
      end

      def type1_identity_fields(font)
        font_info = font.font_dictionary&.font_info
        {
          family_name: font_info&.family_name,
          subfamily_name: nil,
          full_name: font_info&.full_name,
          postscript_name: font.font_name,
          version: font_info&.version,
          font_revision: nil,
        }
      end

      def extract_codepoints(font)
        return [] unless font.has_table?(Constants::CMAP_TAG)

        font.table(Constants::CMAP_TAG).unicode_mappings.keys
      end

      def total_glyphs(font)
        return nil unless font.has_table?(Constants::MAXP_TAG)

        font.table(Constants::MAXP_TAG).num_glyphs
      end

      def cmap_subtable_formats(font)
        return [] unless font.has_table?(Constants::CMAP_TAG)

        font.table(Constants::CMAP_TAG).subtable_formats
      end

      def codepoints_for_report(codepoints)
        return [] if @options[:no_codepoints]

        codepoints.map { |cp| format("U+%<cp>04X", cp: cp) }
      end

      def aggregation_fields(codepoints, ucd)
        return empty_aggregation(ucd) if ucd[:blocks_index].nil?

        blocks_hashes = Ucd::Aggregator.aggregate_blocks(codepoints,
                                                         ucd[:blocks_index])
        {
          ucd_version: ucd[:version],
          blocks: blocks_hashes.map { |block_hash| build_audit_block(block_hash) },
          unicode_scripts: Ucd::Aggregator.aggregate_scripts(codepoints,
                                                             ucd[:scripts_index]),
        }
      end

      def empty_aggregation(ucd)
        { ucd_version: ucd[:version], blocks: [], unicode_scripts: [] }
      end

      def build_audit_block(block_hash)
        Models::Audit::AuditBlock.new(
          name: block_hash[:name],
          first_cp: block_hash[:first_cp],
          last_cp: block_hash[:last_cp],
          range: format("U+%<first>04X-U+%<last>04X",
                        first: block_hash[:first_cp], last: block_hash[:last_cp]),
          total: block_hash[:total],
          covered: block_hash[:covered],
          fill_ratio: block_hash[:fill_ratio],
          complete: block_hash[:complete],
        )
      end

      def opentype_scripts(font)
        scripts = Set.new
        scripts.merge(font.table(Constants::GSUB_TAG).scripts) if font.has_table?(Constants::GSUB_TAG)
        scripts.merge(font.table(Constants::GPOS_TAG).scripts) if font.has_table?(Constants::GPOS_TAG)
        scripts.sort
      end

      def all_features(font)
        features = Set.new
        scripts = opentype_scripts(font)

        if font.has_table?(Constants::GSUB_TAG)
          gsub = font.table(Constants::GSUB_TAG)
          scripts.each { |tag| features.merge(gsub.features(script_tag: tag)) }
        end

        if font.has_table?(Constants::GPOS_TAG)
          gpos = font.table(Constants::GPOS_TAG)
          scripts.each { |tag| features.merge(gpos.features(script_tag: tag)) }
        end

        features.sort
      end

      # Resolve + locally ensure the UCD indices for the requested version.
      # Returns a hash with :version, :blocks_index, :scripts_index, and
      # optional :warning. Indices are nil when UCD could not be obtained.
      def ensure_ucd(version_intent)
        version = Ucd::VersionResolver.resolve(version_intent)

        with_local_indices(version) do |blocks_path, scripts_path|
          {
            version: version,
            blocks_index: Ucd::Index.load(blocks_path),
            scripts_index: Ucd::Index.load(scripts_path),
          }
        end
      rescue Ucd::UnknownVersionError => e
        { version: nil, blocks_index: nil, scripts_index: nil,
          warning: "UCD version rejected: #{e.message}" }
      rescue StandardError => e
        {
          version: version,
          blocks_index: nil,
          scripts_index: nil,
          warning: "UCD unavailable for version #{version}: #{e.message}",
        }
      end

      # Ensure the cache + index files exist for `version`, then yield their
      # paths. Re-raises non-fatal download/index errors as warnings.
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
