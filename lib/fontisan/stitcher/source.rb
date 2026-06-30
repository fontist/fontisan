# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Wraps a source font (UFO or loaded TTF/OTF) behind a single
    # extraction API used by the selectors.
    #
    # For UFO sources, glyphs are accessed by name directly. For TTF
    # or OTF sources, individual glyphs are extracted on demand from
    # the BinData tables (glyf/loca/head for TTF, CFF for OTF). This
    # is O(1) per glyph rather than the previous O(n) full-donor
    # conversion.
    #
    # CBDT/CBLC sources (e.g. NotoColorEmoji) are detected via
    # #bitmap_mode. When a source is :cbdt, the Stitcher propagates
    # the raw CBDT/CBLC tables into the output instead of extracting
    # outlines. The glyph data lives in the bitmap tables, not in glyf.
    class Source
      attr_reader :font

      def initialize(font)
        @font = font
        @bin_data_cache = nil
      end

      # @return [Symbol] :ufo, :ttf, :otf
      def format
        case @font
        when Fontisan::Ufo::Font then :ufo
        when Fontisan::TrueTypeFont then :ttf
        when Fontisan::OpenTypeFont then :otf
        else :unknown
        end
      end

      # Detect how this source stores glyph data.
      #
      # - :glyf — TrueType outlines (glyf table present)
      # - :cbdt — Color bitmaps (CBDT + CBLC tables, no glyf)
      # - :mixed — Both glyf and CBDT
      # - :none  — UFO source or neither table present
      #
      # @return [Symbol]
      def bitmap_mode
        return :none if @font.is_a?(Fontisan::Ufo::Font)
        return :none unless @font.respond_to?(:has_table?)

        has_cbdt = @font.has_table?("CBDT") && @font.has_table?("CBLC")
        has_glyf = @font.has_table?("glyf") || @font.has_table?("CFF ")
        return :mixed if has_cbdt && has_glyf
        return :cbdt if has_cbdt
        return :glyf if has_glyf

        :none
      end

      # Find the gid for a Unicode codepoint in this source.
      # @param codepoint [Integer]
      # @return [Integer, nil]
      def gid_for_codepoint(codepoint)
        case @font
        when Fontisan::Ufo::Font then ufo_gid_for(codepoint)
        else bin_data_gid_for(codepoint)
        end
      end

      # Extract a glyph by gid.
      #
      # For TTF/OTF sources, this is O(1) per glyph: it parses just
      # the requested glyph from glyf/CFF on demand, not the entire
      # donor. The full-donor conversion is avoided entirely.
      #
      # For CBDT sources, returns a placeholder glyph (no contours)
      # since the glyph data is in the bitmap tables, not outlines.
      #
      # @param gid [Integer]
      # @return [Fontisan::Ufo::Glyph, nil]
      def glyph_for_gid(gid)
        case @font
        when Fontisan::Ufo::Font then ufo_glyph_at(gid)
        else extract_single_glyph_from_bindata(gid)
        end
      end

      # Raw table bytes from the loaded font (for passthrough).
      # @param tag [String] 4-byte table tag (e.g. "CBDT", "CBLC")
      # @return [String, nil] raw bytes or nil if table not present
      def raw_table_bytes(tag)
        sfnt_table = @font.table(tag)
        return nil unless sfnt_table

        sfnt_table.raw_data
      rescue StandardError
        nil
      end

      # Width of a specific glyph (extracted from hmtx).
      # Falls back to 0 if hmtx is missing.
      # @param gid [Integer]
      # @return [Integer]
      def glyph_width(gid)
        widths = bin_data_widths
        widths[gid] || 0
      end

      private

      # ---------- UFO source ----------

      def ufo_gid_for(codepoint)
        @font.glyphs.each_with_index do |(_name, glyph), index|
          return index if glyph.unicodes.include?(codepoint)
        end
        nil
      end

      def ufo_glyph_at(gid)
        names = @font.glyphs.keys
        name = names[gid]
        return nil unless name

        @font.glyph(name)
      end

      # ---------- TTF/OTF source: O(1) per-glyph extraction ----------

      def bin_data_gid_for(codepoint)
        cmap = @font.table("cmap")
        return nil unless cmap

        cmap.unicode_mappings[codepoint]
      end

      # Lazily parse the relevant BinData tables. Cached so we only
      # pay the parse cost once per source.
      def bin_data_cache
        @bin_data_cache ||= parse_bin_data_tables
      end

      def parse_bin_data_tables
        cache = { head: @font.table("head") }

        if @font.has_table?("glyf")
          cache[:loca] = @font.table("loca")
          cache[:glyf] = @font.table("glyf")
          # loca needs head's index_to_loc_format to size its offsets
          if cache[:loca].respond_to?(:parse_with_context) && cache[:head]
            cache[:loca].parse_with_context(
              cache[:head].index_to_loc_format,
              @font.table("maxp")&.num_glyphs || 0,
            )
          end
        end

        cache
      end

      # Build {gid → advance_width} from hmtx (cached).
      def bin_data_widths
        @bin_data_widths ||= build_bin_data_widths
      end

      def build_bin_data_widths
        widths = {}
        hmtx = @font.table("hmtx")
        return widths unless hmtx

        hhea = @font.table("hhea")
        maxp = @font.table("maxp")
        num_h_metrics = hhea&.number_of_h_metrics || 1
        num_glyphs = maxp&.num_glyphs || 0

        if hmtx.respond_to?(:parse_with_context)
          hmtx.parse_with_context(num_h_metrics, num_glyphs)
        end

        num_glyphs.times do |gid|
          metric = hmtx.respond_to?(:metric_for) ? hmtx.metric_for(gid) : nil
          widths[gid] = metric ? metric[:advance_width] : 0
        rescue StandardError
          widths[gid] = 0
        end
        widths
      end

      # Extract a single glyph by gid, parsing just the relevant bytes.
      # O(1) per call (after the first call's table-parsing overhead).
      def extract_single_glyph_from_bindata(gid)
        cache = bin_data_cache

        if cache[:glyf] && cache[:loca] && cache[:head]
          extract_truetype_glyph(gid, cache)
        end
      end

      def extract_truetype_glyph(gid, cache)
        simple = cache[:glyf].glyph_for(gid, cache[:loca], cache[:head])
        return nil unless simple
        return nil unless simple.respond_to?(:simple?) && simple.simple?

        name = gid.zero? ? ".notdef" : "gid#{gid}"
        glyph = Fontisan::Ufo::Glyph.new(name: name)
        glyph.width = glyph_width(gid)
        copy_simple_contours(simple, glyph)
        add_cmap_unicodes(gid, glyph)
        glyph
      rescue StandardError
        nil
      end

      # Copy a SimpleGlyph's contours + points into a Ufo::Glyph.
      def copy_simple_contours(simple, ufo_glyph)
        num_contours = simple.end_pts_of_contours&.size || 0
        return if num_contours.zero?

        num_contours.times do |ci|
          points = simple.points_for_contour(ci)
          next unless points && !points.empty?

          ufo_points = points.map do |pt|
            x = pt[:x] || pt["x"]
            y = pt[:y] || pt["y"]
            on_curve = pt[:on_curve].nil? || pt[:on_curve]
            type = on_curve ? "line" : "offcurve"
            Fontisan::Ufo::Point.new(x: x.to_f, y: y.to_f, type: type)
          end
          ufo_glyph.add_contour(Fontisan::Ufo::Contour.new(ufo_points))
        end
      end

      # Add Unicode codepoints from the cmap that map to this gid.
      def add_cmap_unicodes(gid, glyph)
        cmap = @font.table("cmap")
        return unless cmap

        (cmap.unicode_mappings || {}).each do |cp, g|
          glyph.add_unicode(cp) if g == gid
        end
      end
    end
  end
end
