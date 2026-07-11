# frozen_string_literal: true

module Fontisan
  module Audit
    # Central registry of audit checks. A profile is a named subset of
    # checks (e.g. +:ots+, +:structural+). The +:default+ profile runs
    # every registered check.
    #
    # Profiles let callers opt into specific validation axes without
    # running everything — e.g. +fontisan audit font.ttf --validate ots+
    # runs only the OTS compatibility check.
    #
    # @example Run all checks
    #   CheckRegistry.for(:default)  # => [TableDirectoryCheck, ...]
    #
    # @example Run a specific profile
    #   CheckRegistry.for(:ots)      # => [OtsCompatibilityCheck]
    class CheckRegistry
      # Per-table OT conformance checks (axis 14 — full OT spec coverage).
      OT_TABLE_CHECKS = %i[ot_head ot_hhea ot_maxp ot_os2 ot_name ot_post
                           ot_kern ot_cff ot_glyf ot_layout].freeze

      PROFILES = {
        default: %i[table_directory glyph_names cmap ots_compatibility
                    collection_integrity variable_font hinting woff2_validation
                    format_round_trip opentype_conformance naming_consistency
                    ot_head ot_hhea ot_maxp ot_os2 ot_name ot_post ot_kern
                    ot_cff ot_glyf ot_layout],
        structural: %i[table_directory collection_integrity opentype_conformance],
        ots: %i[ots_compatibility],
        layout: %i[glyph_names cmap ot_layout naming_consistency],
        variable: %i[variable_font],
        hinting: %i[hinting],
        web: %i[ots_compatibility woff2_validation],
        spec: %i[opentype_conformance ot_head ot_hhea ot_maxp ot_os2
                 ot_name ot_post ot_kern ot_cff ot_glyf ot_layout
                 naming_consistency],
        per_table: OT_TABLE_CHECKS,
      }.freeze

      # @param profile [Symbol]
      # @return [Array<Class>] check classes for the profile
      def self.for(profile)
        codes = PROFILES[profile] || PROFILES[:default]
        codes.filter_map { |code| check_for(code) }
      end

      # @param code [Symbol]
      # @return [Class, nil] the check class
      def self.check_for(code)
        case code
        when :table_directory then Checks::TableDirectoryCheck
        when :glyph_names then Checks::GlyphNameCheck
        when :cmap then Checks::CmapCheck
        when :ots_compatibility then Checks::OtsCompatibilityCheck
        when :collection_integrity then Checks::CollectionIntegrityCheck
        when :variable_font then Checks::VariableFontCheck
        when :hinting then Checks::HintingCheck
        when :woff2_validation then Checks::Woff2ValidationCheck
        when :format_round_trip then Checks::FormatRoundTripCheck
        when :opentype_conformance then Checks::OpenTypeConformanceCheck
        when :naming_consistency then Checks::NamingConsistencyCheck
        when :ot_head then Checks::HeadCheck
        when :ot_hhea then Checks::HheaCheck
        when :ot_maxp then Checks::MaxpCheck
        when :ot_os2 then Checks::Os2Check
        when :ot_name then Checks::NameTableCheck
        when :ot_post then Checks::PostCheck
        when :ot_kern then Checks::KernCheck
        when :ot_cff then Checks::CffTableCheck
        when :ot_glyf then Checks::GlyfTableCheck
        when :ot_layout then Checks::LayoutTableCheck
        end
      end
    end
  end
end
