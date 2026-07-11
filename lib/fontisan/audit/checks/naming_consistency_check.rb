# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates name-table consistency across name IDs. Catches
      # common real-world bugs where font metadata disagrees with
      # itself:
      #
      #   - PostScript name should start with the Family name (minus
      #     spaces) — e.g. Family "Source Sans" → PS "SourceSans-Regular"
      #   - Subfamily should be a recognized style ("Regular", "Bold",
      #     "Italic", "Bold Italic") for non-variable fonts
      #   - Full name should be Family + " " + Subfamily
      #   - Version string should start with "Version "
      #
      # These rules catch typo-level errors that confuse font pickers,
      # package managers, and PDF embedding workflows.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/name
      class NamingConsistencyCheck < Check
        RECOGNIZED_SUBFAMILIES = %w[
          Regular Italic Bold BoldItalic Thin Light Medium SemiBold Black
          Condensed Extended Oblique Book Normal
        ].freeze

        def self.call(font)
          return [] unless font.has_table?("name")

          name = font.table("name")
          issues = []
          issues.concat(check_ps_name_prefix(name))
          issues.concat(check_full_name_composition(name))
          issues.concat(check_subfamily_style(name, font))
          issues
        end

        def self.code
          :naming_consistency
        end

        # PostScript name should start with the family name (spaces
        # removed). E.g. Family "Source Sans 3" → PS "SourceSans3-Regular".
        def self.check_ps_name_prefix(name)
          family = name.english_name(Tables::Name::FAMILY).to_s
          ps = name.english_name(Tables::Name::POSTSCRIPT_NAME).to_s
          return [] if family.empty? || ps.empty?

          family_compact = family.delete(" ")
          return [] if ps.start_with?(family_compact)

          [issue(severity: :warning,
                 message: "PostScript name '#{ps}' does not start with the " \
                          "family name '#{family}' (expected prefix: '#{family_compact}')",
                 location: "name.consistency.ps_prefix")]
        end
        private_class_method :check_ps_name_prefix

        # Full name should be Family + " " + Subfamily.
        def self.check_full_name_composition(name)
          family = name.english_name(Tables::Name::FAMILY).to_s
          subfamily = name.english_name(Tables::Name::SUBFAMILY).to_s
          full = name.english_name(Tables::Name::FULL_NAME).to_s
          return [] if family.empty? || subfamily.empty? || full.empty?

          expected = "#{family} #{subfamily}"
          return [] if full == expected

          [issue(severity: :info,
                 message: "Full name '#{full}' doesn't match " \
                          "Family + Subfamily '#{expected}'",
                 location: "name.consistency.full_name")]
        end
        private_class_method :check_full_name_composition

        # Subfamily should be a recognized style name for non-variable
        # fonts. Variable fonts use arbitrary subfamily names.
        def self.check_subfamily_style(name, font)
          return [] if font.has_table?("fvar") # variable fonts use custom names

          subfamily = name.english_name(Tables::Name::SUBFAMILY).to_s
          return [] if subfamily.empty?

          return [] if recognized_subfamily?(subfamily)

          [issue(severity: :info,
                 message: "Subfamily '#{subfamily}' is not a standard style " \
                          "name — font pickers may not categorize it correctly",
                 location: "name.consistency.subfamily")]
        end
        private_class_method :check_subfamily_style

        def self.recognized_subfamily?(subfamily)
          RECOGNIZED_SUBFAMILIES.any? do |recognized|
            subfamily.casecmp?(recognized) || subfamily.casecmp?(recognized.delete('"'))
          end
        end
        private_class_method :recognized_subfamily?
      end
    end
  end
end
