# frozen_string_literal: true

module Fontisan
  module Ufo
    # A mark-attachment anchor on a glyph (used in GSUB/GPOS).
    class Anchor
      attr_reader :x, :y, :name, :identifier

      def initialize(x:, y:, name: nil, identifier: nil)
        @x = x
        @y = y
        @name = name
        @identifier = identifier
      end
    end
  end
end
