# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # UFO → OTF (CFF2). Uses CFF2 outlines instead of CFF1.
      #
      # CFF2 uses the same OTTO sfnt signature as CFF1. The difference
      # is the table tag: `CFF2` (vs `CFF ` for CFF1). CFF2 enables
      # variable font support and improved subroutinization.
      #
      # Note: CFF2 does NOT bypass the 65,535 glyph cap. The maxp
      # table's numGlyphs is uint16 in all OpenType versions, and the
      # CFF2 CharStrings INDEX count must match it. For > 65,535
      # glyphs, use TTC splitting.
      class Otf2Compiler < BaseCompiler
        SFNT_VERSION = SFNT_VERSION_OPEN_TYPE

        def build_outline_tables
          {
            "CFF2" => Cff2.build(font, glyphs: font.glyphs.values),
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
            "CFF2" => Cff2.build(font, glyphs: glyphs),
          }

          write(tables, output_path)
          output_path
        end
      end
    end
  end
end
