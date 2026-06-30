# frozen_string_literal: true

module Fontisan
  # Multi-source font stitcher. Combines glyphs from one or more
  # source fonts (UFO or loaded TTF/OTF) into a single new font.
  #
  # The Stitcher builds a Fontisan::Ufo::Font from selected glyphs,
  # then delegates compilation to the existing TtfCompiler or
  # OtfCompiler. Single source of truth: one compiler pipeline,
  # whether the input is one UFO or many sources.
  #
  # @example Stitch ASCII from one UFO, Hiragana from another
  #   stitcher = Fontisan::Stitcher.new
  #   stitcher.add_source(:latin, Fontisan::Ufo::Font.open("latin.ufo"))
  #   stitcher.add_source(:jp, Fontisan::Ufo::Font.open("jp.ufo"))
  #   stitcher.include_range(0x41..0x5A, from: :latin)
  #   stitcher.include_range(0x3040..0x309F, from: :jp)
  #   stitcher.write_to("stitched.ttf", format: :ttf)
  class Stitcher
    autoload :Source,   "fontisan/stitcher/source"
    autoload :Selector, "fontisan/stitcher/selector"

    attr_reader :sources, :bindings

    def initialize
      @sources = {}
      @bindings = []
      @target = Ufo::Font.new
    end

    # Register a named source font.
    # @param label [Symbol, String] name to reference this source by
    # @param font [Fontisan::Ufo::Font, Fontisan::SfntFont] the source
    def add_source(label, font)
      @sources[label.to_sym] = Source.new(font)
    end

    # Include all codepoints in a range from a named source.
    # @param range [Range<Integer>] codepoint range
    # @param from [Symbol, String] source label
    def include_range(range, from:)
      Selector::Range.new(range).apply(source(from), @bindings)
    end

    # Include an explicit list of codepoints.
    # @param codepoints [Array<Integer>]
    # @param from [Symbol, String] source label
    def include_codepoints(codepoints, from:)
      Selector::Codepoints.new(codepoints).apply(source(from), @bindings)
    end

    # Include a single glyph by donor gid (rare; for unencoded glyphs
    # like .notdef).
    # @param donor_gid [Integer]
    # @param from [Symbol, String] source label
    def include_gid(donor_gid, from:)
      Selector::Gid.new(donor_gid).apply(source(from), @bindings)
    end

    # Always include .notdef from a named source.
    # @param from [Symbol, String] source label
    def include_notdef(from:)
      include_gid(0, from: from)
    end

    # Set font-wide metadata on the stitched font.
    # @param info_hash [Hash] any subset of Fontisan::Ufo::Info fields
    def set_info(info_hash)
      @target.info = Ufo::Info.new(info_hash)
    end

    # Write the stitched font to disk.
    #
    # For CBDT/CBLC sources (e.g. NotoColorEmoji), the raw CBDT and
    # CBLC tables are copied byte-for-byte into the output. This works
    # because CBDT-mode glyphs are processed first (GIDs 0..N-1),
    # matching the source's GID layout. Only one CBDT source is
    # supported; multiple CBDT sources raise MultipleCbdtSourcesError.
    #
    # @param path [String] output file path
    # @param format [Symbol] :ttf or :otf
    def write_to(path, format: :ttf)
      build_target_font
      compiler = compiler_for(format)
      compiler_instance = compiler.new(@target)
      compiler_instance.compile(output_path: path)

      propagate_cbdt_tables(path) if cbdt_source

      path
    end

    # Build the internal UFO::Font from the current bindings. Useful
    # for testing or for further manipulation before writing.
    # @return [Fontisan::Ufo::Font]
    def build_target_font
      @target = Ufo::Font.new
      assign_gids_and_copy_glyphs
      @target
    end

    private

    def source(label)
      @sources.fetch(label.to_sym) do
        raise ArgumentError, "unknown source: #{label.inspect}"
      end
    end

    # Find the single CBDT source among registered sources, if any.
    # Raises if more than one CBDT source is present (merge not supported).
    # @return [Source, nil]
    def cbdt_source
      cbdts = @sources.values.select { |s| s.bitmap_mode == :cbdt }
      if cbdts.size > 1
        raise MultipleCbdtSourcesError,
              "multiple CBDT sources not supported (found #{cbdts.size})"
      end

      cbdts.first
    end

    # Copy raw CBDT + CBLC table bytes from the CBDT source into the
    # compiled output file. The GIDs must match (CBDT glyphs are at
    # the same GIDs in both source and output because they were added
    # first during build_target_font).
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

      sfnt = tables.key?("CFF ") ? 0x4F54544F : 0x00010000
      Fontisan::FontWriter.write_to_file(tables, path, sfnt_version: sfnt)
    end

    def extract_raw_table(font, tag)
      sfnt_table = font.table(tag)
      return nil unless sfnt_table

      sfnt_table.raw_data
    rescue StandardError
      nil
    end

    def compiler_for(format)
      case format.to_sym
      when :ttf then Ufo::Compile::TtfCompiler
      when :otf then Ufo::Compile::OtfCompiler
      else
        raise ArgumentError, "unknown format: #{format.inspect}"
      end
    end

    # Walk bindings in codepoint order, assign sequential new gids,
    # copy each glyph into the target font's default layer.
    #
    # When a CBDT source is present, its glyphs are added FIRST (in
    # source GID order) so that the CBLC's GID references remain valid.
    # Glyf-source bindings are processed AFTER, appending new glyphs.
    def assign_gids_and_copy_glyphs
      cbdt = cbdt_source

      if cbdt
        add_all_cbdt_glyphs(cbdt)
      else
        add_notdef_from_bindings
      end

      sorted_bindings.each do |binding|
        next if binding[:donor_gid].zero?

        # Skip bindings from the CBDT source — its glyphs are already added.
        next if cbdt && binding[:source].equal?(cbdt)

        glyph = binding[:source].glyph_for_gid(binding[:donor_gid])
        next unless glyph

        if @target.glyphs.key?(glyph.name)
          add_extra_unicode(glyph.name, binding[:codepoint])
        else
          copy_glyph_into(@target, name: glyph.name,
                                   source: binding[:source],
                                   donor_gid: binding[:donor_gid],
                                   codepoint: binding[:codepoint])
        end
      end
    end

    # Bindings sorted by codepoint (nil codepoints come last).
    def sorted_bindings
      @bindings.sort_by { |b| [b[:codepoint] || Float::INFINITY, b[:donor_gid]] }
    end

    def copy_glyph_into(target_font, name:, source:, donor_gid:, codepoint: nil)
      original = source.glyph_for_gid(donor_gid)
      return unless original

      copy = clone_glyph(original, name: name)
      copy.add_unicode(codepoint) if codepoint
      target_font.layers.default_layer.add(copy)
    end

    def add_extra_unicode(glyph_name, codepoint)
      return unless codepoint

      glyph = @target.glyph(glyph_name)
      glyph.add_unicode(codepoint) unless glyph.unicodes.include?(codepoint)
    end

    # Add .notdef at GID 0 from the first binding that references gid 0.
    # Falls back to a synthesized empty .notdef if none found.
    def add_notdef_from_bindings
      notdef_binding = @bindings.find { |b| b[:donor_gid].zero? }
      if notdef_binding
        copy_glyph_into(@target, name: ".notdef",
                                 source: notdef_binding[:source],
                                 donor_gid: 0)
      else
        @target.layers.default_layer.add(Ufo::Glyph.new(name: ".notdef"))
      end
    end

    # Add ALL glyphs from a CBDT source in source GID order. This
    # ensures the CBLC's GID references remain valid in the output
    # without rewriting the table. Each glyph gets a placeholder
    # (no contours) since the bitmap data is in CBDT, not glyf.
    def add_all_cbdt_glyphs(source)
      ufo = source.font.is_a?(Ufo::Font) ? source.font : nil
      if ufo
        ufo.glyphs.each_value { |g| @target.layers.default_layer.add(clone_glyph(g, name: g.name)) }
        return
      end

      # For loaded TTF/OTF sources, iterate via cmap to get glyph names.
      # CBDT fonts (like NotoColorEmoji) may have thousands of glyphs;
      # we add them all as placeholders.
      maxp = source.font.table("maxp")
      num_glyphs = maxp&.num_glyphs || 0
      cmap = source.font.table("cmap")
      mappings = cmap&.unicode_mappings || {}

      # Build gid → [codepoints] from cmap
      gid_cps = Hash.new { |h, k| h[k] = [] }
      mappings.each { |cp, gid| gid_cps[gid] << cp }

      num_glyphs.times do |gid|
        name = gid.zero? ? ".notdef" : "gid#{gid}"
        glyph = Ufo::Glyph.new(name: name)
        glyph.width = 0
        gid_cps[gid].each { |cp| glyph.add_unicode(cp) }
        @target.layers.default_layer.add(glyph)
      end
    end

    # Deep-copy a glyph with a new name. Used so multiple target
    # glyphs can share the same source outline without aliasing.
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
