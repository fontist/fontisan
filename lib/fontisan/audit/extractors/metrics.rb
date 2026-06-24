# frozen_string_literal: true

module Fontisan
  module Audit
    module Extractors
      # Layout-critical metrics consolidated from head, hhea, OS/2, post.
      #
      # Returned fields:
      #   metrics: Models::Audit::Metrics instance, or nil for Type 1
      #
      # All table reads are nil-safe; tables may be absent in stripped
      # WOFF builds or legacy formats.
      class Metrics < Base
        def extract(context)
          font = context.font
          return { metrics: nil } unless sfnt?(font)

          { metrics: Models::Audit::Metrics.new(**gather(font)) }
        end

        private

        def sfnt?(font)
          font.is_a?(SfntFont)
        end

        def gather(font)
          {}.tap do |h|
            h.merge!(head_fields(font))
            h.merge!(hhea_fields(font))
            h.merge!(os2_fields(font))
            h.merge!(post_fields(font))
          end
        end

        def head_fields(font)
          head = table(font, Constants::HEAD_TAG)
          return {} unless head

          {
            units_per_em: head.units_per_em&.to_i,
            bbox_x_min: head.x_min&.to_i,
            bbox_y_min: head.y_min&.to_i,
            bbox_x_max: head.x_max&.to_i,
            bbox_y_max: head.y_max&.to_i,
          }
        end

        def hhea_fields(font)
          hhea = table(font, Constants::HHEA_TAG)
          return {} unless hhea

          {
            hhea_ascent: hhea.ascent&.to_i,
            hhea_descent: hhea.descent&.to_i,
            hhea_line_gap: hhea.line_gap&.to_i,
          }
        end

        def os2_fields(font)
          os2 = table(font, Constants::OS2_TAG)
          return {} unless os2

          {
            typo_ascender: os2.s_typo_ascender&.to_i,
            typo_descender: os2.s_typo_descender&.to_i,
            typo_line_gap: os2.s_typo_line_gap&.to_i,
            win_ascent: os2.us_win_ascent&.to_i,
            win_descent: os2.us_win_descent&.to_i,
            x_height: os2.sx_height&.to_i,
            cap_height: os2.s_cap_height&.to_i,
            subscript_x_size: os2.y_subscript_x_size&.to_i,
            subscript_y_size: os2.y_subscript_y_size&.to_i,
            subscript_x_offset: os2.y_subscript_x_offset&.to_i,
            subscript_y_offset: os2.y_subscript_y_offset&.to_i,
            superscript_x_size: os2.y_superscript_x_size&.to_i,
            superscript_y_size: os2.y_superscript_y_size&.to_i,
            superscript_x_offset: os2.y_superscript_x_offset&.to_i,
            superscript_y_offset: os2.y_superscript_y_offset&.to_i,
            strikeout_size: os2.y_strikeout_size&.to_i,
            strikeout_position: os2.y_strikeout_position&.to_i,
          }
        end

        def post_fields(font)
          post = table(font, Constants::POST_TAG)
          return {} unless post

          {
            underline_position: post.underline_position&.to_f,
            underline_thickness: post.underline_thickness&.to_f,
          }
        end

        def table(font, tag)
          return nil unless font.has_table?(tag)

          font.table(tag)
        end
      end
    end
  end
end
