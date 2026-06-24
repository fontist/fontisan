# frozen_string_literal: true

module Fontisan
  module Audit
    module Extractors
      # Coverage fields: how many codepoints and glyphs the font ships,
      # plus the raw codepoint list (unless suppressed).
      #
      # Returned fields:
      #   total_codepoints, total_glyphs, cmap_subtables, codepoints
      class Coverage < Base
        def extract(context)
          font = context.font
          {
            total_codepoints: context.codepoints.length,
            total_glyphs: total_glyphs(font),
            cmap_subtables: cmap_subtable_formats(font),
            codepoints: codepoints_for_report(context),
          }
        end

        private

        def total_glyphs(font)
          return nil unless font.has_table?(Constants::MAXP_TAG)

          font.table(Constants::MAXP_TAG).num_glyphs
        end

        def cmap_subtable_formats(font)
          return [] unless font.has_table?(Constants::CMAP_TAG)

          font.table(Constants::CMAP_TAG).subtable_formats
        end

        def codepoints_for_report(context)
          return [] if context.no_codepoints?

          context.codepoints.map { |cp| format("U+%<cp>04X", cp: cp) }
        end
      end
    end
  end
end
