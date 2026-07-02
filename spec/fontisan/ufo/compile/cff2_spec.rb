# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe "CFF2 table builder and Otf2Compiler" do
  let(:font) do
    f = Fontisan::Ufo::Font.new
    f.info.family_name = "Test"
    f.info.units_per_em = 1000
    f.glyphs[".notdef"] = Fontisan::Ufo::Glyph.new(name: ".notdef")

    a = Fontisan::Ufo::Glyph.new(name: "A")
    a.add_unicode(0x41)
    a.width = 600
    a.add_contour(Fontisan::Ufo::Contour.new([
                                               Fontisan::Ufo::Point.new(x: 100, y: 0, type: "line"),
                                               Fontisan::Ufo::Point.new(x: 100, y: 100, type: "offcurve"),
                                               Fontisan::Ufo::Point.new(x: 500, y: 100, type: "offcurve"),
                                               Fontisan::Ufo::Point.new(x: 500, y: 0, type: "curve"),
                                             ]))
    f.glyphs["A"] = a
    f
  end

  describe Fontisan::Ufo::Compile::Cff2 do
    it "produces a non-empty binary string" do
      bytes = described_class.build(font, glyphs: font.glyphs.values)
      expect(bytes).to be_a(String)
      expect(bytes.bytesize).to be > 0
    end

    it "starts with the CFF2 header (major=2, minor=0, headerSize=5)" do
      bytes = described_class.build(font, glyphs: font.glyphs.values)
      major, minor, header_size, = bytes.unpack("CCCn")
      expect(major).to eq(2)
      expect(minor).to eq(0)
      expect(header_size).to eq(5)
    end

    it "contains a non-empty CharStrings INDEX" do
      bytes = described_class.build(font, glyphs: font.glyphs.values)
      expect(bytes.bytesize).to be > 20
    end
  end

  describe "Otf2Compiler end-to-end" do
    it "compiles a UFO font to OTF (CFF2) and reopens it" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.otf")
        Fontisan::Ufo::Compile::Otf2Compiler.new(font).compile(output_path: path)

        expect(File.exist?(path)).to be(true)
        expect(File.binread(path, 4)).to eq("OTTO")

        reopened = Fontisan::FontLoader.load(path)
        expect(reopened.has_table?("CFF2")).to be(true)
        expect(reopened.table("maxp").num_glyphs).to eq(2)
        expect(reopened.table("cmap").unicode_mappings.key?(0x41)).to be(true)
      end
    end

    it "supports Stitcher write_to with format: :otf2" do
      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:src, font)
      stitcher.include_notdef(from: :src, into: :main)
      stitcher.include_codepoints([0x41], from: :src, into: :main)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "stitched.otf")
        stitcher.write_to(path, format: :otf2, subfont: :main)

        reopened = Fontisan::FontLoader.load(path)
        expect(reopened.has_table?("CFF2")).to be(true)
        expect(reopened.table("cmap").unicode_mappings.key?(0x41)).to be(true)
      end
    end
  end
end
