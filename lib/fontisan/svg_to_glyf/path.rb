# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    # SVG path parsing: tokenize the `d` attribute and produce typed
    # Command value objects ready for contour assembly.
    module Path
      autoload :Command, "fontisan/svg_to_glyf/path/command"
      autoload :Parser, "fontisan/svg_to_glyf/path/parser"
      autoload :State, "fontisan/svg_to_glyf/path/state"
      autoload :ContourBuilder, "fontisan/svg_to_glyf/path/contour_builder"
    end
  end
end
