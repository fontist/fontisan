# frozen_string_literal: true

module Fontisan
  module Formatters
    # Human-readable diff of two {Models::Audit::AuditReport}s.
    #
    # Output groups changes by kind: scalar field changes, codepoint set
    # deltas (added/removed counts and a preview of the ranges), then
    # structural inventory changes (scripts, features, blocks, languages).
    # Empty sections are omitted so a no-op diff prints only the header.
    class AuditDiffTextRenderer
      SEPARATOR = "=" * 80
      LIST_LIMIT = 10

      # @param diff [Models::Audit::AuditDiff]
      def initialize(diff)
        @diff = diff
        @lines = []
      end

      # @return [String]
      def render
        render_header
        render_field_changes
        render_codepoint_delta
        render_structural_changes
        render_empty_note
        @lines.join("\n")
      end

      private

      def render_header
        @lines << "AUDIT DIFF"
        @lines << SEPARATOR
        @lines << "left:  #{@diff.left_source}"
        @lines << "right: #{@diff.right_source}"
      end

      def render_field_changes
        changes = Array(@diff.field_changes)
        return if changes.empty?

        section("FIELD CHANGES (#{changes.size})")
        changes.each do |change|
          @lines << "  #{change.field}: #{change.left.inspect} → #{change.right.inspect}"
        end
      end

      def render_codepoint_delta
        delta = @diff.codepoints
        return unless delta && (delta.added_count.to_i.positive? || delta.removed_count.to_i.positive?)

        section("CODEPOINT COVERAGE")
        @lines << "  added:      #{delta.added_count}"
        @lines << "  removed:    #{delta.removed_count}"
        @lines << "  unchanged:  #{delta.unchanged_count}"
        preview_added(delta)
        preview_removed(delta)
      end

      def preview_added(delta)
        ranges = Array(delta.added)
        return if ranges.empty?

        @lines << "  + #{format_ranges(ranges)}"
      end

      def preview_removed(delta)
        ranges = Array(delta.removed)
        return if ranges.empty?

        @lines << "  - #{format_ranges(ranges)}"
      end

      def render_structural_changes
        render_set("SCRIPTS",   @diff.added_scripts,   @diff.removed_scripts)
        render_set("FEATURES",  @diff.added_features,  @diff.removed_features)
        render_set("BLOCKS",    @diff.added_blocks,    @diff.removed_blocks)
        render_set("LANGUAGES", @diff.added_languages, @diff.removed_languages)
      end

      def render_set(name, added, removed)
        added = Array(added)
        removed = Array(removed)
        return if added.empty? && removed.empty?

        section("#{name} CHANGES")
        @lines << "  + #{truncate(added)}" unless added.empty?
        @lines << "  - #{truncate(removed)}" unless removed.empty?
      end

      def render_empty_note
        return unless @diff.empty?

        @lines << ""
        @lines << "(no differences)"
      end

      # ---- helpers --------------------------------------------------------

      def section(title)
        @lines << ""
        @lines << title
      end

      def truncate(list)
        shown = list.first(LIST_LIMIT).join(", ")
        shown += ", ..." if list.size > LIST_LIMIT
        shown
      end

      def format_ranges(ranges)
        shown = ranges.first(LIST_LIMIT).map do |r|
          "U+#{format('%04X', r.first_cp)}-U+#{format('%04X', r.last_cp)}"
        end.join(", ")
        shown += ", ..." if ranges.size > LIST_LIMIT
        shown
      end
    end
  end
end
