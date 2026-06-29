# frozen_string_literal: true

module Fontisan
  module Ufo
    # A glyph in a UFO source. Holds contours, components, anchors,
    # guidelines, images, unicode codepoints, advance width/height,
    # and a custom-data bag (`lib`).
    #
    # The `.glif` XML format has multiple revisions (1, 2, 3); Reader
    # accepts all of them. UFO 3 uses format 2 or 3.
    class Glyph
      attr_accessor :width, :height, :note
      attr_reader :name, :unicodes, :contours, :components, :anchors, :guidelines, :images, :lib

      def initialize(name:)
        @name = name.to_s
        @unicodes = []
        @width = 0.0
        @height = 0.0
        @contours = []
        @components = []
        @anchors = []
        @guidelines = []
        @images = []
        @note = nil
        @lib = Lib.new
      end

      def add_unicode(codepoint)
        @unicodes << codepoint.to_i
      end

      # @return [BoundingBox, nil] the axis-aligned bounding box of
      #   the contours, or nil if the glyph has no contours.
      def bbox
        return nil if @contours.empty?

        xs = @contours.flat_map { |c| c.points.map(&:x) }
        ys = @contours.flat_map { |c| c.points.map(&:y) }
        BoundingBox.new(x_min: xs.min, y_min: ys.min, x_max: xs.max, y_max: ys.max)
      end

      # Plain-data bounding box (used by glyph bbox computation; not a
      # full OpenType table).
      BoundingBox = Struct.new(:x_min, :y_min, :x_max, :y_max, keyword_init: true)
    end
  end
end
