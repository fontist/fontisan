# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates the 'head' table per the OpenType spec.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/head
      class HeadCheck < Check
        HEAD_MAGIC = 0x5F0F3CF5
        MIN_UPM = 16
        MAX_UPM = 16_384
        MAC_STYLE_DEFINED_BITS = 0x00FF
        MAC_STYLE_RESERVED_BITS = 0xFF00

        def self.call(font)
          return [] unless font.has_table?("head")

          head = font.table("head")
          issues = []
          issues.concat(validate_magic(head))
          issues.concat(validate_upm(head))
          issues.concat(validate_loc_format(head))
          issues.concat(validate_dates(head))
          issues.concat(validate_mac_style(head))
          issues
        end

        def self.code
          :ot_head
        end

        def self.validate_magic(head)
          return [] if head.magic_number == HEAD_MAGIC

          [issue(severity: :error,
                 message: "head.magicNumber is 0x#{head.magic_number.to_i.to_s(16)} " \
                          "but must be 0x#{HEAD_MAGIC.to_s(16)}",
                 location: "head.magic_number")]
        end
        private_class_method :validate_magic

        def self.validate_upm(head)
          upm = head.units_per_em.to_i
          return [] if upm.between?(MIN_UPM, MAX_UPM)

          [issue(severity: :error,
                 message: "head.unitsPerEm is #{upm} but must be between " \
                          "#{MIN_UPM} and #{MAX_UPM}",
                 location: "head.units_per_em")]
        end
        private_class_method :validate_upm

        def self.validate_loc_format(head)
          fmt = head.index_to_loc_format.to_i
          return [] if [0, 1].include?(fmt)

          [issue(severity: :error,
                 message: "head.indexToLocFormat is #{fmt} but must be 0 " \
                          "(short) or 1 (long)",
                 location: "head.index_to_loc_format")]
        end
        private_class_method :validate_loc_format

        def self.validate_dates(head)
          issues = []
          if head.created_raw.to_i.zero?
            issues << issue(severity: :info,
                            message: "head.created is 0 — creation date not set",
                            location: "head.created")
          end
          if head.modified_raw.to_i.zero?
            issues << issue(severity: :info,
                            message: "head.modified is 0 — modification date not set",
                            location: "head.modified")
          end
          issues
        end
        private_class_method :validate_dates

        def self.validate_mac_style(head)
          style = head.mac_style.to_i
          issues = []
          unless (style & MAC_STYLE_RESERVED_BITS).zero?
            issues << issue(severity: :warning,
                            message: "head.macStyle uses reserved bits " \
                                     "(0x#{style.to_s(16)}, bits 8-15 must be 0)",
                            location: "head.mac_style")
          end
          issues
        end
        private_class_method :validate_mac_style
      end
    end
  end
end
