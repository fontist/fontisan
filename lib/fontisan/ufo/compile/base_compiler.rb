# frozen_string_literal: true

require "fileutils"

module Fontisan
  module Ufo
    module Compile
      # Common orchestrator for TTF and OTF compilers.
      # Subclasses implement `#build_outline_tables` (returning the
      # format-specific table set: glyf+loca for TTF, CFF for OTF)
      # and `sfnt_version` (0x00010000 for TTF, 0x4F54544F for OTF).
      class BaseCompiler
        SFNT_VERSION_TRUE_TYPE = 0x00010000
        SFNT_VERSION_OPEN_TYPE = 0x4F54544F # "OTTO"

        attr_reader :font

        def initialize(font)
          @font = font
        end

        # @param output_path [String] where to write the binary font
        # @return [String] the path
        def compile(output_path:)
          tables = build_tables
          write(tables, output_path)
          output_path
        end

        # Format-specific extra tables. Override in subclasses.
        # @return [Hash<String, #to_binary_s, String>]
        def build_outline_tables
          {}
        end

        # @return [Integer] 0x00010000 (TTF) or 0x4F54544F (OTF)
        def sfnt_version
          self.class::SFNT_VERSION
        end

        private

        # All tables every OTF/TTF must have, plus optional feature
        # tables (GPOS for kerning) when the UFO source has kerning data.
        def build_tables
          glyphs = glyphs_with_notdef
          tables = {
            "head" => Head.build(font, glyphs: glyphs),
            "hhea" => Hhea.build(font, glyphs: glyphs),
            "maxp" => Maxp.build(font, glyphs: glyphs),
            "OS/2" => Os2.build(font, glyphs: glyphs),
            "name" => Name.build(font),
            "post" => Post.build(font, glyphs: glyphs),
            "hmtx" => Hmtx.build(font, glyphs: glyphs),
            "cmap" => Cmap.build(font, glyphs: glyphs),
          }

          # GPOS kern table (only when the UFO source has kerning pairs)
          gpos = Gpos.build(font, glyphs: glyphs)
          tables["GPOS"] = gpos if gpos

          tables.merge(build_outline_tables)
        end

        # OpenType requires GID 0 to be `.notdef`. Normalize the source
        # glyph list so that:
        #   - if `.notdef` is already at GID 0, the list is unchanged;
        #   - if `.notdef` exists elsewhere, it's moved to GID 0;
        #   - if no `.notdef` exists, an empty one is prepended.
        #
        # Without this, the alphabetically-first source glyph lands at
        # GID 0 and the cmap parser (which treats GID 0 as `.notdef` per
        # spec) silently drops it from the cmap.
        def glyphs_with_notdef
          source = font.glyphs.values
          return source if source.empty?

          existing = source.find { |g| g.name == ".notdef" }
          return source if existing == source.first

          rest = source - [existing]
          notdef = existing || Ufo::Glyph.notdef(units_per_em: default_units_per_em)
          [notdef, *rest]
        end

        def default_units_per_em
          font.info&.units_per_em&.to_i || Ufo::Glyph::DEFAULT_UNITS_PER_EM
        end

        def write(tables_hash, output_path)
          dir = File.dirname(output_path)
          FileUtils.mkpath(dir) unless dir == "."

          Fontisan::FontWriter.write_to_file(
            tables_hash.transform_values { |t| serialize_table(t) },
            output_path,
            sfnt_version: sfnt_version,
          )
        end

        # BinData records (Tables::*) respond to to_binary_s; raw
        # String values pass through. We branch on class identity
        # rather than `respond_to?` to keep the type system honest.
        def serialize_table(table)
          case table
          when String then table
          else table.to_binary_s
          end
        end
      end
    end
  end
end
