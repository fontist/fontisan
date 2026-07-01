# frozen_string_literal: true

require "digest"

module Fontisan
  class Stitcher
    # Stateless signature computation for a Ufo::Glyph's visual identity.
    #
    # Two glyphs with the same signature are visually interchangeable
    # and can share a gid in the output font. The signature captures
    # advance width, every contour's points (x, y, type), and every
    # component reference (base glyph + transform presence).
    #
    # Used by Deduplicator to merge identical outlines from different
    # donors, reducing the glyph count below the TrueType 65,535 cap.
    module GlyphSignature
      # @param glyph [Fontisan::Ufo::Glyph]
      # @return [String] SHA-256 hex digest of the glyph's outline identity
      def self.for(glyph)
        Digest::SHA256.hexdigest(canonical_representation(glyph))
      end

      # Build a deterministic string capturing the glyph's visual identity.
      # The representation is ordered and normalized so that semantically
      # identical glyphs produce byte-identical strings.
      #
      # @param glyph [Fontisan::Ufo::Glyph]
      # @return [String]
      def self.canonical_representation(glyph)
        io = +""
        io << "w:#{glyph.width.to_i};"

        glyph.contours.each_with_index do |contour, ci|
          io << "c#{ci}:"
          contour.points.each do |pt|
            io << "#{pt.x.to_i},#{pt.y.to_i},#{pt.type};"
          end
        end

        glyph.components.each_with_index do |comp, i|
          io << "comp#{i}:#{comp.base_glyph}"
          io << ":t" if comp.transformation
        end

        io
      end

      private_class_method :canonical_representation
    end
  end
end
