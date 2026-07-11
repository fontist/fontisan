# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates the 'kern' table if present. The kern table is
      # deprecated by the OpenType spec — GPOS is the replacement.
      # Many legacy fonts still ship kern; this check warns about
      # deprecation and validates basic structure.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/kern
      class KernCheck < Check
        def self.call(font)
          return [] unless font.has_table?("kern")

          issues = [deprecation_warning]
          issues.concat(validate_gpos_presence(font))
          issues
        end

        def self.code
          :ot_kern
        end

        def self.deprecation_warning
          issue(severity: :warning,
                message: "kern table is present but deprecated by the " \
                         "OpenType spec — use GPOS instead. Some modern " \
                         "renderers (HarfBuzz, Core Text) ignore kern",
                location: "tables.kern")
        end
        private_class_method :deprecation_warning

        def self.validate_gpos_presence(font)
          return [] if font.has_table?("GPOS")

          [issue(severity: :warning,
                 message: "kern table present but no GPOS table — " \
                          "kerning data should be migrated to a GPOS " \
                          "'kern' feature for full renderer support",
                 location: "tables.GPOS")]
        end
        private_class_method :validate_gpos_presence
      end
    end
  end
end
