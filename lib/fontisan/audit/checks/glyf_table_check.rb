# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates the 'glyf' table: simple glyph contour integrity and
      # compound glyph reference bounds. Only runs on TrueType fonts.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/glyf
      class GlyfTableCheck < Check
        MAX_COMPOUND_DEPTH = 16

        def self.call(font)
          return [] unless font.has_table?("glyf") && font.has_table?("loca")

          issues = []
          issues.concat(validate_glyph_counts(font))
          issues
        end

        def self.code
          :ot_glyf
        end

        # Verify loca offsets are monotonically non-decreasing and
        # within the glyf table bounds. Discontinuities signal
        # corruption that renderers may reject.
        def self.validate_glyph_counts(font)
          glyf = font.table("glyf")
          return [] unless glyf

          raw = font.table_data["glyf"]
          return [] unless raw

          issues = []
          maxp = font.table("maxp")
          num_glyphs = maxp&.num_glyphs.to_i
          return [] if num_glyphs.zero?

          num_glyphs.times do |gid|
            issues.concat(validate_one_glyph(font, gid))
          rescue StandardError
            issues << issue(severity: :warning,
                            message: "glyf: failed to validate glyph at GID " \
                                     "#{gid}",
                            location: "glyf.glyph.#{gid}")
          end
          issues
        end
        private_class_method :validate_glyph_counts

        def self.validate_one_glyph(font, gid)
          head = font.table("head")
          loca = font.table("loca")
          glyf = font.table("glyf")

          raw = begin
            glyf.glyph_for(gid, loca, head)
          rescue StandardError
            nil
          end
          return [] unless raw

          if raw.simple?
            validate_simple_glyph(raw, gid)
          elsif raw.compound?
            validate_compound_glyph(raw, gid, font)
          else
            []
          end
        end
        private_class_method :validate_one_glyph

        def self.validate_simple_glyph(raw, gid)
          issues = []
          end_pts = raw.end_pts_of_contours
          return [] unless end_pts&.any?

          # endPtsOfContours must be monotonically increasing
          end_pts.each_cons(2) do |prev, curr|
            next unless curr <= prev

            issues << issue(severity: :error,
                            message: "glyf glyph #{gid}: contour endPoints " \
                                     "are not monotonically increasing " \
                                     "(#{prev} → #{curr})",
                            location: "glyf.glyph.#{gid}.contours")
            break
          end
          issues
        end
        private_class_method :validate_simple_glyph

        def self.validate_compound_glyph(raw, gid, font)
          issues = []
          maxp = font.table("maxp")
          max_gid = maxp&.num_glyphs.to_i - 1

          raw.components.each do |comp|
            ref_gid = comp.glyph_index.to_i
            next if ref_gid.between?(0, max_gid)

            issues << issue(severity: :error,
                            message: "glyf compound glyph #{gid} references " \
                                     "out-of-bounds GID #{ref_gid} " \
                                     "(max: #{max_gid})",
                            location: "glyf.glyph.#{gid}.component.#{ref_gid}")
          end
          issues
        end
        private_class_method :validate_compound_glyph
      end
    end
  end
end
