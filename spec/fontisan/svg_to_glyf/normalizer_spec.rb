# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg_to_glyf"

RSpec.describe Fontisan::SvgToGlyf::Geometry::Normalizer do
  let(:affine) { Fontisan::SvgToGlyf::Geometry::AffineTransform }

  describe "#matrix" do
    it "maps SVG top-left (0,0) to font top (0, upm)" do
      n = described_class.new(viewbox_width: 1000, viewbox_height: 1000, upm: 1000)
      expect(n.matrix.apply(0, 0)).to eq([0.0, 1000.0])
    end

    it "maps SVG bottom-left (0,H) to font baseline-left (0, 0)" do
      n = described_class.new(viewbox_width: 1000, viewbox_height: 1000, upm: 1000)
      expect(n.matrix.apply(0, 1000)).to eq([0.0, 0.0])
    end

    it "maps SVG bottom-right (W,H) to font baseline-right (upm, 0)" do
      n = described_class.new(viewbox_width: 1000, viewbox_height: 1000, upm: 1000)
      expect(n.matrix.apply(1000, 1000)).to eq([1000.0, 0.0])
    end

    it "scales non-square viewBox to square UPM" do
      n = described_class.new(viewbox_width: 500, viewbox_height: 1000, upm: 1000)
      x, y = n.matrix.apply(250, 500)
      expect(x).to eq(500.0)
      expect(y).to eq(500.0)
    end

    it "scales a 1000×1000 viewBox up to UPM=2048" do
      n = described_class.new(viewbox_width: 1000, viewbox_height: 1000, upm: 2048)
      x, y = n.matrix.apply(500, 500)
      expect(x).to be_within(0.001).of(1024.0)
      expect(y).to be_within(0.001).of(1024.0)
    end
  end

  describe "#final_transform" do
    it "returns just the normalization when no group transform is given" do
      n = described_class.new(viewbox_width: 1000, viewbox_height: 1000, upm: 1000)
      expect(n.final_transform).to eq(n.matrix)
    end

    it "composes with a group transform" do
      n = described_class.new(viewbox_width: 1000, viewbox_height: 1000, upm: 1000)
      group = affine.scale(2)
      final = n.final_transform(group)

      # A path point (0,0) → group scale (0,0) → normalize (0, upm)
      expect(final.apply(0, 0)).to eq([0.0, 1000.0])
      # A path point (100, 0) → group scale (200, 0) → normalize (200, upm)
      expect(final.apply(100, 0)).to eq([200.0, 1000.0])
    end
  end
end
