# frozen_string_literal: true

module Fontisan
  module SpecHelpers
    module BaselineOptimizerCases
      def optimizer_pattern(bytes, positions:, savings:, glyphs: positions.keys)
        Optimizers::PatternAnalyzer::Pattern.new(
          bytes, bytes.bytesize, glyphs, positions.values.sum(&:length), savings,
          positions, false
        )
      end
    end
  end
end
