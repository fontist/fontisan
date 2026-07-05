# frozen_string_literal: true

module Fontisan
  module Ufo
    module Convert
      # Thin facade over Compile::OtfCompiler (CFF1 outlines).
      module ToOtf
        # @param ufo [Fontisan::Ufo::Font]
        # @param output_path [String]
        # @return [String] the output_path
        def self.convert(ufo, output_path:)
          Compile::OtfCompiler.new(ufo).compile(output_path: output_path)
          output_path
        end
      end
    end
  end
end
