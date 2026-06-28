# frozen_string_literal: true

module Fontisan
  # High-level font-assembler API. Builds a new font from typed inputs
  # (cmap, per-glyph outlines, name records) and writes the result via
  # the existing low-level {Fontisan::FontWriter} class.
  #
  # Pairs with Fontisan::Font.open:
  #
  #   Fontisan::Font.open(path)         → read an existing font
  #   Fontisan::FontBuilder.new         → build a new font from scratch
  #
  # Architecture:
  #
  #   FontBuilder (orchestrator, public API)
  #     holds a FontModel (in-memory font representation)
  #     delegates per-table serialization to Tables::*
  #
  #   FontModel — typed in-memory model (cmap, glyphs, names, etc.)
  #     no serialization logic; pure data
  #
  #   Tables::* (one class per OpenType table)
  #     each knows its own byte layout
  #     adding a new table = adding a new class (OCP)
  #
  # All typed structures use Struct with keyword_init. No `:hash`
  # lutaml attributes anywhere.
  module FontBuilder
    autoload :FontModel, "fontisan/font_builder/font_model"
    autoload :Outline, "fontisan/font_builder/outline"
    autoload :Point, "fontisan/font_builder/point"
    autoload :NameRecord, "fontisan/font_builder/name_record"
    autoload :Metrics, "fontisan/font_builder/metrics"
    autoload :GlyphEntry, "fontisan/font_builder/glyph_entry"
    autoload :Main, "fontisan/font_builder/main"
    autoload :Tables, "fontisan/font_builder/tables"
  end
end
