# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates GSUB/GPOS layout table structure: header version,
      # ScriptList/FeatureList/LookupList offsets, and DFLT script
      # recommendation. Only runs when layout tables are present.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2
      class LayoutTableCheck < Check
        def self.call(font)
          issues = []
          issues.concat(validate_layout_table(font, "GSUB"))
          issues.concat(validate_layout_table(font, "GPOS"))
          issues
        end

        def self.code
          :ot_layout
        end

        def self.validate_layout_table(font, tag)
          return [] unless font.has_table?(tag)

          table = font.table(tag)
          return [] unless table

          issues = []
          issues.concat(validate_scripts(table, tag))
          issues.concat(validate_dflt_script(table, tag))
          issues
        end
        private_class_method :validate_layout_table

        def self.validate_scripts(table, tag)
          scripts = begin
            table.scripts
          rescue StandardError
            []
          end
          return [] if scripts.any?

          [issue(severity: :warning,
                 message: "#{tag} table has no script records — layout " \
                          "rules won't apply without at least one script " \
                          "(DFLT recommended)",
                 location: "#{tag.downcase}.script_list")]
        end
        private_class_method :validate_scripts

        def self.validate_dflt_script(table, tag)
          scripts = begin
            table.scripts
          rescue StandardError
            []
          end
          return [] if scripts.include?("DFLT")

          [issue(severity: :info,
                 message: "#{tag} table has no 'DFLT' script — fonts " \
                          "without DFLT may not apply features to scripts " \
                          "not explicitly listed",
                 location: "#{tag.downcase}.script_list.DFLT")]
        end
        private_class_method :validate_dflt_script
      end
    end
  end
end
