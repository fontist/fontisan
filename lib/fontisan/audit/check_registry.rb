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
      PROFILES = {
        default: %i[table_directory glyph_names cmap ots_compatibility
                    collection_integrity variable_font hinting woff2_validation
                    format_round_trip],
        structural: %i[table_directory collection_integrity],
        ots: %i[ots_compatibility],
        layout: %i[glyph_names cmap],
        variable: %i[variable_font],
        hinting: %i[hinting],
        web: %i[ots_compatibility woff2_validation],
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
        end
      end
    end
  end
end
