# frozen_string_literal: true

module Fontisan
  module Formatters
    # Human-readable overview of a {Models::Audit::LibrarySummary}.
    #
    # Lists the per-face rollup counts, aggregate metrics, script coverage
    # matrix, duplicate groups, and license distribution. The full per-face
    # AuditReports are attached to the model; this view only shows the
    # cross-face summaries (use YAML/JSON output for the full per-face data).
    class LibrarySummaryTextRenderer
      SEPARATOR = "=" * 80
      LIST_LIMIT = 15

      # @param summary [Models::Audit::LibrarySummary]
      def initialize(summary)
        @summary = summary
        @lines = []
      end

      # @return [String]
      def render
        render_header
        render_aggregates
        render_script_coverage
        render_duplicates
        render_license_distribution
        @lines.join("\n")
      end

      private

      def render_header
        @lines << "LIBRARY SUMMARY"
        @lines << SEPARATOR
        @lines << "root:    #{@summary.root_path}"
        @lines << "files:   #{@summary.total_files}   faces: #{@summary.total_faces}"
        exts = Array(@summary.scanned_extensions)
        @lines << "formats: #{exts.empty? ? '(none)' : exts.join(', ')}"
      end

      def render_aggregates
        m = @summary.aggregate_metrics || {}
        section("AGGREGATES")
        @lines << "  codepoints:     #{m[:total_codepoints] || 0}"
        @lines << "  glyphs:         #{m[:total_glyphs] || 0}"
        @lines << "  total size:     #{format_bytes(m[:total_size_bytes] || 0)}"
      end

      def render_script_coverage
        rows = Array(@summary.script_coverage)
        return if rows.empty?

        section("SCRIPT COVERAGE (top #{LIST_LIMIT})")
        rows.first(LIST_LIMIT).each do |row|
          @lines << "  #{row.script}: #{row.face_count} face#{'s' unless row.face_count == 1}"
        end
      end

      def render_duplicates
        groups = Array(@summary.duplicate_groups)
        return if groups.empty?

        section("DUPLICATES (#{groups.size} group#{'s' unless groups.size == 1})")
        groups.each do |group|
          @lines << "  sha #{group.source_sha256[0, 12]}:"
          group.files.each { |path| @lines << "    #{path}" }
        end
      end

      def render_license_distribution
        dist = @summary.license_distribution || {}
        return if dist.empty?

        section("LICENSE DISTRIBUTION")
        dist.sort_by { |_url, count| -count }.each do |url, count|
          @lines << "  #{count}  #{url}"
        end
      end

      def section(title)
        @lines << ""
        @lines << title
      end

      def format_bytes(bytes)
        return "0 B" if bytes.nil? || bytes.zero?

        if bytes < 1024
          "#{bytes} B"
        elsif bytes < 1024 * 1024
          "#{(bytes / 1024.0).round(2)} KB"
        else
          "#{(bytes / (1024.0 * 1024)).round(2)} MB"
        end
      end
    end
  end
end
