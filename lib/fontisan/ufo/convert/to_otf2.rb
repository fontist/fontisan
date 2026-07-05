# frozen_string_literal: true

module Fontisan
  module Ufo
    module Convert
      # Thin facade over Compile::Otf2Compiler (CFF2 outlines, used
      # for variable OTF). CFF2 still inherits the 65,535-glyph cap
      # because maxp.numGlyphs is uint16 — see Stitcher::GlyphLimit.
      module ToOtf2
        # @param ufo [Fontisan::Ufo::Font]
        # @param output_path [String]
        # @return [String] the output_path
        def self.convert(ufo, output_path:)
          Compile::Otf2Compiler.new(ufo).compile(output_path: output_path)
          output_path
        end
      end
    end
  end
end
