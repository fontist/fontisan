# frozen_string_literal: true

module Fontisan
  module FontBuilder
    Metrics = Struct.new(:advance_width, :left_side_bearing, keyword_init: true) do
      def initialize(advance_width: 0, left_side_bearing: 0)
        super
      end
    end
  end
end
