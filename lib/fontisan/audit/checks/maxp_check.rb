# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates the 'maxp' table per the OpenType spec.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/maxp
      class MaxpCheck < Check
        MAX_GLYPHS = 0xFFFF
        MAX_STACK_ELEMENTS = 1000

        def self.call(font)
          return [] unless font.has_table?("maxp")

          maxp = font.table("maxp")
          issues = []
          issues.concat(validate_version(maxp, font))
          issues.concat(validate_num_glyphs(maxp))
          issues.concat(validate_hint_capacity(maxp))
          issues
        end

        def self.code
          :ot_maxp
        end

        def self.validate_version(maxp, font)
          version_raw = maxp.version_raw
          is_truetype = font.has_table?("glyf")
          tt_version = 0x00010000 # 1.0 as Fixed 16.16
          cff_version = 0x00005000 # 0.5 as Fixed 16.16
          if is_truetype && version_raw != tt_version
            [issue(severity: :error,
                   message: "maxp.version is 0x#{version_raw.to_s(16)} but must " \
                            "be 1.0 (0x#{tt_version.to_s(16)}) for TrueType fonts",
                   location: "maxp.version")]
          elsif !is_truetype && version_raw != cff_version
            [issue(severity: :warning,
                   message: "maxp.version is 0x#{version_raw.to_s(16)} but " \
                            "should be 0.5 (0x#{cff_version.to_s(16)}) for " \
                            "CFF-based fonts",
                   location: "maxp.version")]
          else
            []
          end
        end
        private_class_method :validate_version

        def self.validate_num_glyphs(maxp)
          n = maxp.num_glyphs.to_i
          return [] if n.between?(1, MAX_GLYPHS)

          [issue(severity: :error,
                 message: "maxp.numGlyphs is #{n} but must be between 1 and " \
                          "#{MAX_GLYPHS}",
                 location: "maxp.num_glyphs")]
        end
        private_class_method :validate_num_glyphs

        def self.validate_hint_capacity(maxp)
          return [] unless maxp.version_1_0?

          issues = []
          zones = maxp.max_zones.to_i
          unless zones.between?(1, 2)
            issues << issue(severity: :warning,
                            message: "maxp.maxZones is #{zones} but must be 1 or 2 " \
                                     "per the OpenType spec",
                            location: "maxp.max_zones")
          end
          stack = maxp.max_stack_elements.to_i
          if stack > MAX_STACK_ELEMENTS
            issues << issue(severity: :warning,
                            message: "maxp.maxStackElements is #{stack} — " \
                                     "excessively large values waste interpreter memory",
                            location: "maxp.max_stack_elements")
          end
          issues
        end
        private_class_method :validate_hint_capacity
      end
    end
  end
end
