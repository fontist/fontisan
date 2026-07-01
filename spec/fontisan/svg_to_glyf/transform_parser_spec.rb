# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg_to_glyf"

RSpec.describe Fontisan::SvgToGlyf::Geometry::TransformParser do
  let(:identity) { Fontisan::SvgToGlyf::Geometry::AffineTransform.identity }

  describe ".parse" do
    it "returns identity for nil" do
      expect(described_class.parse(nil)).to eq(identity)
    end

    it "returns identity for an empty string" do
      expect(described_class.parse("")).to eq(identity)
      expect(described_class.parse("   ")).to eq(identity)
    end

    it "parses translate with two args" do
      t = described_class.parse("translate(10, 20)")
      expect(t.apply(0, 0)).to eq([10.0, 20.0])
    end

    it "parses translate with one arg (ty defaults to 0)" do
      t = described_class.parse("translate(15)")
      expect(t.apply(0, 0)).to eq([15.0, 0.0])
    end

    it "parses scale with one arg (sy defaults to sx)" do
      t = described_class.parse("scale(2)")
      expect(t.apply(3, 5)).to eq([6.0, 10.0])
    end

    it "parses scale with two args" do
      t = described_class.parse("scale(2, 3)")
      expect(t.apply(3, 5)).to eq([6.0, 15.0])
    end

    it "parses rotate (degrees, around origin)" do
      t = described_class.parse("rotate(90)")
      x, y = t.apply(1, 0)
      expect(x).to be_within(0.0001).of(0.0)
      expect(y).to be_within(0.0001).of(1.0)
    end

    it "parses rotate around a point" do
      t = described_class.parse("rotate(180, 5, 5)")
      cx, cy = t.apply(5, 5)
      expect(cx).to be_within(0.0001).of(5.0)
      expect(cy).to be_within(0.0001).of(5.0)
      x, y = t.apply(6, 5)
      expect(x).to be_within(0.0001).of(4.0)
      expect(y).to be_within(0.0001).of(5.0)
    end

    it "parses matrix(a,b,c,d,e,f)" do
      t = described_class.parse("matrix(1, 0, 0, 1, 100, 200)")
      expect(t.apply(0, 0)).to eq([100.0, 200.0])
    end

    it "parses skewX" do
      t = described_class.parse("skewX(45)")
      x, y = t.apply(1, 0)
      expect(x).to be_within(0.0001).of(1.0)
      expect(y).to be_within(0.0001).of(0.0)
      x, = t.apply(0, 1)
      expect(x).to be_within(0.0001).of(1.0)
    end

    it "composes multiple functions left-to-right" do
      # scale(2) translate(10,0): point is first translated, then scaled
      t = described_class.parse("scale(2) translate(10, 0)")
      result = t.apply(5, 0)
      # translate: (5,0)→(15,0), then scale: →(30,0)
      expect(result).to eq([30.0, 0.0])
    end

    it "tolerates whitespace and comma variations" do
      t = described_class.parse("translate(  10  ,  20  )")
      expect(t.apply(0, 0)).to eq([10.0, 20.0])
    end

    it "raises on unknown function" do
      expect { described_class.parse("bogus(1, 2)") }
        .to raise_error(ArgumentError, /unknown SVG transform function/)
    end

    it "handles the real ucode fixture transform" do
      t = described_class.parse("scale(51.354062) translate(-12780.598814, -17391.128233)")
      # Path point (12780, 17391) → translate: (~0, ~0) → scale: (~0, ~0)
      result = t.apply(12780.598814, 17391.128233)
      expect(result[0]).to be_within(0.01).of(0.0)
      expect(result[1]).to be_within(0.01).of(0.0)
    end
  end
end
