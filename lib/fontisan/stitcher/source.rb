# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Wraps a source font (UFO or loaded TTF/OTF) behind a single
    # extraction API used by the selectors.
    #
    # For UFO sources, glyphs are accessed by name directly. For TTF
    # sources, per-glyph extraction requires reading the BinData glyf
    # table — TODO.full/14 will add full TTF→UFO glyph conversion.
    # Until then, TTF sources raise on glyph extraction.
    class Source
      attr_reader :font

      def initialize(font)
        @font = font
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
      # @param gid [Integer]
      # @return [Fontisan::Ufo::Glyph, nil]
      def glyph_for_gid(gid)
        case @font
        when Fontisan::Ufo::Font then ufo_glyph_at(gid)
        else raise NotImplementedError,
                   "TTF/OTF per-glyph extraction lands in TODO.full/14; " \
                   "convert the source to UFO first via Fontisan::Ufo::Cli#convert"
        end
      end

      private

      # UFO lookup: walk glyphs, find the one whose unicodes includes
      # this codepoint. (UFO doesn't have a built-in cmap.)
      def ufo_gid_for(codepoint)
        @font.glyphs.each_with_index do |(_name, glyph), _index|
          return gid_of_glyph(glyph) if glyph.unicodes.include?(codepoint)
        end
        nil
      end

      # UFO gid is the index in the layer's glyph order. The first
      # glyph in @font.glyphs is gid 0.
      def gid_of_glyph(glyph)
        names = @font.glyphs.keys
        names.index(glyph.name)
      end

      def ufo_glyph_at(gid)
        names = @font.glyphs.keys
        name = names[gid]
        return nil unless name

        @font.glyph(name)
      end

      def bin_data_gid_for(codepoint)
        cmap = @font.table("cmap")
        return nil unless cmap

        cmap.unicode_mappings[codepoint]
      end
    end
  end
end
