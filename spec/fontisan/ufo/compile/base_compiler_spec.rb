# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/font"
require "fontisan/ufo/glyph"
require "fontisan/ufo/compile/ttf_compiler"

RSpec.describe Fontisan::Ufo::Compile::BaseCompiler do
  # Direct test of the .notdef-injection contract via the TtfCompiler
  # subclass, which is the production path that exposed the bug.
  describe ".notdef at GID 0 (OpenType requirement)" do
    it "inserts an empty .notdef when the UFO doesn't declare one" do
      font = Fontisan::Ufo::Font.new
      # Add a glyph whose name sorts lexically BEFORE ".notdef" so that
      # without the fix it would land at GID 0 and be silently dropped
      # from the cmap by parsers that treat GID 0 as .notdef.
      glyph = Fontisan::Ufo::Glyph.new(name: "u1F200")
      glyph.add_unicode(0x1F200)
      font.layers.default_layer.add(glyph)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.ttf")
        Fontisan::Ufo::Compile::TtfCompiler.new(font).compile(output_path: path)

        loaded = Fontisan::FontLoader.load(path)
        cmap = loaded.table("cmap").unicode_mappings

        # U+1F200 must survive the round-trip. Without .notdef injection
        # the glyph would land at GID 0 and the cmap parser would drop it.
        expect(cmap.key?(0x1F200)).to be(true),
                                       "U+1F200 must remain in cmap after compile; " \
                                       "missing .notdef at GID 0 caused it to be silently dropped"
        expect(loaded.table("maxp").num_glyphs).to eq(2) # .notdef + u1F200
      end
    end

    it "preserves an explicitly declared .notdef at GID 0" do
      font = Fontisan::Ufo::Font.new
      font.layers.default_layer.add(Fontisan::Ufo::Glyph.new(name: ".notdef"))
      real = Fontisan::Ufo::Glyph.new(name: "u0041")
      real.add_unicode(0x41)
      font.layers.default_layer.add(real)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.ttf")
        Fontisan::Ufo::Compile::TtfCompiler.new(font).compile(output_path: path)

        loaded = Fontisan::FontLoader.load(path)
        cmap = loaded.table("cmap").unicode_mappings
        expect(cmap.key?(0x41)).to be(true)
        expect(loaded.table("maxp").num_glyphs).to eq(2)
      end
    end
  end
end
