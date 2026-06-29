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
    # @param path [String] output file path
    # @param format [Symbol] :ttf or :otf
    def write_to(path, format: :ttf)
      build_target_font
      compiler = compiler_for(format)
      compiler.new(@target).compile(output_path: path)
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
    def assign_gids_and_copy_glyphs
      # Always put .notdef at gid 0 first.
      notdef_binding = @bindings.find { |b| b[:donor_gid].zero? }
      if notdef_binding
        copy_glyph_into(@target, name: ".notdef",
                                 source: notdef_binding[:source],
                                 donor_gid: 0)
      else
        # Synthesize an empty .notdef
        @target.layers.default_layer.add(Ufo::Glyph.new(name: ".notdef"))
      end

      sorted_bindings.each do |binding|
        next if binding[:donor_gid].zero? # already handled

        glyph = binding[:source].glyph_for_gid(binding[:donor_gid])
        next unless glyph

        # If multiple codepoints map to the same glyph, only the first
        # binding creates the glyph; subsequent ones add unicode entries.
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
