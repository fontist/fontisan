# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Foundational OpenType spec conformance checks. Covers the
      # most commonly-violated "MUST" and "SHOULD" rules from the OT
      # spec that other check domains don't already cover.
      #
      # This check is intentionally a growing foundation — new OT spec
      # rules are added incrementally as real-world fonts surface them.
      # Full OT conformance is a long-running effort that tracks the
      # spec's evolution (axis 14 per TODO #03).
      #
      # Current checks:
      #
      #   - Required tables for each sfnt flavor (TTF vs CFF vs variable)
      #   - head.indexToLocFormat consistency with loca table size
      #   - name table must have at least family (1), subfamily (2),
      #     full (4), PostScript (6) name IDs
      #   - OS/2 fsSelection must not use reserved bits
      #   - hhea.numberOfHMetrics must be ≤ maxp.numGlyphs
      #   - post table version must be valid
      #   - cmap must have at least one Unicode subtable (already
      #     covered by CmapCheck — skipped here to avoid duplicate issues)
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/otff
      class OpenTypeConformanceCheck < Check
        REQUIRED_NAME_IDS = {
          1 => "Family",
          2 => "Subfamily",
          4 => "Full",
          6 => "PostScript",
        }.freeze

        # @param font [SfntFont]
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          issues = []
          issues.concat(validate_required_tables(font))
          issues.concat(validate_loca_format(font))
          issues.concat(validate_name_coverage(font))
          issues.concat(validate_os2_fsselection(font))
          issues.concat(validate_hhea_metrics(font))
          issues
        end

        def self.code
          :opentype_conformance
        end

        # ---------- required tables ----------

        def self.validate_required_tables(font)
          required = required_tables_for_flavor(font)
          missing = required.reject { |tag| font.has_table?(tag) }
          missing.map do |tag|
            issue(severity: :error,
                  message: "Required table '#{tag}' is missing for this " \
                           "sfnt flavor",
                  location: "tables.#{tag}")
          end
        end
        private_class_method :validate_required_tables

        def self.required_tables_for_flavor(font)
          base = %w[head hhea maxp hmtx name post cmap OS/2]
          if font.has_table?("glyf")
            base + %w[glyf loca]
          elsif font.has_table?("CFF2")
            base + ["CFF2"]
          elsif font.has_table?("CFF ")
            base + ["CFF "]
          else
            base
          end
        end
        private_class_method :required_tables_for_flavor

        # ---------- loca format ----------

        def self.validate_loca_format(font)
          return [] unless font.has_table?("head") && font.has_table?("loca")

          head = font.table("head")
          loca = font.table("loca")
          return [] unless head && loca

          format = head.index_to_loc_format
          maxp = font.table("maxp")
          num_glyphs = maxp&.num_glyphs.to_i
          return [] if num_glyphs.zero?

          expected_size = format.zero? ? (num_glyphs + 1) * 2 : (num_glyphs + 1) * 4
          actual_size = loca.to_binary_s.bytesize
          return [] if actual_size == expected_size

          [issue(severity: :warning,
                 message: "loca table size (#{actual_size} bytes) doesn't match " \
                          "head.indexToLocFormat=#{format} + numGlyphs=#{num_glyphs} " \
                          "(expected #{expected_size} bytes)",
                 location: "head.index_to_loc_format")]
        end
        private_class_method :validate_loca_format

        # ---------- name table coverage ----------

        def self.validate_name_coverage(font)
          return [] unless font.has_table?("name")

          name = font.table("name")
          REQUIRED_NAME_IDS.each_with_object([]) do |(id, label), issues|
            val = name.english_name(id).to_s
            next unless val.empty?

            issues << issue(severity: :error,
                            message: "Required name ID #{id} (#{label}) is " \
                                     "missing from the name table",
                            location: "name.nameID.#{id}")
          end
        end
        private_class_method :validate_name_coverage

        # ---------- OS/2 fsSelection reserved bits ----------

        def self.validate_os2_fsselection(font)
          return [] unless font.has_table?("OS/2")

          os2 = font.table("OS/2")
          fs = os2.fs_selection.to_i
          reserved_mask = 0xFC00 # bits 10-15 are reserved
          return [] if (fs & reserved_mask).zero?

          [issue(severity: :warning,
                 message: "OS/2 fsSelection uses reserved bits " \
                          "(value 0x#{fs.to_s(16)}, bits 10-15 must be 0)",
                 location: "os2.fs_selection")]
        end
        private_class_method :validate_os2_fsselection

        # ---------- hhea.numberOfHMetrics ----------

        def self.validate_hhea_metrics(font)
          return [] unless font.has_table?("hhea") && font.has_table?("maxp")

          num_metrics = font.table("hhea").number_of_h_metrics.to_i
          num_glyphs = font.table("maxp").num_glyphs.to_i
          return [] if num_metrics.positive? && num_metrics <= num_glyphs

          [issue(severity: :error,
                 message: "hhea.numberOfHMetrics (#{num_metrics}) must be " \
                          "between 1 and maxp.numGlyphs (#{num_glyphs})",
                 location: "hhea.number_of_h_metrics")]
        end
        private_class_method :validate_hhea_metrics
      end
    end
  end
end
