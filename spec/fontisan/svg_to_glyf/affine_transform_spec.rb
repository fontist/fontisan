# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg_to_glyf"

RSpec.describe Fontisan::SvgToGlyf::Geometry::AffineTransform do
  let(:identity) { described_class.identity }

  describe ".identity" do
    it "returns a no-op transform" do
      expect(identity.apply(100, 200)).to eq([100.0, 200.0])
    end

    it "reports itself as identity" do
      expect(identity.identity?).to be(true)
    end
  end

  describe ".translate" do
    it "shifts points by (tx, ty)" do
      t = described_class.translate(10, 20)
      expect(t.apply(5, 5)).to eq([15.0, 25.0])
    end

    it "defaults ty to 0" do
      t = described_class.translate(10)
      expect(t.apply(5, 5)).to eq([15.0, 5.0])
    end
  end

  describe ".scale" do
    it "scales both axes by the same factor when sy is omitted" do
      t = described_class.scale(3)
      expect(t.apply(2, 4)).to eq([6.0, 12.0])
    end

    it "scales axes independently when both are given" do
      t = described_class.scale(2, 0.5)
      expect(t.apply(4, 4)).to eq([8.0, 2.0])
    end
  end

  describe ".rotate_degrees" do
    it "rotates 90 degrees counter-clockwise around origin" do
      t = described_class.rotate_degrees(90)
      x, y = t.apply(1, 0)
      expect(x).to be_within(0.0001).of(0.0)
      expect(y).to be_within(0.0001).of(1.0)
    end
  end

  describe ".flip_y" do
    it "reflects points across the given horizontal axis" do
      t = described_class.flip_y(500)
      expect(t.apply(100, 400)).to eq([100.0, 600.0])
      expect(t.apply(100, 500)).to eq([100.0, 500.0])
      expect(t.apply(100, 600)).to eq([100.0, 400.0])
    end
  end

  describe "#compose" do
    it "applies the other transform first, then self" do
      scale = described_class.scale(2)
      translate = described_class.translate(10, 0)
      combined = translate.compose(scale)

      # scale first: (5, 0) → (10, 0), then translate: → (20, 0)
      expect(combined.apply(5, 0)).to eq([20.0, 0.0])
    end

    it "is not commutative" do
      scale = described_class.scale(2)
      translate = described_class.translate(10, 0)

      ab = scale.compose(translate).apply(5, 0)
      ba = translate.compose(scale).apply(5, 0)
      expect(ab).not_to eq(ba)
    end

    it "returns identity when composing with identity" do
      t = described_class.translate(5, 5)
      expect(t.compose(identity)).to eq(t)
      expect(identity.compose(t)).to eq(t)
    end
  end

  describe "#==" do
    it "compares component-by-component" do
      expect(described_class.translate(1, 2)).to eq(described_class.translate(1.0, 2.0))
      expect(described_class.translate(1, 2)).not_to eq(described_class.translate(1, 3))
    end
  end
end
