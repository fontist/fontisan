# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates the 'name' table per the OpenType spec.
      #
      # Covers: required nameIDs, PostScript name character validity,
      # version string format. Glyph-name rules are in GlyphNameCheck.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/name
      class NameTableCheck < Check
        REQUIRED_NAME_IDS = {
          1 => "Family",
          2 => "Subfamily",
          4 => "Full",
          6 => "PostScript",
        }.freeze
        PS_NAME_PATTERN = /\A[A-Za-z][A-Za-z0-9._-]*\z/

        def self.call(font)
          return [] unless font.has_table?("name")

          name = font.table("name")
          issues = []
          issues.concat(validate_required_ids(name))
          issues.concat(validate_ps_name(name))
          issues.concat(validate_version_string(name))
          issues
        end

        def self.code
          :ot_name
        end

        def self.validate_required_ids(name)
          REQUIRED_NAME_IDS.each_with_object([]) do |(id, label), issues|
            val = name.english_name(id).to_s
            next unless val.empty?

            issues << issue(severity: :error,
                            message: "Required name ID #{id} (#{label}) is " \
                                     "missing from the name table",
                            location: "name.nameID.#{id}")
          end
        end
        private_class_method :validate_required_ids

        def self.validate_ps_name(name)
          ps = name.english_name(6).to_s
          return [] if ps.empty? || ps.match?(PS_NAME_PATTERN)

          [issue(severity: :warning,
                 message: "PostScript name '#{ps}' contains characters outside " \
                          "the OT spec grammar (must start with a letter, then " \
                          "A–Z a–z 0–9 . - _)",
                 location: "name.nameID.6")]
        end
        private_class_method :validate_ps_name

        def self.validate_version_string(name)
          ver = name.english_name(5).to_s
          return [] if ver.empty?

          unless ver.match?(/\AVersion\s/i)
            return [issue(severity: :info,
                          message: "name ID 5 (version) is '#{ver}' but should " \
                                   "start with 'Version ' per OT spec convention",
                          location: "name.nameID.5")]
          end

          []
        end
        private_class_method :validate_version_string
      end
    end
  end
end
