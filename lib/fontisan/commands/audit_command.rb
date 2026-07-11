# frozen_string_literal: true

require "digest"
require "time"

module Fontisan
  module Commands
    # Produces a structured {Models::AuditReport} for a single font or
    # an array of reports for every face in a collection.
    #
    # The audit report is MECE with ucode: fontisan owns the font-identity
    # axis (name table, style metadata, OpenType layout); ucode owns the
    # Unicode-coverage axis (UCD parsing, block/script aggregation). The
    # audit command emits the raw codepoint list so a consumer can run
    # ucode separately without re-reading the font.
    #
    # Delegates data extraction to existing sub-commands and table readers
    # — no table re-parsing happens here. This keeps the audit command a
    # thin orchestration layer (DRY, single source of truth).
    #
    # @example Single font
    #   cmd = AuditCommand.new("Inter.ttf", include_codepoints: true)
    #   cmd.run  # => Models::AuditReport
    #
    # @example Collection
    #   cmd = AuditCommand.new("Inter.ttc")
    #   cmd.run  # => Array<Models::AuditReport>
    class AuditCommand < BaseCommand
      # @return [Models::AuditReport, Array<Models::AuditReport>]
      def run
        if FontLoader.collection?(@font_path)
          audit_collection
        else
          audit_single_font(font_index: nil, num_fonts: 1)
        end
      end

      private

      # ------------------------------------------------------------------
      # Collection dispatch
      # ------------------------------------------------------------------

      def audit_collection
        collection = FontLoader.load_collection(@font_path)
        num = collection.num_fonts
        Array.new(num) do |idx|
          face = load_face(idx)
          build_report(face, font_index: idx, num_fonts: num)
        end
      end

      def audit_single_font(font_index:, num_fonts:)
        build_report(font, font_index: font_index, num_fonts: num_fonts)
      end

      # Reload a single face from a collection by index, with full tables
      # so the audit is complete.
      def load_face(idx)
        FontLoader.load(@font_path, font_index: idx, mode: LoadingModes::FULL)
      end

      # ------------------------------------------------------------------
      # Report assembly
      # ------------------------------------------------------------------

      # @param face [SfntFont] loaded font
      # @param font_index [Integer, nil]
      # @param num_fonts [Integer]
      # @return [Models::AuditReport]
      def build_report(face, font_index:, num_fonts:)
        Models::AuditReport.new.tap do |r|
          populate_provenance(r, font_index:, num_fonts:)
          populate_identity(r, face)
          populate_style(r, face)
          populate_coverage(r, face)
          populate_layout(r, face)
        end
      end

      # ------------------------------------------------------------------
      # Provenance
      # ------------------------------------------------------------------

      def populate_provenance(report, font_index:, num_fonts:)
        report.generated_at = Time.now.utc.iso8601
        report.fontisan_version = VERSION
        report.source_file = File.basename(@font_path)
        report.source_sha256 = Digest::SHA256.file(@font_path).hexdigest
        report.source_format = detect_source_format
        report.font_index = font_index
        report.num_fonts_in_source = num_fonts
      end

      def detect_source_format
        fmt = FontLoader.detect_format(@font_path)
        fmt ? fmt.to_s : "unknown"
      end

      # ------------------------------------------------------------------
      # Identity (name table)
      # ------------------------------------------------------------------

      def populate_identity(report, face)
        return unless face.has_table?(Constants::NAME_TAG)

        name_table = face.table(Constants::NAME_TAG)
        report.family_name = name_table.english_name(Tables::Name::FAMILY)
        report.subfamily_name = name_table.english_name(Tables::Name::SUBFAMILY)
        report.full_name = name_table.english_name(Tables::Name::FULL_NAME)
        report.postscript_name =
          name_table.english_name(Tables::Name::POSTSCRIPT_NAME)
        report.version = name_table.english_name(Tables::Name::VERSION)

        return unless face.has_table?(Constants::HEAD_TAG)

        report.font_revision = face.table(Constants::HEAD_TAG).font_revision
      end

      # ------------------------------------------------------------------
      # Style (OS/2, head, fvar)
      # ------------------------------------------------------------------

      def populate_style(report, face)
        report.is_variable = false
        report.italic = false
        report.bold = false
        populate_os2_style(report, face) if face.has_table?(Constants::OS2_TAG)
        populate_head_style(report, face) if face.has_table?(Constants::HEAD_TAG)
        populate_fvar_style(report, face) if face.has_table?(Constants::FVAR_TAG)
      end

      def populate_os2_style(report, face)
        os2 = face.table(Constants::OS2_TAG)
        report.weight_class = os2.us_weight_class
        report.width_class = os2.us_width_class
        report.italic = os2.fs_selection && (os2.fs_selection & 0x01).positive?
        report.bold = os2.fs_selection && (os2.fs_selection & 0x20).positive?
        report.panose = format_panose(os2.panose)
      end

      def populate_head_style(report, face)
        head = face.table(Constants::HEAD_TAG)
        mac_style = head.mac_style || 0
        # head macStyle overrides OS/2 fsSelection only when OS/2 didn't set it
        report.italic = true if (mac_style & 0x02).positive?
        report.bold = true if (mac_style & 0x01).positive?
      end

      def populate_fvar_style(report, face)
        report.is_variable = true
        fvar = face.table(Constants::FVAR_TAG)
        report.axes = fvar.axes.map do |axis|
          Models::AuditAxis.new(
            tag: axis.axis_tag,
            min_value: axis.min_value,
            default_value: axis.default_value,
            max_value: axis.max_value,
            name_id: axis.axis_name_id,
          )
        end
      end

      def format_panose(panose)
        return nil unless panose

        panose.to_a.join(" ")
      end

      # ------------------------------------------------------------------
      # Coverage (cmap + glyph count)
      # ------------------------------------------------------------------

      def populate_coverage(report, face)
        if face.has_table?(Constants::CMAP_TAG)
          cmap = face.table(Constants::CMAP_TAG)
          mappings = cmap.unicode_mappings || {}
          report.total_codepoints = mappings.size
          report.cmap_subtables = cmap.subtable_formats
          report.codepoints = codepoint_list(mappings.keys) if include_codepoints?
        end

        report.total_glyphs = total_glyphs(face)
      end

      def codepoint_list(codepoints)
        codepoints.sort.map { |cp| format_codepoint(cp) }
      end

      def format_codepoint(cp)
        format("U+%04X", cp)
      end

      def total_glyphs(face)
        return 0 unless face.has_table?(Constants::MAXP_TAG)

        face.table(Constants::MAXP_TAG)&.num_glyphs || 0
      rescue StandardError
        0
      end

      def include_codepoints?
        @options.fetch(:include_codepoints, true)
      end

      # ------------------------------------------------------------------
      # OpenType layout (GSUB/GPOS)
      # ------------------------------------------------------------------

      def populate_layout(report, face)
        report.opentype_scripts = collect_scripts(face)
        report.features = collect_features(face)
      end

      def collect_scripts(face)
        scripts = Set.new
        %w[GSUB GPOS].each do |tag|
          next unless face.has_table?(tag)

          table = face.table(tag)
          scripts.merge(table.scripts) if table
        end
        scripts.sort
      end

      def collect_features(face)
        features = Set.new
        %w[GSUB GPOS].each do |tag|
          next unless face.has_table?(tag)

          table = face.table(tag)
          features.merge(collect_features_from_table(table)) if table
        end
        features.sort
      end

      def collect_features_from_table(layout_table)
        scripts = begin
                    layout_table.scripts
        rescue StandardError
                    []
        end
        scripts.flat_map { |script| features_for_script(layout_table, script) }
      rescue StandardError
        []
      end

      def features_for_script(layout_table, script)
        
          layout_table.features(script_tag: script)
      rescue StandardError
          []
        
      end
    end
  end
end
