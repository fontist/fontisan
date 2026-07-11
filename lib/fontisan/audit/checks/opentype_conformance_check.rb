# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Foundational cross-table OpenType spec conformance checks.
      # Per-table rules live in their own check modules
      # ({HeadCheck}, {HheaCheck}, {Os2Check}, {NameTableCheck},
      # {PostCheck}, {KernCheck}) to keep each concern MECE.
      #
      # This check owns the rules that span multiple tables:
      #
      #   - Required tables for each sfnt flavor (TTF vs CFF vs variable)
      #   - head.indexToLocFormat consistency with loca table byte size
      #   - hhea.numberOfHMetrics must be ≤ maxp.numGlyphs
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/otff
      class OpenTypeConformanceCheck < Check
        # @param font [SfntFont]
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          issues = []
          issues.concat(validate_required_tables(font))
          issues.concat(validate_loca_format(font))
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
