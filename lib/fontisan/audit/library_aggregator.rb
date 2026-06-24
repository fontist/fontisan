# frozen_string_literal: true

module Fontisan
  module Audit
    # Pure cross-face aggregation over a list of AuditReports.
    #
    # No I/O, no font parsing — operates only on already-built reports.
    # Easy to spec with synthetic reports and trivially testable. The
    # orchestrator ({LibraryAuditor}) handles file discovery and per-face
    # auditing; this class owns the rollups that span faces.
    #
    # Aggregates:
    #   - aggregate_metrics: sum of total_codepoints and total_glyphs.
    #   - script_coverage:   one ScriptCoverageRow per Unicode script,
    #                         listing faces that cover it.
    #   - duplicate_groups:  files bucketed by source_sha256 (size > 1).
    #   - license_distribution: face counts keyed by license_url.
    class LibraryAggregator
      # @param reports [Array<Models::Audit::AuditReport>]
      # @return [Hash{Symbol => Object}] keys: :aggregate_metrics,
      #   :script_coverage, :duplicate_groups, :license_distribution
      def aggregate(reports)
        {
          aggregate_metrics: aggregate_metrics(reports),
          script_coverage: build_script_coverage(reports),
          duplicate_groups: find_duplicates(reports),
          license_distribution: license_distribution(reports),
        }
      end

      private

      def aggregate_metrics(reports)
        {
          total_codepoints: reports.sum(&:total_codepoints),
          total_glyphs: reports.sum(&:total_glyphs),
        }
      end

      def build_script_coverage(reports)
        by_script = Hash.new { |h, k| h[k] = [] }
        reports.each do |report|
          face = report.postscript_name || report.source_file
          scripts_for(report).each { |script| by_script[script] << face }
        end
        by_script.map do |script, faces|
          Models::Audit::ScriptCoverageRow.new(
            script: script,
            face_count: faces.size,
            faces: faces.uniq.sort,
          )
        end.sort_by { |row| [-row.face_count, row.script] }
      end

      def find_duplicates(reports)
        reports.group_by(&:source_sha256)
          .select { |_sha, group| group.size > 1 }
          .map do |sha, group|
            Models::Audit::DuplicateGroup.new(
              source_sha256: sha,
              files: group.map(&:source_file).sort,
            )
          end
          .sort_by(&:source_sha256)
      end

      def license_distribution(reports)
        reports.each_with_object({}) do |report, counts|
          url = license_url_for(report)
          counts[url] = counts.fetch(url, 0) + 1
        end
      end

      def scripts_for(report)
        Array(report.unicode_scripts)
      end

      def license_url_for(report)
        report.licensing&.license_url || "(none)"
      end
    end
  end
end
