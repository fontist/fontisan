# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Wraps a source font (UFO or loaded TTF/OTF) behind a single
    # extraction API used by the selectors.
    #
    # For UFO sources, glyphs are accessed by name directly. For TTF
    # or OTF sources, the source is lazily converted to a UFO::Font
    # via Ufo::Convert::FromBinData on first glyph access, then cached.
    # This is O(n) in donor glyph count but amortized across all
    # codepoint extractions from that donor.
    class Source
      attr_reader :font

      def initialize(font)
        @font = font
        @ufo_cache = nil
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
        else converted_ufo_glyph_at(gid)
        end
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

      # ---------- TTF/OTF source ----------

      def bin_data_gid_for(codepoint)
        cmap = @font.table("cmap")
        return nil unless cmap

        cmap.unicode_mappings[codepoint]
      end

      # Lazily convert the loaded TTF/OTF to a UFO::Font, then
      # extract glyphs from the cached UFO model.
      def converted_ufo
        return @ufo_cache if @ufo_cache

        @ufo_cache = Fontisan::Ufo::Convert::FromBinData.convert(@font)
      end

      def converted_ufo_glyph_at(gid)
        ufo = converted_ufo
        names = ufo.glyphs.keys
        name = names[gid]
        return nil unless name

        ufo.glyph(name)
      end
    end
  end
end