# frozen_string_literal: true

module Fontisan
  # Unified Font Object (UFO) v3 model + compile + convert pipeline.
  #
  # A UFO is a directory-based font source format. Each UFO is a
  # human-readable, human-editable collection of plists + GLIF XML
  # files. fontisan can:
  #
  #   - Read any UFO source into a typed model (this namespace).
  #   - Edit the model programmatically.
  #   - Compile to a binary font (TTF, OTF, …) via
  #     Fontisan::Ufo::Compile::*
  #   - Convert any binary font fontisan can read INTO a UFO source.
  #   - Stitch glyphs from multiple sources into a new font via
  #     Fontisan::Stitcher.
  #
  # Reference: https://unifiedfontobject.org
  module Ufo
    autoload :Font,        "fontisan/ufo/font"
    autoload :Info,        "fontisan/ufo/info"
    autoload :Layer,       "fontisan/ufo/layer"
    autoload :LayerSet,    "fontisan/ufo/layer_set"
    autoload :Glyph,       "fontisan/ufo/glyph"
    autoload :Contour,     "fontisan/ufo/contour"
    autoload :Point,       "fontisan/ufo/point"
    autoload :Component,   "fontisan/ufo/component"
    autoload :Anchor,      "fontisan/ufo/anchor"
    autoload :Guideline,   "fontisan/ufo/guideline"
    autoload :Image,       "fontisan/ufo/image"
    autoload :Transformation, "fontisan/ufo/transformation"
    autoload :Kerning,     "fontisan/ufo/kerning"
    autoload :Features,    "fontisan/ufo/features"
    autoload :Lib,         "fontisan/ufo/lib"
    autoload :DataSet,     "fontisan/ufo/data_set"
    autoload :ImageSet,    "fontisan/ufo/image_set"
    autoload :Plist,       "fontisan/ufo/plist"
    autoload :Reader,      "fontisan/ufo/reader"
    autoload :Writer,      "fontisan/ufo/writer"
  end
end
