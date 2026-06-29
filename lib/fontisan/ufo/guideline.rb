# frozen_string_literal: true

module Fontisan
  module Ufo
    # A helper guideline on a glyph. Editor-only; not compiled into
    # the final font.
    class Guideline
      attr_reader :x, :y, :angle, :name, :identifier

      def initialize(x:, y:, angle: nil, name: nil, identifier: nil)
        @x = x
        @y = y
        @angle = angle
        @name = name
        @identifier = identifier
      end
    end
  end
end
