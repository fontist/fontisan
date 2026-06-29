# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # UFO → TTF. Same tables as the OTF compiler plus glyf + loca
      # (no CFF). Maxp version 1.0 carries the TrueType metrics.
      class TtfCompiler < BaseCompiler
        SFNT_VERSION = SFNT_VERSION_TRUE_TYPE

        def build_outline_tables
          result = GlyfLoca.build(font, glyphs: font.glyphs.values)
          loca_format = result.delete(:loca_format)

          # Head needs to know loca_format; rebuild Head with the right flag.
          @tables_with_loca_format = loca_format

          {
            "glyf" => result["glyf"],
            "loca" => result["loca"],
          }
        end

        # Override to inject the loca_format into Head before serialization.
        def compile(output_path:)
          glyphs = font.glyphs.values
          nil

          glyf_loca = GlyfLoca.build(font, glyphs: glyphs)
          loca_format = glyf_loca.delete(:loca_format)

          tables = {
            "head" => Head.build(font, glyphs: glyphs, loca_format: loca_format || Head::LOCA_FORMAT_LONG),
            "hhea" => Hhea.build(font, glyphs: glyphs),
            "maxp" => Maxp.build(font, glyphs: glyphs, version: Maxp::VERSION_TRUE_TYPE),
            "OS/2" => Os2.build(font, glyphs: glyphs),
            "name" => Name.build(font),
            "post" => Post.build(font),
            "hmtx" => Hmtx.build(font, glyphs: glyphs),
            "cmap" => Cmap.build(font, glyphs: glyphs),
            "glyf" => glyf_loca["glyf"],
            "loca" => glyf_loca["loca"],
          }

          write(tables, output_path)
          output_path
        end
      end
    end
  end
end
