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
      # == Why placeholders are name-deconflicted
      #
      # Placeholders are named after the CBDT source's gid ("gid{N}").
      # Outline donors compiled earlier into the same target use the
      # SAME naming scheme (see Source#extract_truetype_glyph), so a
      # CBDT placeholder at "gid110" would collide with an outline
      # glyph at "gid110" from a different donor. Layer#add raises on
      # conflict (it never silently overwrites — that path previously
      # erased real outline glyphs and dropped their cmap entries,
      # causing the CJK Ext G loss in Essenfont-Regular.ttc). We
      # allocate a unique name via UniqueGlyphName so each placeholder
      # lands at its own GID slot without touching the outlines.
      #
      # Glyphs are NOT registered with the deduplicator: each CBDT
      # glyph is unique to its source, and deduplication would
      # incorrectly collapse distinct bitmaps.
      #
      # @param source [Stitcher::Source] the CBDT source
      # @param target [Ufo::Font] target UFO font to receive placeholders
      def add_placeholder_glyphs(source, target)
        @placeholder_names = {}

        ufo = source.font.is_a?(Ufo::Font) ? source.font : nil
        if ufo
          ufo.glyphs.each_value do |g|
            name = UniqueGlyphName.in(target, g.name)
            target.layers.default_layer.add(GlyphCloner.clone(g, name: name))
          end
          return
        end

        maxp = source.font.table("maxp")
        num_glyphs = maxp&.num_glyphs || 0
        cmap = source.font.table("cmap")
        mappings = cmap&.unicode_mappings || {}

        gid_cps = Hash.new { |h, k| h[k] = [] }
        mappings.each { |cp, gid| gid_cps[gid] << cp }

        num_glyphs.times do |gid|
          base_name = gid.zero? ? ".notdef" : "gid#{gid}"
          name = UniqueGlyphName.in(target, base_name)
          glyph = Ufo::Glyph.new(name: name)
          glyph.width = 0
          gid_cps[gid].each { |cp| glyph.add_unicode(cp) }
          target.layers.default_layer.add(glyph)
          @placeholder_names[gid] = name
        end
      end

      # Propagate CBDT/CBLC tables from the CBDT source into the
      # compiled font at `path`, rewriting the file in place.
      #
      # Reads every table from the compiled font as raw bytes (bypassing
      # BinData #table because some tables — notably CFF2 — don't yet
      # have round-trippable BinData models), splices in CBDT/CBLC
      # rebuilt with compiled-font GIDs, and rewrites the file.
      #
      # The CBDT/CBLC rebuild uses Subset::TableStrategy::ColorBitmapSubsetter
      # to remap every bitmap block from source GID to compiled GID.
      # This ensures CBLC's IndexSubTableArray references the compiled
      # font's actual GIDs, not the source's.
      #
      # Falls back to raw-byte copy when the GID mapping can't be
      # resolved (no placeholder names recorded, or compiled post table
      # is v3.0 with no glyph names).
      #
      # No-op when called with a non-CBDT source or nil.
      #
      # @param source [Stitcher::Source, nil] the CBDT source
      # @param path [String] compiled font file to rewrite
      def propagate_tables_into(source, path)
        return unless source

        compiled = FontLoader.load(path)

        tables = {}
        compiled.table_names.each do |tag|
          raw = compiled.table_data[tag]
          tables[tag] = raw if raw
        end

        rebuilt = rebuild_color_tables(source, compiled)
        tables["CBDT"] = rebuilt[:cbdt] if rebuilt[:cbdt]
        tables["CBLC"] = rebuilt[:cblc] if rebuilt[:cblc]

        sfnt = tables.key?("CFF ") || tables.key?("CFF2") ? 0x4F54544F : 0x00010000
        FontWriter.write_to_file(tables, path, sfnt_version: sfnt)
      end

      private

      # Rebuild CBDT/CBLC bytes with compiled-font GIDs instead of
      # source GIDs. Delegates to Subset::TableStrategy::ColorBitmapSubsetter
      # which already implements the offset-remap algorithm for the
      # subsetter — the Stitcher case is the same algorithm with a
      # different GID mapping (source → compiled instead of source →
      # sequential subset GID).
      #
      # Falls back to raw-byte copy when the GID mapping can't be
      # resolved (no placeholder names recorded, or compiled post/cmap
      # can't reverse-map them).
      def rebuild_color_tables(source, compiled)
        source_cbdt = source.raw_table_bytes("CBDT")
        source_cblc = source.raw_table_bytes("CBLC")
        return {} unless source_cbdt && source_cblc

        gid_map = resolve_gid_mapping(compiled)
        return raw_bytes_fallback(source_cbdt, source_cblc) unless gid_map

        mapping = Subset::GlyphMapping.new(mapping: gid_map)
        subsetter = Subset::TableStrategy::ColorBitmapSubsetter.new(
          font: source.font, mapping: mapping,
        ).build

        { cbdt: subsetter.cbdt_bytes, cblc: subsetter.cblc_bytes }
      end

      # Build {source_gid => compiled_gid} from the placeholder names
      # recorded during add_placeholder_glyphs. Walks the compiled
      # font's post table to find each placeholder's compiled GID.
      # Returns nil when the mapping can't be resolved (e.g., no
      # placeholders recorded, or post v3.0 with no names).
      def resolve_gid_mapping(compiled)
        return nil unless @placeholder_names && !@placeholder_names.empty?

        post = compiled.table("post")
        return nil unless post

        names = post.glyph_names
        return nil unless names

        name_to_gid = {}
        names.each_with_index { |name, gid| name_to_gid[name] = gid }

        gid_map = {}
        @placeholder_names.each do |source_gid, placeholder_name|
          compiled_gid = name_to_gid[placeholder_name]
          gid_map[source_gid] = compiled_gid if compiled_gid
        end

        gid_map.empty? ? nil : gid_map
      end

      def raw_bytes_fallback(cbdt_bytes, cblc_bytes)
        { cbdt: cbdt_bytes, cblc: cblc_bytes }
      end
    end
  end
end
