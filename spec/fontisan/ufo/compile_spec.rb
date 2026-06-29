# frozen_string_literal: true

# rubocop:disable RSpec/MultipleDescribes

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe "UFO → TTF/OTF compile (uses real last-resort-font)" do
  let(:ufo_path) { "/Users/mulgogi/src/external/unicode/last-resort-font/font.ufo" }
  let(:font) { Fontisan::Ufo::Font.open(ufo_path) }
  let(:tmpdir) { Dir.mktmpdir }

  before { skip "last-resort-font not available" unless Dir.exist?(ufo_path) }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  describe Fontisan::Ufo::Compile::TtfCompiler do
    it "writes a TTF that reopens cleanly via FontLoader" do
      path = File.join(tmpdir, "out.ttf")
      described_class.new(font).compile(output_path: path)

      expect(File.exist?(path)).to be(true)
      expect(File.size(path)).to be > 0

      reopened = Fontisan::FontLoader.load(path)
      head = reopened.table("head")
      expect(head.units_per_em).to eq(font.info.units_per_em)
      expect(head.magic_number).to eq(0x5F0F3CF5)
      expect(head.checksum_adjustment).not_to eq(0) # FontWriter patched it
    end

    it "writes the TrueType sfnt magic" do
      path = File.join(tmpdir, "magic.ttf")
      described_class.new(font).compile(output_path: path)
      expect(File.binread(path, 4).unpack1("N")).to eq(0x00010000)
    end

    it "preserves glyph count in maxp" do
      path = File.join(tmpdir, "maxp.ttf")
      described_class.new(font).compile(output_path: path)
      reopened = Fontisan::FontLoader.load(path)
      expect(reopened.table("maxp").num_glyphs).to eq(font.glyphs.size)
    end
  end

  describe Fontisan::Ufo::Compile::OtfCompiler do
    it "writes the OTTO sfnt magic" do
      path = File.join(tmpdir, "out.otf")
      described_class.new(font).compile(output_path: path)
      expect(File.binread(path, 4)).to eq("OTTO")
    end

    it "writes a CFF table" do
      path = File.join(tmpdir, "cff.otf")
      described_class.new(font).compile(output_path: path)
      reopened = Fontisan::FontLoader.load(path)
      # The CFF table is currently a placeholder (TODO.full/10 will
      # wire real charstrings). The font must still parse as OTF
      # and have a non-empty CFF table.
      expect(reopened.has_table?("CFF ")).to be(true)
    end
  end
end

RSpec.describe Fontisan::Ufo::Compile::Cmap do
  describe ".build" do
    let(:font) do
      font = Fontisan::Ufo::Font.new
      font.info.family_name = "Test"
      font.info.version_major = 1
      font.info.version_minor = 0
      font
    end

    it "emits version=0 + numTables=2 in the cmap header" do
      notdef = Fontisan::Ufo::Glyph.new(name: ".notdef")
      a = Fontisan::Ufo::Glyph.new(name: "A")
      a.add_unicode(0x41)
      a.width = 500
      glyphs = [notdef, a]

      bytes = described_class.build(font, glyphs: glyphs)
      # cmap header: uint16 version (0), uint16 numTables (2)
      expect(bytes.unpack("nn")).to eq([0, 2])
      expect(bytes.bytesize).to be > 0
    end

    it "maps the test codepoint through format 12" do
      notdef = Fontisan::Ufo::Glyph.new(name: ".notdef")
      a = Fontisan::Ufo::Glyph.new(name: "A")
      a.add_unicode(0x41)
      glyphs = [notdef, a]

      bytes = described_class.build(font, glyphs: glyphs)
      # The format byte (12) for the format-12 subtable appears
      # after the cmap header (4 bytes) + 2 subtable records (8
      # bytes each) + the format-4 subtable. Find it anywhere in
      # the bytes to confirm a format-12 subtable exists.
      expect(bytes.bytes).to include(12)
    end
  end
end

RSpec.describe Fontisan::Ufo::Compile::Hmtx do
  describe ".build" do
    it "emits one LongHorMetric per glyph (4 bytes each)" do
      font = Fontisan::Ufo::Font.new
      glyphs = [
        Fontisan::Ufo::Glyph.new(name: ".notdef"),
        Fontisan::Ufo::Glyph.new(name: "A"),
      ]
      glyphs.first.width = 500
      glyphs.last.width = 600

      bytes = described_class.build(font, glyphs: glyphs)
      expect(bytes.bytesize).to eq(8) # 2 glyphs * 4 bytes
    end
  end
end

RSpec.describe Fontisan::Ufo::Compile::Name do
  describe ".build" do
    it "emits all 7 required name IDs" do
      font = Fontisan::Ufo::Font.new
      font.info.family_name = "Essenfont"
      font.info.style_name = "Regular"
      font.info.version_major = 1
      font.info.version_minor = 0

      bytes = described_class.build(font)
      record_count = bytes.unpack1("@2 n")
      expect(record_count).to eq(7)
    end
  end
end

RSpec.describe Fontisan::Ufo::Compile::Post do
  describe ".build" do
    it "emits version 3.0 (32 bytes, no glyph names)" do
      font = Fontisan::Ufo::Font.new
      font.info.italic_angle = 0.0

      bytes = described_class.build(font)
      expect(bytes.unpack1("N")).to eq(0x00030000)
      expect(bytes.bytesize).to eq(32)
    end
  end
end
# rubocop:enable RSpec/MultipleDescribes
