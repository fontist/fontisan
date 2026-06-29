# frozen_string_literal: true

module Fontisan
  module Ufo
    # Per-glyph custom data from `glyphs/<glyph>.plist`. Each glyph
    # has its own plist file with arbitrary key/value data.
    class DataSet
      def initialize
        @data = {} # glyph_name => Hash<String, Object>
      end

      def [](glyph_name)
        @data[glyph_name.to_s] ||= {}
      end

      def keys
        @data.keys
      end
    end
  end
end
