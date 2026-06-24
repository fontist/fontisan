# frozen_string_literal: true

# Autoload hub for the Fontisan::Svg namespace.

module Fontisan
  module Svg
    autoload :FontFaceGenerator, "fontisan/svg/font_face_generator"
    autoload :FontGenerator, "fontisan/svg/font_generator"
    autoload :GlyphGenerator, "fontisan/svg/glyph_generator"
    autoload :ViewBoxCalculator, "fontisan/svg/view_box_calculator"
  end
end
