# frozen_string_literal: true

module Fontisan
  module Ufo
    # A composite-glyph reference: this glyph draws by transforming
    # another glyph. Used in UFO 3 composites; often the same shape as
    # the OpenType composite-glyph flag set.
    class Component
      attr_reader :base_glyph, :transformation, :identifier

      def initialize(base_glyph:, transformation: nil, identifier: nil)
        @base_glyph = base_glyph.to_s
        @transformation = transformation # Fontisan::Ufo::Transformation or nil
        @identifier = identifier
      end
    end
  end
end
