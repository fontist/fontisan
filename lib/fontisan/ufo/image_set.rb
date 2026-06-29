# frozen_string_literal: true

module Fontisan
  module Ufo
    # Background images from `images/<layer>/...`. MVP stores nothing;
    # a real implementation lands with TODO 02 (glyph model + images).
    class ImageSet
      attr_reader :images

      def initialize
        @images = {}
      end

      def empty?
        @images.empty?
      end
    end
  end
end
