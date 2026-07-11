# frozen_string_literal: true

require "tmpdir"

module Fontisan
  module Ufo
    module Compile
      # VariableOtf — produces a variable OTF with CFF2 outlines.
      #
      # The orchestrator assembles a default-master UFO plus variation
      # masters into a variable OpenType font with:
      #   - CFF2 outlines with blend operators for each varying coordinate
      #   - ItemVariationStore embedded in the CFF2 table (regions only;
      #     deltas live in charstring blend operands)
      #   - fvar (axes + instances)
      #   - STAT (style attributes)
      #   - avar (axis remapping, when maps are provided)
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cff2
      class VariableOtf
        # @param default_font [Fontisan::Ufo::Font] the default master
        # @param master_fonts [Array<Fontisan::Ufo::Font>] variation masters
        # @param axes [Array<Hash>] fvar axes (tag, min, default, max, name_id)
        # @param instances [Array<Hash>] named instances
        def initialize(default_font, master_fonts: [], axes: [], instances: [])
          @default = default_font
          @masters = master_fonts
          @axes = axes
          @instances = instances
        end

        # Compile the variable OTF directly to the output path.
        # @param output_path [String] output file path
        # @return [String] the output path
        def compile(output_path:)
          tables = build_tables
          Fontisan::FontWriter.write_to_file(
            tables.transform_values { |t| t.is_a?(String) ? t : t.to_binary_s },
            output_path,
            sfnt_version: 0x4F54544F,
          )
          output_path
        end

        # Build all tables for the variable OTF.
        # @return [Hash<String,String>] table tag → bytes
        def build_tables
          glyphs = @default.glyphs.values

          tables = {
            "head" => Head.build(@default, glyphs: glyphs, loca_format: Head::LOCA_FORMAT_LONG),
            "hhea" => Hhea.build(@default, glyphs: glyphs),
            "maxp" => Maxp.build(@default, glyphs: glyphs, version: Maxp::VERSION_OPEN_TYPE),
            "OS/2" => Os2.build(@default, glyphs: glyphs),
            "name" => Name.build(@default),
            "post" => Post.build(@default),
            "hmtx" => Hmtx.build(@default, glyphs: glyphs),
            "cmap" => Cmap.build(@default, glyphs: glyphs),
            "CFF2" => build_cff2(glyphs),
            "fvar" => Fvar.build(@default, axes: @axes, instances: @instances),
            "STAT" => Stat.build(axes: @axes),
          }

          avar_bytes = Avar.build(axes: @axes)
          tables["avar"] = avar_bytes if avar_bytes

          tables
        end

        private

        # Build the CFF2 table. When masters are supplied, variable
        # charstrings with blend operators are emitted; otherwise a static
        # CFF2 table is produced.
        def build_cff2(glyphs)
          masters = @masters.map { |mf| { font: mf, axes: @axes } }
          Cff2.build(@default, glyphs: glyphs,
                     masters: masters.any? ? masters : nil,
                     axis_count: @axes.size)
        end
      end
    end
  end
end
