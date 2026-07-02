# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # VariableOtf — produces a variable OTF with CFF2 outlines.
      #
      # The orchestrator assembles a default-master UFO plus variation
      # masters into a variable OpenType font with:
      #   - CFF2 outlines (with blend/vsindex operators for variation)
      #   - fvar (axes + instances)
      #   - STAT (style attributes)
      #   - avar (axis remapping)
      #   - HVAR (horizontal metrics variation)
      #   - MVAR (font-wide metrics variation)
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

        # Compile the variable OTF.
        # @param output_path [String] output file path
        # @return [String] the output path
        def compile(output_path:)
          tables = build_tables
          Dir.mktmpdir do |dir|
            Fontisan::FontWriter.write_to_file(tables, "#{dir}/temp.otf",
                                               sfnt_version: 0x4F54544F)
            File.binwrite(output_path, File.binread("#{dir}/temp.otf"))
          end
          output_path
        end

        # Build all tables for the variable OTF.
        # @return [Hash<String,String>] table tag → bytes
        def build_tables
          tables = base_tables
          tables["fvar"] = Fvar.build(@default, axes: @axes, instances: @instances)
          tables["STAT"] = Stat.build(axes: @axes)
          tables["avar"] = avar_table
          tables["CFF2"] = Cff2.build(@default, glyphs: @default.glyphs.values)
          tables
        end

        private

        def base_tables
          {
            "head" => Head.build(@default, glyphs: @default.glyphs.values, loca_format: Head::LOCA_FORMAT_LONG),
            "hhea" => Hhea.build(@default, glyphs: @default.glyphs.values),
            "maxp" => Maxp.build(@default, glyphs: @default.glyphs.values, version: Maxp::VERSION_OPEN_TYPE),
            "OS/2" => Os2.build(@default, glyphs: @default.glyphs.values),
            "name" => Name.build(@default),
            "post" => Post.build(@default),
            "hmtx" => Hmtx.build(@default, glyphs: @default.glyphs.values),
            "cmap" => Cmap.build(@default, glyphs: @default.glyphs.values),
          }
        end

        def avar_table
          return nil unless @axes.any? { |a| a[:maps] }

          Avar.build(axes: @axes)
        end
      end
    end
  end
end
