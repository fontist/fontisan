# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/font"

RSpec.describe Fontisan::Ufo::Font do
  describe "#initialize" do
    it "starts with default state" do
      font = described_class.new
      expect(font.family_name).to be_nil
      expect(font.info).to be_a(Fontisan::Ufo::Info)
      expect(font.layers.default_layer.name).to eq("public.default")
      expect(font.glyphs).to eq({})
      expect(font.ufo_version).to be_nil
    end
  end

  describe ".open (uses real last-resort-font as fixture)" do
    let(:ufo_path) { "/Users/mulgogi/src/external/unicode/last-resort-font/font.ufo" }

    before { skip "last-resort-font not available at #{ufo_path}" unless Dir.exist?(ufo_path) }

    it "reads fontinfo.plist correctly" do
      font = described_class.open(ufo_path)
      # last-resort-font/font.ufo is the High-Efficiency font
      expect(font.info.family_name).to eq("Last Resort High-Efficiency")
      expect(font.info.style_name).to eq("Regular")
      expect(font.info.units_per_em).to eq(2048)
    end

    it "reads metainfo.plist version" do
      font = described_class.open(ufo_path)
      # last-resort-font is a UFO 2 source (per metainfo.plist)
      expect(font.ufo_version).to eq(2)
    end

    it "populates the default layer with glyphs" do
      font = described_class.open(ufo_path)
      # last-resort-font has 381 glyphs
      expect(font.glyphs.size).to be > 0
      expect(font.glyph(".notdef")).not_to be_nil
    end

    it "reads advance widths from .glif" do
      font = described_class.open(ufo_path)
      expect(font.glyph(".notdef").width).to eq(1024.0)
    end
  end
end
