# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates the 'OS/2' table per the OpenType spec.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/os2
      class Os2Check < Check
        FS_SELECTION_RESERVED = 0xFC00

        def self.call(font)
          return [] unless font.has_table?("OS/2")

          os2 = font.table("OS/2")
          issues = []
          issues.concat(validate_weight_class(os2))
          issues.concat(validate_width_class(os2))
          issues.concat(validate_fs_selection(os2))
          issues.concat(validate_typo_metrics(os2))
          issues.concat(validate_win_metrics(os2))
          issues.concat(validate_panose(os2))
          issues
        end

        def self.code
          :ot_os2
        end

        def self.validate_weight_class(os2)
          w = os2.us_weight_class.to_i
          return [] if w.between?(1, 1000)

          [issue(severity: :error,
                 message: "OS/2.usWeightClass is #{w} but must be between " \
                          "1 and 1000",
                 location: "os2.us_weight_class")]
        end
        private_class_method :validate_weight_class

        def self.validate_width_class(os2)
          w = os2.us_width_class.to_i
          return [] if w.between?(1, 9)

          [issue(severity: :error,
                 message: "OS/2.usWidthClass is #{w} but must be between 1 " \
                          "and 9",
                 location: "os2.us_width_class")]
        end
        private_class_method :validate_width_class

        def self.validate_fs_selection(os2)
          fs = os2.fs_selection.to_i
          return [] if (fs & FS_SELECTION_RESERVED).zero?

          [issue(severity: :warning,
                 message: "OS/2.fsSelection uses reserved bits " \
                          "(0x#{fs.to_s(16)}, bits 10-15 must be 0)",
                 location: "os2.fs_selection")]
        end
        private_class_method :validate_fs_selection

        def self.validate_typo_metrics(os2)
          issues = []
          asc = os2.s_typo_ascender.to_i
          desc = os2.s_typo_descender.to_i
          if asc <= 0
            issues << issue(severity: :warning,
                            message: "OS/2.sTypoAscender is #{asc} but should " \
                                     "be positive",
                            location: "os2.s_typo_ascender")
          end
          if desc.positive?
            issues << issue(severity: :warning,
                            message: "OS/2.sTypoDescender is #{desc} but should " \
                                     "be ≤ 0",
                            location: "os2.s_typo_descender")
          end
          issues
        end
        private_class_method :validate_typo_metrics

        def self.validate_win_metrics(os2)
          issues = []
          if os2.us_win_ascent.to_i <= 0
            issues << issue(severity: :warning,
                            message: "OS/2.usWinAscent is #{os2.us_win_ascent} " \
                                     "but should be positive",
                            location: "os2.us_win_ascent")
          end
          if os2.us_win_descent.to_i <= 0
            issues << issue(severity: :warning,
                            message: "OS/2.usWinDescent is #{os2.us_win_descent} " \
                                     "but should be positive",
                            location: "os2.us_win_descent")
          end
          issues
        end
        private_class_method :validate_win_metrics

        def self.validate_panose(os2)
          panose = os2.panose
          return [] unless panose

          all_zero = panose.to_a.all?(&:zero?)
          return [] unless all_zero

          [issue(severity: :info,
                 message: "OS/2.panose is all zeros — PANOSE classification " \
                          "helps font matching in some applications",
                 location: "os2.panose")]
        end
        private_class_method :validate_panose
      end
    end
  end
end
