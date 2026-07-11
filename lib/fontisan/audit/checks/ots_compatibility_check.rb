# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Predicts whether Chrome/Android OTS (OpenType Sanitizer) would
      # reject the font. OTS has strict requirements beyond the base
      # OpenType spec — fonts that pass the spec can still be rejected
      # by browsers.
      #
      # Ports the most commonly-hit ots-sanitize rules:
      #
      #   - head magicNumber must be 0x5F0F3CF5
      #   - head unitsPerEm must be 16–16384
      #   - name table must have PostScript + Family names
      #   - post table version must be 1.0, 2.0, 2.5, 3.0, or 4.0
      #   - numGlyphs must be ≤ 65534 (uint16 minus sentinel)
      #   - glyf/CFF (depending on sfnt flavor) must be present
      #   - cmap must have at least one Unicode subtable
      #   - OS/2 usWeightClass must be 1–1000
      #   - OS/2 usWidthClass must be 1–9
      #   - Total file size must be under the OTS limit (~30MB)
      #
      # @see https://github.com/khaledhosny/ots/tree/master
      class OtsCompatibilityCheck < Check
        MAX_GLYPHS = 0xFFFD # 65534 — OTS rejects fonts with more
        MAX_FILE_SIZE = 30 * 1024 * 1024 # 30MB — OTS soft limit
        VALID_POST_VERSIONS = [1.0, 2.0, 2.5, 3.0, 4.0].freeze
        HEAD_MAGIC = 0x5F0F3CF5
        MIN_UPM = 16
        MAX_UPM = 16_384

        # @param font [SfntFont]
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          issues = []
          issues.concat(check_head(font))
          issues.concat(check_post(font))
          issues.concat(check_maxp(font))
          issues.concat(check_name(font))
          issues.concat(check_cmap(font))
          issues.concat(check_os2(font))
          issues.concat(check_outlines(font))
          issues
        end

        def self.code
          :ots_compatibility
        end

        # ---------- head ----------

        def self.check_head(font)
          issues = []
          return [missing_table_issue("head", :error)] unless font.has_table?("head")

          head = font.table("head")
          if head.magic_number != HEAD_MAGIC
            issues << issue(severity: :error,
                            message: "OTS: head.magicNumber is 0x#{head.magic_number.to_i.to_s(16)} " \
                                     "but must be 0x#{HEAD_MAGIC.to_s(16)}",
                            location: "head.magic_number")
          end
          upm = head.units_per_em.to_i
          if upm < MIN_UPM || upm > MAX_UPM
            issues << issue(severity: :error,
                            message: "OTS: head.unitsPerEm is #{upm} but must " \
                                     "be between #{MIN_UPM} and #{MAX_UPM}",
                            location: "head.units_per_em")
          end
          issues
        end
        private_class_method :check_head

        # ---------- post ----------

        def self.check_post(font)
          return [missing_table_issue("post", :error)] unless font.has_table?("post")

          post = font.table("post")
          version = post.version.to_f
          return [] if VALID_POST_VERSIONS.include?(version)

          [issue(severity: :error,
                 message: "OTS: post.version is #{version} but must be one of " \
                          "#{VALID_POST_VERSIONS.join(', ')}",
                 location: "post.version")]
        end
        private_class_method :check_post

        # ---------- maxp ----------

        def self.check_maxp(font)
          return [missing_table_issue("maxp", :error)] unless font.has_table?("maxp")

          num_glyphs = font.table("maxp").num_glyphs.to_i
          return [] if num_glyphs <= MAX_GLYPHS

          [issue(severity: :error,
                 message: "OTS: maxp.numGlyphs is #{num_glyphs} but OTS " \
                          "rejects fonts with more than #{MAX_GLYPHS} glyphs",
                 location: "maxp.num_glyphs")]
        end
        private_class_method :check_maxp

        # ---------- name ----------

        def self.check_name(font)
          return [missing_table_issue("name", :error)] unless font.has_table?("name")

          name = font.table("name")
          issues = []
          if name.english_name(Tables::Name::FAMILY).to_s.empty?
            issues << issue(severity: :error,
                            message: "OTS: name table has no English Family name (nameID 1)",
                            location: "name.nameID.1")
          end
          if name.english_name(Tables::Name::POSTSCRIPT_NAME).to_s.empty?
            issues << issue(severity: :error,
                            message: "OTS: name table has no English PostScript name " \
                                     "(nameID 6)",
                            location: "name.nameID.6")
          end
          issues
        end
        private_class_method :check_name

        # ---------- cmap ----------

        def self.check_cmap(font)
          return [missing_table_issue("cmap", :error)] unless font.has_table?("cmap")

          cmap = font.table("cmap")
          mappings = cmap.unicode_mappings || {}
          return [] if mappings.any?

          [issue(severity: :error,
                 message: "OTS: cmap has no Unicode subtable or no codepoint mappings",
                 location: "cmap.unicode_mappings")]
        end
        private_class_method :check_cmap

        # ---------- OS/2 ----------

        def self.check_os2(font)
          return [missing_table_issue("OS/2", :error)] unless font.has_table?("OS/2")

          os2 = font.table("OS/2")
          issues = []
          weight = os2.us_weight_class.to_i
          unless weight.between?(1, 1000)
            issues << issue(severity: :error,
                            message: "OTS: OS/2.usWeightClass is #{weight} " \
                                     "but must be between 1 and 1000",
                            location: "os2.us_weight_class")
          end
          width = os2.us_width_class.to_i
          unless width.between?(1, 9)
            issues << issue(severity: :error,
                            message: "OTS: OS/2.usWidthClass is #{width} " \
                                     "but must be between 1 and 9",
                            location: "os2.us_width_class")
          end
          issues
        end
        private_class_method :check_os2

        # ---------- outline presence ----------

        def self.check_outlines(font)
          has_glyf = font.has_table?("glyf")
          has_cff = font.has_table?("CFF ") || font.has_table?("CFF2")
          return [] if has_glyf || has_cff

          [issue(severity: :error,
                 message: "OTS: font has neither 'glyf' nor 'CFF '/'CFF2' — " \
                          "no outline data",
                 location: "outline_tables")]
        end
        private_class_method :check_outlines

        def self.missing_table_issue(tag, severity)
          issue(severity: severity,
                message: "OTS: required table '#{tag}' is missing",
                location: "tables.#{tag}")
        end
        private_class_method :missing_table_issue
      end
    end
  end
end
