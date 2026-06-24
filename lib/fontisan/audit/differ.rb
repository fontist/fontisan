# frozen_string_literal: true

module Fontisan
  module Audit
    # Computes an {Models::Audit::AuditDiff} between two AuditReports.
    #
    # Pure: no I/O, no font parsing. Both reports must already be built
    # (Commands::AuditCompareCommand handles loading reports from disk
    # or auditing fresh fonts before invoking the differ).
    #
    # Comparison shape:
    #   - Scalar fields: one FieldChange per differing field.
    #   - Codepoint coverage: CodepointSetDiff built from the cmap range
    #     lists (expanded to integer sets for set arithmetic, then
    #     re-coalesced to ranges for output).
    #   - Structural inventories (features, scripts, blocks, languages):
    #     simple array set-diffs.
    class Differ
      # Scalar AuditReport fields compared field-by-field. Excludes
      # generated_at / source_sha256 / source_file (per-report identity),
      # codepoints / codepoint_ranges (handled via CodepointSetDiff),
      # and nested models (surfaced via structural add/remove lists).
      COMPARED_FIELDS = %i[
        family_name subfamily_name full_name postscript_name version
        font_revision weight_class width_class italic bold panose
        total_codepoints total_glyphs ucd_version cldr_version
      ].freeze

      def initialize(left_report, right_report)
        @left = left_report
        @right = right_report
      end

      # @return [Models::Audit::AuditDiff]
      def diff
        Models::Audit::AuditDiff.new(
          left_source: @left.source_file,
          right_source: @right.source_file,
          field_changes: field_changes,
          codepoints: codepoint_diff,
          added_features: set_diff(features(@right), features(@left)),
          removed_features: set_diff(features(@left), features(@right)),
          added_scripts: set_diff(scripts(@right), scripts(@left)),
          removed_scripts: set_diff(scripts(@left), scripts(@right)),
          added_blocks: set_diff(blocks(@right), blocks(@left)),
          removed_blocks: set_diff(blocks(@left), blocks(@right)),
          added_languages: set_diff(languages(@right), languages(@left)),
          removed_languages: set_diff(languages(@left), languages(@right)),
        )
      end

      private

      def field_changes
        COMPARED_FIELDS.filter_map do |field|
          left_val = @left.public_send(field)
          right_val = @right.public_send(field)
          next if left_val == right_val

          Models::Audit::FieldChange.new(
            field: field.to_s,
            left: serialize_value(left_val),
            right: serialize_value(right_val),
          )
        end
      end

      def codepoint_diff
        left_set = codepoints_from_ranges(@left)
        right_set = codepoints_from_ranges(@right)
        added = right_set - left_set
        removed = left_set - right_set
        unchanged = left_set & right_set

        Models::Audit::CodepointSetDiff.new(
          added: CodepointRangeCoalescer.call(added.to_a),
          removed: CodepointRangeCoalescer.call(removed.to_a),
          added_count: added.size,
          removed_count: removed.size,
          unchanged_count: unchanged.size,
        )
      end

      # Expand a report's compact codepoint range list into a Set<Integer>.
      # Works for both default reports (range list populated) and
      # --all-codepoints reports (range list is also populated).
      def codepoints_from_ranges(report)
        ranges = report.codepoint_ranges || []
        ranges.each_with_object(Set.new) do |range, set|
          (range.first_cp..range.last_cp).each { |cp| set << cp }
        end
      end

      def features(report)
        report.opentype_layout&.features || []
      end

      def scripts(report)
        report.opentype_layout&.scripts || []
      end

      def blocks(report)
        (report.blocks || []).map(&:name)
      end

      def languages(report)
        (report.language_coverage || []).map(&:language)
      end

      def set_diff(minuend, subtrahend)
        (Array(minuend) - Array(subtrahend)).sort
      end

      def serialize_value(value)
        case value
        when nil then ""
        when String, Integer, Float then value.to_s
        when true, false then value.to_s
        else value.to_yaml
        end
      end
    end
  end
end
