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
    autoload :Source,          "fontisan/stitcher/source"
    autoload :Selector,        "fontisan/stitcher/selector"
    autoload :GlyphSignature,  "fontisan/stitcher/glyph_signature"
    autoload :Deduplicator,    "fontisan/stitcher/deduplicator"
    autoload :GlyphLimit,      "fontisan/stitcher/glyph_limit"

    DEFAULT_DEDUPLICATE = true

    attr_reader :sources, :subfonts, :info

    def initialize(deduplicate: DEFAULT_DEDUPLICATE)
      @sources = {}
      @subfonts = Hash.new { |h, k| h[k] = [] }
      @info = nil
      @deduplicate = deduplicate
    end

    def add_source(label, font)
      @sources[label.to_sym] = Source.new(font)
    end

    def include_range(range, from:, into:)
      Selector::Range.new(range).apply(source(from), @subfonts[into])
    end

    def include_codepoints(codepoints, from:, into:)
      Selector::Codepoints.new(codepoints).apply(source(from), @subfonts[into])
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

      compiler = compiler_for(format)
      compiler.new(target).compile(output_path: path)

      propagate_cbdt_tables(path) if cbdt_source
      path
    end

    def write_collection(path, format:)
      raise ArgumentError, "no subfonts declared" if @subfonts.empty?

      compiled = @subfonts.keys.map do |name|
        compile_subfont_to_loaded_font(name, format: format)
      end

      collection_format = collection_format_for(format)
      Collection::Builder.new(compiled, format: collection_format,
                                        optimize: true).build_to_file(path)
      path
    end

    private

    def source(label)
      @sources.fetch(label.to_sym) do
        raise ArgumentError, "unknown source: #{label.inspect}"
      end
    end

    def cbdt_source
      cbdts = @sources.values.select { |s| s.bitmap_mode == :cbdt }
      if cbdts.size > 1
        raise MultipleCbdtSourcesError,
              "multiple CBDT sources not supported (found #{cbdts.size})"
      end

      cbdts.first
    end

    def compiler_for(format)
      case format.to_sym
      when :ttf then Ufo::Compile::TtfCompiler
      when :otf then Ufo::Compile::OtfCompiler
      when :otf2 then Ufo::Compile::Otf2Compiler
      else
        raise ArgumentError, "unknown format: #{format.inspect}"
      end
    end

    def collection_format_for(subfont_format)
      subfont_format == :ttf ? :ttc : :otc
    end

    def build_target_for(subfont_name)
      bindings = @subfonts[subfont_name] || []
      target = Ufo::Font.new
      target.info = @info ? @info.dup : Ufo::Info.new
      dedup = @deduplicate ? Deduplicator.new : nil
      assign_gids_and_copy_glyphs(bindings, target, dedup)
      target
    end

    def compile_subfont_to_loaded_font(subfont_name, format:)
      target = build_target_for(subfont_name)
      GlyphLimit.check!(target.glyphs.size, format: format)

      ext = format == :ttf ? ".ttf" : ".otf"
      Dir.mktmpdir do |dir|
        sub_path = File.join(dir, "sub#{subfont_name}#{ext}")
        compiler = compiler_for(format)
        compiler.new(target).compile(output_path: sub_path)
        return Fontisan::FontLoader.load(sub_path)
      end
    end

    def assign_gids_and_copy_glyphs(bindings, target, deduplicator)
      cbdt = safe_cbdt_source

      if cbdt
        add_all_cbdt_glyphs(cbdt, target)
      else
        add_notdef_from(bindings, target, deduplicator)
      end

      sorted_bindings(bindings).each do |binding|
        next if binding[:donor_gid].zero?
        next if cbdt && binding[:source].equal?(cbdt)

        glyph = binding[:source].glyph_for_gid(binding[:donor_gid])
        next unless glyph

        canonical = deduplicator&.find(glyph)
        if canonical && target.glyphs.key?(canonical)
          add_extra_unicode(target, canonical, binding[:codepoint])
        else
          name = unique_target_name(target, glyph.name)
          copy_glyph_into(target, name: name, source: binding[:source],
                                  donor_gid: binding[:donor_gid],
                                  codepoint: binding[:codepoint])
          deduplicator&.register(glyph, name)
        end
      end
    end

    def safe_cbdt_source
      cbdts = @sources.values.select { |s| s.bitmap_mode == :cbdt }
      cbdts.size == 1 ? cbdts.first : nil
    rescue MultipleCbdtSourcesError
      nil
    end

    def sorted_bindings(bindings)
      bindings.sort_by { |b| [b[:codepoint] || Float::INFINITY, b[:donor_gid]] }
    end

    def add_notdef_from(bindings, target, deduplicator)
      notdef_binding = bindings.find { |b| b[:donor_gid].zero? }
      if notdef_binding
        copy_glyph_into(target, name: ".notdef",
                                source: notdef_binding[:source],
                                donor_gid: 0)
      else
        target.layers.default_layer.add(Ufo::Glyph.new(name: ".notdef"))
      end
      dedup_target = target.glyphs[".notdef"]
      deduplicator&.register(dedup_target, ".notdef") if dedup_target
    end

    def copy_glyph_into(target_font, name:, source:, donor_gid:, codepoint: nil)
      original = source.glyph_for_gid(donor_gid)
      return unless original

      copy = clone_glyph(original, name: name)
      copy.add_unicode(codepoint) if codepoint
      target_font.layers.default_layer.add(copy)
    end

    def add_extra_unicode(target_font, glyph_name, codepoint)
      return unless codepoint

      glyph = target_font.glyph(glyph_name)
      glyph.add_unicode(codepoint) unless glyph.unicodes.include?(codepoint)
    end

    def unique_target_name(target_font, base_name)
      return base_name unless target_font.glyphs.key?(base_name)

      suffix = 1
      loop do
        candidate = "#{base_name}.#{suffix}"
        return candidate unless target_font.glyphs.key?(candidate)

        suffix += 1
      end
    end

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

    def propagate_cbdt_tables(path)
      source = cbdt_source
      return unless source

      compiled = Fontisan::FontLoader.load(path)

      tables = {}
      compiled.table_names.each do |tag|
        raw = extract_raw_table(compiled, tag)
        tables[tag] = raw if raw
      end

      cbdt_bytes = source.raw_table_bytes("CBDT")
      cblc_bytes = source.raw_table_bytes("CBLC")
      tables["CBDT"] = cbdt_bytes if cbdt_bytes
      tables["CBLC"] = cblc_bytes if cblc_bytes

      sfnt = tables.key?("CFF ") || tables.key?("CFF2") ? 0x4F54544F : 0x00010000
      Fontisan::FontWriter.write_to_file(tables, path, sfnt_version: sfnt)
    end

    def extract_raw_table(font, tag)
      sfnt_table = font.table(tag)
      return nil unless sfnt_table

      sfnt_table.raw_data
    rescue StandardError
      nil
    end

    def add_all_cbdt_glyphs(source, target)
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
  end
end
