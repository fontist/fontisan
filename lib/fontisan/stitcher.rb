# frozen_string_literal: true

module Fontisan
  # Multi-source font stitcher with explicit subfont declaration.
  #
  # Every set of codepoints is explicitly assigned to a named subfont
  # via the required `into:` keyword. The user controls the collection
  # structure upfront — there are no defaults and no after-the-fact
  # splitting.
  #
  # Single-font output: `write_to` requires a `subfont:` name.
  # Collection output: `write_collection` writes all declared subfonts.
  #
  # @example Single font
  #   stitcher = Fontisan::Stitcher.new
  #   stitcher.add_source(:latin, Fontisan::Ufo::Font.open("latin.ufo"))
  #   stitcher.include_range(0x41..0x5A, from: :latin, into: :main)
  #   stitcher.write_to("out.ttf", format: :ttf, subfont: :main)
  #
  # @example Collection
  #   stitcher = Fontisan::Stitcher.new
  #   stitcher.add_source(:noto_sans, noto_sans)
  #   stitcher.add_source(:noto_cjk, noto_cjk)
  #   stitcher.include_range(0x41..0x5A, from: :noto_sans, into: :latin)
  #   stitcher.include_range(0x4E00..0x9FFF, from: :noto_cjk, into: :cjk)
  #   stitcher.write_collection("out.otc", format: :otf2)
  class Stitcher
    autoload :Source,           "fontisan/stitcher/source"
    autoload :Selector,         "fontisan/stitcher/selector"
    autoload :GlyphSignature,   "fontisan/stitcher/glyph_signature"
    autoload :Deduplicator,     "fontisan/stitcher/deduplicator"
    autoload :GlyphLimit,       "fontisan/stitcher/glyph_limit"
    autoload :CollectionResult, "fontisan/stitcher/collection_result"
    autoload :SubfontStats,     "fontisan/stitcher/collection_result"
    autoload :FormatMetadata,   "fontisan/stitcher/format_metadata"
    autoload :PartitionStrategy, "fontisan/stitcher/partition_strategy"
    autoload :CbdtPropagator,   "fontisan/stitcher/cbdt_propagator"
    autoload :GlyphCloner,      "fontisan/stitcher/glyph_cloner"
    autoload :GlyphCopier,      "fontisan/stitcher/glyph_copier"
    autoload :UniqueGlyphName,  "fontisan/stitcher/unique_glyph_name"

    # Internal: pairs a compiled loaded font with its stats so
    # +write_collection+ can build the collection and the result from a
    # single compilation pass.
    CompiledSubfont = Struct.new(:name, :font, :stats, keyword_init: true)
    private_constant :CompiledSubfont

    DEFAULT_DEDUPLICATE = true

    attr_reader :sources, :subfonts, :info

    def initialize(deduplicate: DEFAULT_DEDUPLICATE)
      @sources = {}
      @subfonts = Hash.new { |h, k| h[k] = [] }
      @info = nil
      @deduplicate = deduplicate
    end

    def add_source(label, font, remap: nil)
      @sources[label.to_sym] = Source.new(font, remap: remap)
    end

    def include_range(range, from:, into:)
      Selector::Range.new(range).apply(source(from), @subfonts[into])
    end

    def include_codepoints(codepoints, from:, into:)
      Selector::Codepoints.new(codepoints).apply(source(from), @subfonts[into])
    end

    def include_codepoints_map(cp_map, into:)
      cp_map.to_h
        .group_by { |_cp, label| label }
        .transform_values { |pairs| pairs.map(&:first).sort }
        .each { |label, cps| include_codepoints(cps, from: label, into: into) }
    end

    def include_gid(donor_gid, from:, into:)
      Selector::Gid.new(donor_gid).apply(source(from), @subfonts[into])
    end

    def include_notdef(from:, into:)
      include_gid(0, from: from, into: into)
    end

    def set_info(info_hash)
      @info = Ufo::Info.new(info_hash)
    end

    def subfont_names
      @subfonts.keys
    end

    def build_target_font(subfont:)
      build_target_for(subfont)
    end

    def write_to(path, format:, subfont:)
      target = build_target_for(subfont)
      GlyphLimit.check!(target.glyphs.size, format: format)

      metadata = FormatMetadata.resolve(format)
      metadata.compiler_class.new(target).compile(output_path: path)

      cbdt_propagator.propagate_tables_into(cbdt_propagator.cbdt_source, path)
      path
    end

    def write_collection(path, format:)
      raise ArgumentError, "no subfonts declared" if @subfonts.empty?

      compiled = @subfonts.keys.map do |name|
        compile_subfont_with_stats(name, format: format)
      end
      fonts = compiled.map(&:font)

      collection_format = FormatMetadata.resolve(format).collection_format
      Collection::Builder.new(fonts, format: collection_format,
                                     optimize: true).build_to_file(path)

      CollectionResult.new(
        path: path,
        bytes: File.size(path),
        subfonts: compiled.map(&:stats),
      )
    end

    private

    def source(label)
      @sources.fetch(label.to_sym) do
        raise ArgumentError, "unknown source: #{label.inspect}"
      end
    end

    def build_target_for(subfont_name)
      bindings = @subfonts[subfont_name] || []
      target = Ufo::Font.new
      target.info = @info ? @info.dup : Ufo::Info.new
      dedup = @deduplicate ? Deduplicator.new : nil
      assign_gids_and_copy_glyphs(bindings, target, dedup)
      target
    end

    def compile_subfont_with_stats(subfont_name, format:)
      target = build_target_for(subfont_name)
      GlyphLimit.check!(target.glyphs.size, format: format)

      metadata = FormatMetadata.resolve(format)
      Dir.mktmpdir do |dir|
        sub_path = File.join(dir, "sub#{subfont_name}#{metadata.extension}")
        metadata.compiler_class.new(target).compile(output_path: sub_path)
        cbdt_propagator.propagate_tables_into(cbdt_propagator.cbdt_source,
                                              sub_path)

        loaded = Fontisan::FontLoader.load(sub_path)
        stats = SubfontStats.new(
          name: subfont_name,
          glyph_count: loaded.table("maxp")&.num_glyphs || 0,
          codepoint_count: (loaded.table("cmap")&.unicode_mappings || {}).size,
        )
        CompiledSubfont.new(name: subfont_name, font: loaded, stats: stats)
      end
    end

    def assign_gids_and_copy_glyphs(bindings, target, deduplicator)
      cbdt = cbdt_propagator.safe_cbdt_source
      copier = GlyphCopier.new(deduplicator)

      # Glyph ordering matters: Cmap.build uses first-wins semantics
      # (Cmap.build docstring), so outline donors must be stitched
      # before CBDT placeholders. Otherwise the empty CBDT placeholder
      # would land at a lower GID and win the cp→gid mapping for any
      # codepoint covered by both donors, hiding the real outline glyph.
      # CBDT bitmap data still propagates via CbdtPropagator.
      copier.inject_notdef(bindings, target)
      copier.copy_outlines(bindings, target, skip_sources: cbdt ? [cbdt] : [])
      cbdt_propagator.add_placeholder_glyphs(cbdt, target) if cbdt
    end

    def cbdt_propagator
      @cbdt_propagator ||= CbdtPropagator.new(@sources.values)
    end
  end
end
