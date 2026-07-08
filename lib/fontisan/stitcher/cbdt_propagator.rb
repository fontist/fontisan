# frozen_string: true

module Fontisan
  class Stitcher
    # Owns every CBDT-specific concern in the stitch pipeline.
    #
    # The Stitcher has two distinct CBDT responsibilities that benefit
    # from being in one place:
    #
    #   1. Detection: exactly one CBDT source per stitch is supported.
    #      Multiple CBDT sources raise MultipleCbdtSourcesError.
    #
    #   2. Action: when a CBDT source exists, the stitcher
    #      - injects empty CBDT placeholder glyphs into the target UFO
    #        (the bitmap data lives in CBDT/CBLC tables, not in outlines),
    #      - propagates the raw CBDT/CBLC tables into the compiled font
    #        file so the bitmaps survive the round-trip.
    #
    # Both responsibilities are model-driven from the CBDT Source itself
    # (`Source#bitmap_mode == :cbdt`), so the propagator is stateless
    # given a list of sources. Tests can construct one with synthetic
    # sources directly.
    class CbdtPropagator
      # @param sources [Array<Stitcher::Source>] all sources the stitcher
      #   knows about, in label order (the propagator does not care
      #   about labels).
      def initialize(sources)
        @sources = sources
      end

      # @return [Stitcher::Source, nil] the single CBDT source, or nil
      #   if there is none.
      # @raise [MultipleCbdtSourcesError] if more than one source is
      #   marked :cbdt.
      def cbdt_source
        cbdts = @sources.select { |s| s.bitmap_mode == :cbdt }
        return nil if cbdts.empty?

        if cbdts.size > 1
          raise MultipleCbdtSourcesError,
                "multiple CBDT sources not supported (found #{cbdts.size})"
        end

        cbdts.first
      end

      # Safe variant: returns nil instead of raising when there are
      # multiple CBDT sources. Used inside the per-subfont glyph-copy
      # pass where raising mid-compile would leave partial state.
      #
      # @return [Stitcher::Source, nil]
      def safe_cbdt_source
        cbdt_source
      rescue MultipleCbdtSourcesError
        nil
      end

      # Inject empty CBDT placeholder glyphs from `source` into the
      # target UFO. One placeholder per gid in the source's maxp/cmap.
      # Outline data is intentionally absent — the bitmap lives in
      # the CBDT table that #propagate_tables_into will copy later.
      #
      # Glyphs are NOT registered with the deduplicator: each CBDT
      # glyph is unique to its source, and deduplication would
      # incorrectly collapse distinct bitmaps.
      #
      # @param source [Stitcher::Source] the CBDT source
      # @param target [Ufo::Font] target UFO font to receive placeholders
      def add_placeholder_glyphs(source, target)
        ufo = source.font.is_a?(Ufo::Font) ? source.font : nil
        if ufo
          ufo.glyphs.each_value { |g| target.layers.default_layer.add(clone_glyph(g, name: g.name)) }
          return
        end

        maxp = source.font.table("maxp")
        num_glyphs = maxp&.num_glyphs || 0
        cmap = source.font.table("cmap")
        mappings = cmap&.unicode_mappings || {}

        gid_cps = Hash.new { |h, k| h[k] = [] }
        mappings.each { |cp, gid| gid_cps[gid] << cp }

        num_glyphs.times do |gid|
          name = gid.zero? ? ".notdef" : "gid#{gid}"
          glyph = Ufo::Glyph.new(name: name)
          glyph.width = 0
          gid_cps[gid].each { |cp| glyph.add_unicode(cp) }
          target.layers.default_layer.add(glyph)
        end
      end

      # Propagate the raw CBDT/CBLC tables from the CBDT source into
      # the compiled font at `path`, rewriting the file in place.
      #
      # Reads every table from the compiled font as raw bytes (bypassing
      # BinData #table because some tables — notably CFF2 — don't yet
      # have round-trippable BinData models), splices in CBDT/CBLC,
      # and rewrites the file.
      #
      # No-op when called with a non-CBDT source or nil.
      #
      # @param source [Stitcher::Source, nil] the CBDT source
      # @param path [String] compiled font file to rewrite
      def propagate_tables_into(source, path)
        return unless source

        compiled = FontLoader.load(path)

        # Read every table as raw bytes straight from the file's table
        # directory. We deliberately bypass #table (which parses via
        # BinData) because some tables — notably CFF2 — don't yet have
        # round-trippable BinData models; calling #table on them returns
        # nil and would silently drop them from the rewritten font.
        tables = {}
        compiled.table_names.each do |tag|
          raw = compiled.table_data[tag]
          tables[tag] = raw if raw
        end

        cbdt_bytes = source.raw_table_bytes("CBDT")
        cblc_bytes = source.raw_table_bytes("CBLC")
        tables["CBDT"] = cbdt_bytes if cbdt_bytes
        tables["CBLC"] = cblc_bytes if cblc_bytes

        sfnt = tables.key?("CFF ") || tables.key?("CFF2") ? 0x4F54544F : 0x00010000
        FontWriter.write_to_file(tables, path, sfnt_version: sfnt)
      end

      private

      def clone_glyph(original, name:)
        copy = Ufo::Glyph.new(name: name)
        copy.width = original.width
        copy.height = original.height
        original.contours.each { |c| copy.add_contour(clone_contour(c)) }
        original.components.each { |c| copy.add_component(c) }
        original.anchors.each { |a| copy.add_anchor(a) }
        original.guidelines.each { |g| copy.add_guideline(g) }
        copy
      end

      def clone_contour(original)
        points = original.points.map do |p|
          Ufo::Point.new(x: p.x, y: p.y, type: p.type, smooth: p.smooth)
        end
        Ufo::Contour.new(points)
      end
    end
  end
end
