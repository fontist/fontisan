# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # UFO → TTF. Same tables as the OTF compiler plus glyf + loca
      # (no CFF). Maxp version 1.0 carries the TrueType metrics.
      #
      # Before glyf encoding, the TTF-required filters run:
      #   - cubic_to_quadratic (TTF only supports quadratic Beziers)
      #   - reverse_contour_direction (TTF winding convention)
      class TtfCompiler < BaseCompiler
        SFNT_VERSION = SFNT_VERSION_TRUE_TYPE

        # @return [Hash<String, #to_binary_s>] all TTF tables, not yet written
        def build_tables
          glyphs = font.glyphs.values

          # Deep-clone glyphs so filters don't mutate the source UFO.
          filtered = clone_glyphs(glyphs)
          Filters.apply(Filters::TTF_REQUIRED, filtered)

          glyf_loca = GlyfLoca.build(font, glyphs: filtered)
          loca_format = glyf_loca.delete(:loca_format)

          {
            "head" => Head.build(font, glyphs: filtered,
                                       loca_format: loca_format || Head::LOCA_FORMAT_LONG),
            "hhea" => Hhea.build(font, glyphs: filtered),
            "maxp" => Maxp.build(font, glyphs: filtered,
                                       version: Maxp::VERSION_TRUE_TYPE),
            "OS/2" => Os2.build(font, glyphs: filtered),
            "name" => Name.build(font),
            "post" => Post.build(font),
            "hmtx" => Hmtx.build(font, glyphs: filtered),
            "cmap" => Cmap.build(font, glyphs: filtered),
            "glyf" => glyf_loca["glyf"],
            "loca" => glyf_loca["loca"],
          }
        end

        def compile(output_path:)
          write(build_tables, output_path)
          output_path
        end

        private

        def clone_glyphs(glyphs)
          glyphs.map { |g| clone_glyph(g) }
        end

        def clone_glyph(original)
          copy = Ufo::Glyph.new(name: original.name)
          copy.width = original.width
          copy.height = original.height
          original.unicodes.each { |cp| copy.add_unicode(cp) }
          original.contours.each { |c| copy.add_contour(clone_contour(c)) }
          original.components.each { |c| copy.add_component(c) }
          copy
        end

        def clone_contour(original)
          points = original.points.map do |p|
            Ufo::Point.new(x: p.x, y: p.y, type: p.type, smooth: p.smooth)
          end
          Ufo::Contour.new(points)
        end
      end
    end
  end
end
