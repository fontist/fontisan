# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # UFO → OTF. Uses CFF outlines (instead of TrueType glyf/loca).
      # Maxp version 0.5 (no TrueType metrics); sfnt version OTTO.
      # The CFF table is built by Compile::Cff which encodes real
      # Type 2 charstrings from UFO contours via CharStringBuilder.
      class OtfCompiler < BaseCompiler
        SFNT_VERSION = SFNT_VERSION_OPEN_TYPE

        def compile(output_path:)
          glyphs = glyphs_with_notdef

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
