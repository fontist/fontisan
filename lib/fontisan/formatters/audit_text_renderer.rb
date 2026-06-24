# frozen_string_literal: true

module Fontisan
  module Formatters
    # Human-readable, sectioned view of an {Models::Audit::AuditReport}.
    #
    # The text formatter is the default `--format text` output for
    # `fontisan audit`. Complements YAML/JSON (machine-facing) with a
    # terse, scannable terminal view. Every section is nil-safe so the
    # same renderer covers full OpenType/TrueType faces, Type 1 fonts
    # (no OS/2, no metrics, no layout), and partial reports.
    class AuditTextRenderer
      SEPARATOR = "=" * 80
      LABEL_WIDTH = 18
      LIST_LIMIT = 10

      WIDTH_NAMES = {
        1 => "Ultra-condensed", 2 => "Extra-condensed", 3 => "Condensed",
        4 => "Semi-condensed", 5 => "Medium", 6 => "Semi-expanded",
        7 => "Expanded", 8 => "Extra-expanded", 9 => "Ultra-expanded"
      }.freeze

      # @param report [Models::Audit::AuditReport]
      def initialize(report)
        @report = report
        @lines = []
      end

      # @return [String]
      def render
        render_header
        render_identity
        render_style
        render_metrics
        render_coverage
        render_blocks
        render_licensing
        render_hinting
        render_color
        render_variation
        render_opentype_layout
        render_language_coverage
        render_warnings
        @lines.join("\n")
      end

      private

      def render_header
        @lines << (@report.postscript_name || @report.family_name || "(unknown)")
        @lines << SEPARATOR
        @lines << two_col("generated_at:", @report.generated_at,
                          "fontisan:",     @report.fontisan_version)
        @lines << "source_sha256: #{@report.source_sha256}"
        @lines << "source_file:   #{@report.source_file}"
        @lines << two_col("source_format:", @report.source_format,
                          "layout:", layout_descriptor)
      end

      def layout_descriptor
        if @report.num_fonts_in_source.nil? || @report.num_fonts_in_source <= 1
          "single face (1/1)"
        else
          format("collection face (%<idx>d/%<total>d)",
                 idx: (@report.font_index || 0) + 1,
                 total: @report.num_fonts_in_source)
        end
      end

      def render_identity
        section("IDENTITY")
        row("Family",     @report.family_name)
        row("Subfamily",  @report.subfamily_name)
        row("Full name",  @report.full_name)
        row("PostScript", @report.postscript_name)
        row("Version",    @report.version)
        row("Revision",   @report.font_revision)
      end

      def render_style
        section("STYLE")
        row("Weight class", weight_descriptor)
        row("Width class",  width_descriptor)
        row("Bold",         yes_no(@report.bold))
        row("Italic",       yes_no(@report.italic))
        row("PANOSE",       @report.panose)
      end

      def render_metrics
        return unless @report.metrics

        m = @report.metrics
        section("METRICS")
        row("unitsPerEm", m.units_per_em)
        row("hhea", "ascent: #{m.hhea_ascent} / descent: #{m.hhea_descent} / line gap: #{m.hhea_line_gap}") if m.hhea_ascent
        row("OS/2 typo", "ascent: #{m.typo_ascender} / descent: #{m.typo_descender} / line gap: #{m.typo_line_gap}") if m.typo_ascender
        row("OS/2 win", "ascent: #{m.win_ascent} / descent: #{m.win_descent}") if m.win_ascent
        row("x-height", m.x_height)
        row("cap height", m.cap_height)
        row("bbox", bbox_descriptor(m)) if m.bbox_x_min || m.bbox_x_max
      end

      def render_coverage
        section("COVERAGE")
        row("Codepoints", @report.total_codepoints)
        row("Glyphs",     @report.total_glyphs)
        row("cmap subtables", format("%s", Array(@report.cmap_subtables).join(", "))) unless Array(@report.cmap_subtables).empty?
        row("Ranges (top #{LIST_LIMIT})", codepoint_range_preview)
        row("Unicode scripts", truncate_list(@report.unicode_scripts))
      end

      def render_blocks
        blocks = Array(@report.blocks)
        return if blocks.empty?

        section("UNICODE BLOCKS (top #{LIST_LIMIT} by fill ratio)")
        blocks.sort_by { |b| -(b.fill_ratio || 0) }.first(LIST_LIMIT).each do |block|
          ratio = block.fill_ratio ? format("%<r>d%%", r: (block.fill_ratio * 100).round) : "?"
          @lines << format("  %<name>-40s %<covered>d/%<total>d  (%<ratio>s)",
                           name: "#{block.name}:", covered: block.covered || 0,
                           total: block.total || 0, ratio: ratio)
        end
      end

      def render_licensing
        return unless @report.licensing

        l = @report.licensing
        section("LICENSING")
        row("Copyright",     l.copyright)
        row("Trademark",     l.trademark)
        row("Manufacturer",  l.manufacturer)
        row("Designer",      l.designer)
        row("License",       l.license_description)
        row("License URL",   l.license_url)
        row("Vendor URL",    l.vendor_url)
        row("Designer URL",  l.designer_url)
        row("Vendor ID",     l.vendor_id)
        row("Embedding",     l.embedding_type)
      end

      def render_hinting
        return unless @report.hinting

        h = @report.hinting
        section("HINTING")
        row("Format", h.hinting_format || (h.is_unhinted ? "unhinted" : "unknown"))
        row("fpgm",  instruction_line(h.has_fpgm, h.fpgm_instruction_count))
        row("prep",  instruction_line(h.has_prep, h.prep_instruction_count))
        row("cvt",   cvt_line(h))
        row("gasp",  gasp_line(h))
        row("CFF hints", h.cff_hint_count)
      end

      def render_color
        return unless @report.color_capabilities

        c = @report.color_capabilities
        section("COLOR")
        formats = Array(c.color_formats)
        row("Color formats", formats.empty? ? "(none)" : truncate_list(formats))
        row("COLR", colr_line(c)) if c.has_colr
        row("CPAL", "palettes: #{c.cpal_palette_count}, colors: #{c.cpal_color_count}") if c.has_cpal
        row("SVG documents", c.svg_document_count) if c.has_svg && c.svg_document_count
        row("CBDT strikes", c.cbdt_strike_count) if c.has_cbdt && c.cbdt_strike_count
        row("sbix strikes", c.sbix_strike_count) if c.has_sbix && c.sbix_strike_count
      end

      def render_variation
        v = @report.variation
        section("VARIABLE FONT")
        if v.nil? || Array(v.axes).empty?
          @lines << "  (not variable)"
          return
        end

        v.axes.each do |axis|
          row(axis.tag, format("%<min>s .. %<max>s  default %<default>s",
                               min: axis.min_value, max: axis.max_value,
                               default: axis.default_value))
        end
        return if Array(v.named_instances).empty?

        @lines << "  Named instances:"
        v.named_instances.each do |inst|
          @lines << "    #{inst.postscript_name || inst.subfamily_name}: #{inst.coordinates}"
        end
      end

      def render_opentype_layout
        return unless @report.opentype_layout

        l = @report.opentype_layout
        section("OPENTYPE LAYOUT")
        row("GSUB", yes_no(l.has_gsub))
        row("GPOS", yes_no(l.has_gpos))
        row("Scripts (#{Array(l.scripts).size})", truncate_list(l.scripts))
        row("Features (#{Array(l.features).size})", truncate_list(l.features))
      end

      def render_language_coverage
        langs = Array(@report.language_coverage)
        return if langs.empty?

        section("LANGUAGE COVERAGE (CLDR #{@report.cldr_version})")
        langs.first(LIST_LIMIT).each do |lang|
          pct = lang.coverage_ratio ? format("%<r>d%%", r: (lang.coverage_ratio * 100).round) : "?"
          mark = lang.fully_supported ? "*" : " "
          @lines << format("  %<mark>s %<lang>-8s %<covered>d/%<total>d  (%<pct>s)",
                           mark: mark, lang: "#{lang.language}:", covered: lang.covered,
                           total: lang.total, pct: pct)
        end
      end

      def render_warnings
        section("WARNINGS")
        @lines << if @report.warning
                    "  #{@report.warning}"
                  else
                    "  (none)"
                  end
      end

      # ---- formatting helpers --------------------------------------------

      def section(title)
        @lines << ""
        @lines << title
      end

      def row(label, value)
        return if value.nil?
        return if value.is_a?(String) && value.empty?

        @lines << "  #{label}:#{' ' * [LABEL_WIDTH - label.to_s.length - 1, 1].max}#{value}"
      end

      def two_col(left_label, left_value, right_label, right_value)
        left = "#{left_label} #{left_value}".ljust(40)
        "#{left}#{right_label} #{right_value}"
      end

      def yes_no(bool)
        bool ? "yes" : "no"
      end

      def truncate_list(items)
        list = Array(items)
        return "(none)" if list.empty?

        shown = list.first(LIST_LIMIT).join(", ")
        shown += ", ..." if list.size > LIST_LIMIT
        shown
      end

      def weight_descriptor
        return nil unless @report.weight_class

        name = weight_name(@report.weight_class)
        "#{@report.weight_class}#{" (#{name})" if name}"
      end

      def width_descriptor
        return nil unless @report.width_class

        name = WIDTH_NAMES[@report.width_class]
        "#{@report.width_class}#{" (#{name})" if name}"
      end

      def weight_name(value)
        case value
        when 100 then "Thin"
        when 200 then "Extra-light"
        when 300 then "Light"
        when 400 then "Regular"
        when 500 then "Medium"
        when 600 then "Semi-bold"
        when 700 then "Bold"
        when 800 then "Extra-bold"
        when 900 then "Black"
        end
      end

      def bbox_descriptor(metrics)
        "(#{metrics.bbox_x_min}, #{metrics.bbox_y_min}) → (#{metrics.bbox_x_max}, #{metrics.bbox_y_max})"
      end

      def codepoint_range_preview
        ranges = Array(@report.codepoint_ranges)
        return "(none)" if ranges.empty?

        shown = ranges.first(LIST_LIMIT).map do |r|
          "U+#{format('%04X', r.first_cp)}-U+#{format('%04X', r.last_cp)}"
        end.join(", ")
        shown += ", ..." if ranges.size > LIST_LIMIT
        shown
      end

      def instruction_line(has, count)
        return "no" unless has

        count ? "#{count} instructions" : "present"
      end

      def cvt_line(hinting)
        return "no" unless hinting.has_cvt

        hinting.cvt_entry_count ? "#{hinting.cvt_entry_count} entries" : "present"
      end

      def gasp_line(hinting)
        ranges = Array(hinting.gasp_ranges)
        return "no" if ranges.empty?

        ppems = ranges.map(&:max_ppem).compact
        "#{ranges.size} ranges (#{ppems.join('/')} ppem)"
      end

      def colr_line(color)
        "v#{color.colr_version}, #{color.colr_base_glyph_count} base glyphs, #{color.colr_layer_count} layers"
      end
    end
  end
end
