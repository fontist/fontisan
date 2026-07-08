# frozen_string: true

require "spec_helper"
require "fontisan/ufo/font"
require "fontisan/ufo/glyph"
require "fontisan/ufo/compile/ttf_compiler"
require "fontisan/ufo/compile/otf_compiler"
require "fontisan/ufo/compile/otf2_compiler"

RSpec.describe Fontisan::Ufo::Compile::BaseCompiler do
  # Direct test of the .notdef-injection contract via the concrete
  # compiler subclasses (TtfCompiler is the production path that
  # exposed the bug; Otf/Otf2 share the same BaseCompiler helper).
  describe ".notdef at GID 0 (OpenType requirement)" do
    let(:font_without_notdef) do
      font = Fontisan::Ufo::Font.new
      glyph = Fontisan::Ufo::Glyph.new(name: "u1F200")
      glyph.add_unicode(0x1F200)
      font.layers.default_layer.add(glyph)
      font
    end

    let(:font_with_notdef_first) do
      font = Fontisan::Ufo::Font.new
      font.layers.default_layer.add(Fontisan::Ufo::Glyph.new(name: ".notdef"))
      real = Fontisan::Ufo::Glyph.new(name: "u0041")
      real.add_unicode(0x41)
      font.layers.default_layer.add(real)
      font
    end

    # P0 regression case: .notdef exists but is NOT first. Without the
    # fix, the helper would inject a SECOND .notdef, producing two
    # .notdef glyphs and violating OpenType.
    let(:font_with_notdef_last) do
      font = Fontisan::Ufo::Font.new
      real = Fontisan::Ufo::Glyph.new(name: "u0041")
      real.add_unicode(0x41)
      font.layers.default_layer.add(real)
      font.layers.default_layer.add(Fontisan::Ufo::Glyph.new(name: ".notdef"))
      font
    end

    shared_examples "injects notdef at GID 0" do |compiler_class, extension|
      it "inserts an empty .notdef when the UFO doesn't declare one" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "test#{extension}")
          compiler_class.new(font_without_notdef).compile(output_path: path)

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
    end

    shared_examples "preserves explicit notdef" do |compiler_class, extension|
      it "preserves an explicitly declared .notdef at GID 0" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "test#{extension}")
          compiler_class.new(font_with_notdef_first).compile(output_path: path)

          loaded = Fontisan::FontLoader.load(path)
          cmap = loaded.table("cmap").unicode_mappings
          expect(cmap.key?(0x41)).to be(true)
          expect(loaded.table("maxp").num_glyphs).to eq(2)
        end
      end
    end

    shared_examples "moves existing notdef to GID 0 without duplicating" do |compiler_class, extension|
      it "moves an existing .notdef to GID 0 instead of injecting a duplicate" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "test#{extension}")
          compiler_class.new(font_with_notdef_last).compile(output_path: path)

          loaded = Fontisan::FontLoader.load(path)
          # If the helper duplicated .notdef, numGlyphs would be 3
          # (.notdef injected + u0041 + .notdef existing). The contract
          # is exactly 2 glyphs with .notdef at GID 0.
          expect(loaded.table("maxp").num_glyphs).to eq(2),
                                                     "duplicate .notdef injected; expected 2 glyphs, " \
                                                     "got #{loaded.table('maxp').num_glyphs}"
        end
      end
    end

    # Per-compiler coverage. Each shared example runs against all three
    # concrete compilers so a regression in any one is caught.
    describe Fontisan::Ufo::Compile::TtfCompiler do
      it_behaves_like "injects notdef at GID 0", described_class, ".ttf"
      it_behaves_like "preserves explicit notdef", described_class, ".ttf"
      it_behaves_like "moves existing notdef to GID 0 without duplicating",
                      described_class, ".ttf"
    end

    describe Fontisan::Ufo::Compile::OtfCompiler do
      it_behaves_like "injects notdef at GID 0", described_class, ".otf"
      it_behaves_like "preserves explicit notdef", described_class, ".otf"
      it_behaves_like "moves existing notdef to GID 0 without duplicating",
                      described_class, ".otf"
    end

    describe Fontisan::Ufo::Compile::Otf2Compiler do
      it_behaves_like "injects notdef at GID 0", described_class, ".otf"
      it_behaves_like "preserves explicit notdef", described_class, ".otf"
      it_behaves_like "moves existing notdef to GID 0 without duplicating",
                      described_class, ".otf"
    end

    describe "empty UFO" do
      it "compiles without raising (no injection needed for empty source)" do
        font = Fontisan::Ufo::Font.new
        expect do
          Dir.mktmpdir do |dir|
            path = File.join(dir, "test.ttf")
            Fontisan::Ufo::Compile::TtfCompiler.new(font).compile(output_path: path)
          end
        end.not_to raise_error
      end
    end
  end
end
