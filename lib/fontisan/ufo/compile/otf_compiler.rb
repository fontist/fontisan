# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # UFO → OTF. Uses CFF outlines (instead of TrueType glyf/loca).
      # Maxp version 0.5 (no TrueType metrics); sfnt version OTTO.
      #
      # TODO.full/10: this currently emits a placeholder CFF table
      # that satisfies the OTTO signature but does NOT yet encode
      # real charstrings. Full CFF construction lands when TODO 10
      # ships.
      class OtfCompiler < BaseCompiler
        SFNT_VERSION = SFNT_VERSION_OPEN_TYPE

        def build_outline_tables
          {
            "CFF " => Cff.build(font, glyphs: font.glyphs.values),
          }
        end

        def compile(output_path:)
          glyphs = font.glyphs.values

          tables = {
            "head" => Head.build(font, glyphs: glyphs, loca_format: Head::LOCA_FORMAT_LONG),
            "hhea" => Hhea.build(font, glyphs: glyphs),
            "maxp" => Maxp.build(font, glyphs: glyphs, version: Maxp::VERSION_OPEN_TYPE),
            "OS/2" => Os2.build(font, glyphs: glyphs),
            "name" => Name.build(font),
            "post" => Post.build(font),
            "hmtx" => Hmtx.build(font, glyphs: glyphs),
            "cmap" => Cmap.build(font, glyphs: glyphs),
            "CFF " => Cff.build(font, glyphs: glyphs),
          }

          write(tables, output_path)
          output_path
        end
      end
    end
  end
end
