# frozen_string_literal: true

module Fontisan
  module Ufo
    # A Kerning pairs table parsed from `kerning.plist`. Pairs are
    # stored as `"<left> <right>" => float`, matching the file format.
    # Group pair keys (`"<left_group> <right_group>"`) are stored verbatim.
    class Kerning
      attr_reader :pairs

      def initialize(values = {})
        @pairs = values
      end

      def [](pair_key)
        @pairs[pair_key.to_s]
      end

      def []=(pair_key, value)
        @pairs[pair_key.to_s] = value
      end

      def empty?
        @pairs.empty?
      end

      def to_plist
        @pairs
      end
    end
  end
end
