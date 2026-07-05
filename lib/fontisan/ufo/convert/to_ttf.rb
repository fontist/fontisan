# frozen_string_literal: true

module Fontisan
  module Ufo
    module Convert
      # Thin facade over Compile::TtfCompiler. Exists so callers
      # have a uniform +Ufo::Convert::To{Format}.convert+ API across
      # all output formats, and so the CLI's format dispatch can be
      # a hash lookup instead of a case statement.
      module ToTtf
        # @param ufo [Fontisan::Ufo::Font]
        # @param output_path [String]
        # @return [String] the output_path
        def self.convert(ufo, output_path:)
          Compile::TtfCompiler.new(ufo).compile(output_path: output_path)
          output_path
        end
      end
    end
  end
end
