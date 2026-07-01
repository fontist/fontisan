# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Registry mapping glyph signatures to canonical glyph names in
    # the target font. Enables signature-based deduplication: when
    # two bindings produce glyphs with identical outlines, they share
    # one gid and the duplicate's codepoint is redirected to the
    # canonical glyph.
    #
    # Replaces the Stitcher's previous name-based dedup with
    # outline-based dedup. This merges visually identical glyphs
    # from different donors even when their names differ, reducing
    # the glyph count below the TrueType 65,535 cap.
    class Deduplicator
      attr_reader :signatures

      def initialize
        @signatures = {}
      end

      # Record that `glyph` maps to `canonical_name` in the target.
      # @param glyph [Fontisan::Ufo::Glyph]
      # @param canonical_name [String] the name under which the glyph
      #   was added to the target font
      def register(glyph, canonical_name)
        @signatures[GlyphSignature.for(glyph)] = canonical_name
      end

      # @param glyph [Fontisan::Ufo::Glyph]
      # @return [String, nil] the canonical name if an identical
      #   glyph was already registered, nil otherwise
      def find(glyph)
        @signatures[GlyphSignature.for(glyph)]
      end

      # @return [Integer] number of unique signatures registered
      def size
        @signatures.size
      end

      def empty?
        @signatures.empty?
      end
    end
  end
end
