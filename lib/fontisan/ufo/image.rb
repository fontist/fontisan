# frozen_string_literal: true

module Fontisan
  module Ufo
    # A background image anchored to a glyph (common in color fonts).
    class Image
      attr_reader :file_name, :transformation, :color

      def initialize(file_name:, transformation: nil, color: nil)
        @file_name = file_name.to_s
        @transformation = transformation
        @color = color
      end
    end
  end
end
