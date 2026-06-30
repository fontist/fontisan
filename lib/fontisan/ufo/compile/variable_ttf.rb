# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Orchestrates compilation of a UFO source plus its variation
      # masters into a single variable TrueType font.
      #
      # Pipeline:
      #
      #   default UFO font
      #     │
      #     ├─ TtfCompiler tables (head, hhea, maxp, OS/2, name,
      #     │                     post, hmtx, cmap, glyf, loca)
      #     │
      #     ├─ fvar  (axes + named instances)
      #     ├─ gvar  (per-glyph point deltas across masters)
      #     ├─ HVAR  (advance-width deltas across masters)
      #     ├─ MVAR  (font-wide metric deltas across masters)
      #     ├─ avar  (per-axis non-linear maps; defaults to identity)
      #     └─ STAT  (style attributes for OS matching)
      #
      # Masters are supplied as an Array of Hashes, each with:
      #   - :font   — the master UFO::Font
      #   - :axes   — Hash<String, Float> mapping axis tag → region peak
      #
      class VariableTtf
        SFNT_VERSION = BaseCompiler::SFNT_VERSION_TRUE_TYPE

        # @param font [Fontisan::Ufo::Font] default master
        # @param axes [Array<Hash>] axis definitions (tag, min/default/max,
        #   optional name_id, ordering, maps)
        # @param masters [Array<Hash>] each master: { font:, axes: }
        # @param instances [Array<Hash>] named instances for fvar
        # @param stat_axis_values [Array<Hash>, nil] STAT axis value records
        # @param stat_elided_name_id [Integer, nil] STAT elided fallback name
        # @param default_metrics [Hash<Symbol, Integer>, nil] MVAR defaults
        # @param master_metrics [Array<Hash<Symbol, Integer>>, nil] MVAR per-master
        def initialize(font:, axes:, masters:, instances: nil,
                       stat_axis_values: nil, stat_elided_name_id: nil,
                       default_metrics: nil, master_metrics: nil)
          @font = font
          @axes = axes
          @masters = masters
          @instances = instances
          @stat_axis_values = stat_axis_values
          @stat_elided_name_id = stat_elided_name_id
          @default_metrics = default_metrics
          @master_metrics = master_metrics
        end

        # @param output_path [String]
        # @return [String] the output path
        def compile(output_path:)
          tables = base_tables.merge(variation_tables)
          write(tables, output_path)
          output_path
        end

        private

        def base_tables
          @base_tables ||= TtfCompiler.new(@font).build_tables
        end

        def variation_tables
          axis_count = @axes.size
          tables = {}

          fvar_bytes = Fvar.build(@font, axes: @axes, instances: @instances)
          tables["fvar"] = fvar_bytes if fvar_bytes

          avar_bytes = Avar.build(axes: @axes)
          tables["avar"] = avar_bytes if avar_bytes

          stat_bytes = Stat.build(
            axes: stat_axes,
            axis_values: @stat_axis_values,
            elided_name_id: @stat_elided_name_id,
          )
          tables["STAT"] = stat_bytes if stat_bytes

          default_glyphs = @font.glyphs.values
          glyph_order = default_glyphs.map(&:name)

          gvar_masters = @masters.map do |m|
            {
              axes: m[:axes],
              glyphs: glyphs_for_master(m[:font], glyph_order),
            }
          end
          tables["gvar"] = Gvar.build(
            default_glyphs: default_glyphs,
            masters: gvar_masters,
            axis_count: axis_count,
          )

          default_widths = default_glyphs.map { |g| g.width.to_i }
          master_widths = @masters.map do |m|
            glyphs_for_master(m[:font], glyph_order).map { |g| g.width.to_i }
          end
          tables["HVAR"] = Hvar.build(
            default_widths: default_widths,
            master_widths: master_widths,
            axis_count: axis_count,
          )

          if @default_metrics && @master_metrics
            mvar = Mvar.build(
              default_metrics: @default_metrics,
              master_metrics: @master_metrics,
              axis_count: axis_count,
            )
            tables["MVAR"] = mvar if mvar
          end

          tables
        end

        # Project a master's glyphs onto the default master's glyph order
        # so deltas align by index. Missing glyphs default to the master's
        # .notdef (index 0).
        def glyphs_for_master(master_font, glyph_order)
          by_name = master_font.glyphs
          notdef = by_name.values.first
          glyph_order.map { |name| by_name[name] || notdef }
        end

        # STAT design-axis records derived from @axes. Each axis may
        # supply :name_id and :ordering; missing values default sensibly.
        def stat_axes
          @axes.each_with_index.map do |axis, i|
            {
              tag: axis[:tag] || axis["tag"],
              name_id: axis[:name_id] || axis["name_id"] || 0,
              ordering: axis[:ordering] || axis["ordering"] || i,
            }
          end
        end

        def write(tables_hash, output_path)
          dir = File.dirname(output_path)
          FileUtils.mkpath(dir) unless dir == "."
          Fontisan::FontWriter.write_to_file(
            tables_hash.transform_values { |t| serialize_table(t) },
            output_path,
            sfnt_version: SFNT_VERSION,
          )
        end

        # BinData records respond to to_binary_s; raw String values pass through.
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
