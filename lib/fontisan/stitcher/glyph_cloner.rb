# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Deep-clone helper for UFO glyphs. Stateless — every call returns
    # a fresh +Ufo::Glyph+ with copied contours, components, anchors,
    # and guidelines plus the original's width/height.
    #
    # Extracted as a collaborator so +GlyphCopier+ and +CbdtPropagator+
    # share one implementation of the clone algorithm. Both previously
    # defined identical +clone_glyph+ / +clone_contour+ private methods
    # — a DRY violation that risked drifting apart as the glyph model
    # gained fields.
    module GlyphCloner
      # @param original [Ufo::Glyph] glyph to copy
      # @param name [String, nil] name for the copy; defaults to the
      #   original's name (used by callers that have already allocated
      #   a unique name via +UniqueGlyphName+).
      # @return [Ufo::Glyph] a fresh glyph with the original's geometry
      #   and metrics, sharing no mutable state with it.
      def self.clone(original, name: nil)
        copy = Ufo::Glyph.new(name: name || original.name)
        copy.width = original.width
        copy.height = original.height
        original.contours.each { |c| copy.add_contour(clone_contour(c)) }
        original.components.each { |c| copy.add_component(c) }
        original.anchors.each { |a| copy.add_anchor(a) }
        original.guidelines.each { |g| copy.add_guideline(g) }
        copy
      end

      def self.clone_contour(original)
        points = original.points.map do |p|
          Ufo::Point.new(x: p.x, y: p.y, type: p.type, smooth: p.smooth)
        end
        Ufo::Contour.new(points)
      end
      private_class_method :clone_contour
    end
  end
end
