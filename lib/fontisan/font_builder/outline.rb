# frozen_string_literal: true

require "fontisan/font_builder/point"

module Fontisan
  module FontBuilder
    # A glyph outline: one or more contours, each a sequence of Points,
    # plus optional hinting instructions.
    #
    # For composite glyphs (referencing other glyphs by GID), the
    # contours array is empty and +components+ carries the references.
    # Most glyphs are simple (one contour, closed).
    Outline = Struct.new(:contours, :instructions, :components, keyword_init: true) do
      def initialize(contours: [], instructions: nil, components: [])
        super
      end

      def composite?
        !components.empty?
      end

      def point_count
        contours.sum(&:length)
      end
    end
  end
end
