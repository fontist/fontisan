# frozen_string_literal: true

module Fontisan
  module FontBuilder
    GlyphEntry = Struct.new(:outline, :metrics, keyword_init: true) do
      def initialize(outline: Outline.new, metrics: Metrics.new)
        super
      end
    end
  end
end
