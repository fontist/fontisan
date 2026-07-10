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
    #
    # = Codepoint remap
    #
    # Some donor fonts ship glyphs at non-canonical codepoints — a
    # keyboard-mapped font whose "A" is at U+0041, or a PUA-allocated
    # pre-Unicode font. Pass a +remap:+ hash at construction to expose
    # those glyphs at their canonical codepoints without mutating the
    # donor font's cmap:
    #
    #   Source.new(font, remap: { 0x41 => 0x11DB0 })
    #
    # With a remap set, the source answers +gid_for_codepoint+ for the
    # *target* codepoints (0x11DB0 in the example) by translating them
    # to the donor's *source* codepoints (0x41). Source codepoints not
    # listed in the remap are hidden — only the remapped coverage is
    # exposed. This matches the typical "use this donor for exactly
    # these output characters" intent, and avoids leaking the donor's
    # ASCII/PUA noise into the output.
    class Source
      MAX_COMPOUND_DEPTH = 32

      attr_reader :font, :remap

      # @param font [TrueTypeFont, OpenTypeFont, Ufo::Font] donor font
      # @param remap [Hash{Integer=>Integer}, nil] optional
      #   {source_codepoint => target_codepoint}. When present (even
      #   empty), source codepoints not listed are hidden from
      #   lookups. Pass +nil+ (the default) for the passthrough
      #   behavior — every donor codepoint is exposed as-is.
      def initialize(font, remap: nil)
        @font = font
        @bin_data_cache = nil

        # Distinguish "no remap kwarg" (nil → passthrough) from
        # "explicit empty remap" ({} → drop everything). The latter
        # still flips the source into remapped mode, just with no
        # entries — every donor codepoint gets filtered out.
        return unless remap

        @remap = remap.to_h.transform_keys(&:to_i).transform_values(&:to_i)
        @inverse_remap = @remap.each_with_object({}) do |(src, target), h|
          h[target] = src
        end
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
      #
      # When +remap+ was set at construction, +codepoint+ is treated as
      # a *target* codepoint — the source codepoint that maps to it via
      # +remap+ is what actually gets looked up. Returns +nil+ for
      # codepoints the remap does not cover.
      #
      # @param codepoint [Integer]
      # @return [Integer, nil]
      def gid_for_codepoint(codepoint)
        src_cp = source_codepoint_for(codepoint)
        return nil unless src_cp

        case @font
        when Fontisan::Ufo::Font then ufo_gid_for(src_cp)
        else bin_data_gid_for(src_cp)
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
        head = @font.table("head")
        num_h_metrics = hhea&.number_of_h_metrics || 1
        num_glyphs = maxp&.num_glyphs || 0

        if hmtx.respond_to?(:parse_with_context)
          hmtx.parse_with_context(num_h_metrics, num_glyphs)
        end

        # Fallback advance width when hmtx lookup fails for a GID.
        # Per the OpenType spec, glyphs at GID >= numberOfHMetrics
        # inherit the last LongHorMetric's advanceWidth. If the table
        # is empty or corrupt, fall back to the font's unitsPerEm.
        fallback_width = if hmtx.respond_to?(:h_metrics) && hmtx.h_metrics&.any?
                           hmtx.h_metrics.last[:advance_width]
                         else
                           head&.units_per_em || 1000
                         end

        num_glyphs.times do |gid|
          metric = hmtx&.metric_for(gid)
          aw = metric ? metric[:advance_width] : nil
          widths[gid] = aw&.positive? ? aw : fallback_width
        rescue StandardError
          widths[gid] = fallback_width
        end
        widths
      end

      # Extract a single glyph by gid, parsing just the relevant bytes.
      # O(1) per call (after the first call's table-parsing overhead).
      #
      # For TTF (glyf) sources: reads one glyph from glyf/loca.
      # For OTF (CFF) sources: falls back to the full-donor conversion
      # BUT uses a proper gid→name map (not array index) to avoid the
      # gid-misalignment bug that dropped Plane 1 codepoints.
      def extract_single_glyph_from_bindata(gid)
        cache = bin_data_cache

        if cache[:glyf] && cache[:loca] && cache[:head]
          extract_truetype_glyph(gid, cache)
        elsif @font.has_table?("CFF ")
          extract_cff_glyph_safe(gid)
        end
      end

      # CFF glyph extraction: uses the full UFO conversion. After the
      # fix in FromBinData (no more `next unless simple`), every gid
      # gets a glyph, so array index = gid.
      def extract_cff_glyph_safe(gid)
        ufo = converted_ufo
        names = ufo.glyphs.keys
        return nil if gid >= names.size

        name = names[gid]
        ufo.glyph(name)
      end

      # Lazily convert the loaded TTF/OTF to a UFO::Font (for CFF
      # sources and as a fallback).
      def converted_ufo
        @converted_ufo ||= Fontisan::Ufo::Convert::FromBinData.convert(@font)
      end

      def extract_truetype_glyph(gid, cache)
        raw = cache[:glyf].glyph_for(gid, cache[:loca], cache[:head])
        return nil unless raw

        name = gid.zero? ? ".notdef" : "gid#{gid}"
        glyph = Fontisan::Ufo::Glyph.new(name: name)
        glyph.width = glyph_width(gid)

        if raw.respond_to?(:simple?) && raw.simple?
          copy_simple_contours(raw, glyph)
        elsif raw.respond_to?(:compound?) && raw.compound?
          flatten_compound_into(raw, glyph, cache, Set.new)
        end

        normalize_glyph_metrics!(glyph, cache[:head])
        add_cmap_unicodes(gid, glyph)
        glyph
      rescue StandardError
        nil
      end

      # Fix glyphs whose contours extend far left of the origin
      # (massively negative LSB) or whose advance width was lost
      # during donor hmtx extraction. Without this, Egyptian
      # Hieroglyphs and similar donor glyphs overflow into the
      # preceding character cell.
      #
      # Shifts all x-coordinates so xMin >= 0, then ensures the
      # advance width covers the glyph's full visual extent.
      def normalize_glyph_metrics!(glyph, head)
        return if glyph.contours.empty?

        bbox = glyph.bbox
        return unless bbox

        upm = head&.units_per_em || 1000
        threshold = -(upm * 0.1).to_i

        # Shift contours right if the glyph extends past the origin
        if bbox.x_min < threshold
          shift = -bbox.x_min.to_i
          glyph.contours.each do |contour|
            contour.points.each { |pt| pt.x = pt.x + shift }
          end
        end

        # Ensure advance width is positive and covers the glyph
        visual_width = glyph.bbox&.x_max&.to_i || upm
        if glyph.width.to_i <= 0 || glyph.width.to_i < visual_width
          glyph.width = [visual_width, upm].max
        end
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

      # Recursively flatten a CompoundGlyph's components into the UFO
      # glyph as contours (with transforms applied). This makes the
      # extracted glyph self-contained — it doesn't depend on the
      # component glyphs being present in the target font.
      #
      # Only components with ARGS_ARE_XY_VALUES are flattened by offset.
      # Point-index alignment (rare) is skipped — those components
      # contribute nothing, but the rest of the compound is preserved.
      def flatten_compound_into(compound, ufo_glyph, cache, visited, depth = 0)
        return if depth > MAX_COMPOUND_DEPTH
        return if visited.include?(compound.glyph_id)

        visited = visited.dup.add(compound.glyph_id)

        compound.components.each do |component|
          next unless component.args_are_xy?

          raw = cache[:glyf].glyph_for(component.glyph_index, cache[:loca],
                                       cache[:head])
          next unless raw

          matrix = component.transformation_matrix

          if raw.respond_to?(:simple?) && raw.simple?
            flatten_simple_component(raw, ufo_glyph, matrix)
          elsif raw.respond_to?(:compound?) && raw.compound?
            flatten_compound_into(raw, ufo_glyph, cache, visited, depth + 1)
          end
        end
      end

      # Apply a 2×3 affine matrix [a, b, c, d, e, f] to each point of
      # a simple component, appending the transformed contours.
      # The math is delegated to +Transformation#apply+ so the
      # affine-matrix logic lives in one place (DRY) — same code path
      # the UFO Transformations filter uses.
      def flatten_simple_component(simple, ufo_glyph, matrix)
        transform = Ufo::Transformation.new(
          a: matrix[0], b: matrix[1],
          c: matrix[2], d: matrix[3],
          e: matrix[4], f: matrix[5]
        )
        num_contours = simple.end_pts_of_contours&.size || 0
        return if num_contours.zero?

        num_contours.times do |ci|
          points = simple.points_for_contour(ci)
          next unless points && !points.empty?

          ufo_points = points.map do |pt|
            x = (pt[:x] || pt["x"]).to_f
            y = (pt[:y] || pt["y"]).to_f
            tx, ty = transform.apply(x, y)
            on_curve = pt[:on_curve].nil? || pt[:on_curve]
            type = on_curve ? "line" : "offcurve"
            Ufo::Point.new(x: tx, y: ty, type: type)
          end
          ufo_glyph.add_contour(Ufo::Contour.new(ufo_points))
        end
      end

      # Add Unicode codepoints from the cmap that map to this gid.
      #
      # When +remap+ was set at construction, the source's raw codepoints
      # are translated through the remap (source→target), and source
      # codepoints not in the remap are dropped. Otherwise the raw cmap
      # codepoints are attached as-is.
      def add_cmap_unicodes(gid, glyph)
        effective_codepoints_for_gid(gid).each { |cp| glyph.add_unicode(cp) }
      end

      # Translate a caller-facing codepoint to the donor's own codepoint.
      # Without remap, the two are identical. With remap, the caller's
      # codepoint is the *target*; look up the source codepoint that
      # maps to it. Returns +nil+ if no remap entry covers the target.
      def source_codepoint_for(codepoint)
        return codepoint unless @remap

        @inverse_remap[codepoint]
      end

      # Codepoints that should be attached to a glyph at the given gid,
      # after applying the remap (if any).
      def effective_codepoints_for_gid(gid)
        raw_cmap = self.raw_cmap
        raw_cmap.each_with_object([]) do |(src_cp, g), cps|
          next unless g == gid

          if @remap
            target = @remap[src_cp]
            cps << target if target
          else
            cps << src_cp
          end
        end
      end

      # The raw cmap hash from the donor's table. Always {src_cp => gid};
      # never remapped. UFO sources return {} (no cmap table).
      def raw_cmap
        cmap = @font.table("cmap")
        return {} unless cmap

        cmap.unicode_mappings || {}
      rescue StandardError
        {}
      end
    end
  end
end
