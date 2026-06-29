# frozen_string_literal: true

module Fontisan
  module Ufo
    # A single layer in a UFO source. A Layer holds a set of glyphs
    # keyed by name. The default layer is `public.default` per UFO 3.
    #
    # glyphs is mutated in place by Reader and Writer; the Layer does
    # not own serialization concerns.
    class Layer
      DEFAULT_NAME = "public.default"

      attr_reader :name, :glyphs

      def initialize(name = DEFAULT_NAME)
        @name = name
        @glyphs = {}
      end

      def [](glyph_name)
        @glyphs[glyph_name.to_s]
      end

      def add(glyph)
        @glyphs[glyph.name.to_s] = glyph
        glyph
      end

      def each(&)
        @glyphs.each_value(&)
      end

      def size
        @glyphs.size
      end
    end
  end
end
