# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/transformation"

RSpec.describe Fontisan::Ufo::Transformation do
  describe "#apply" do
    it "returns the input unchanged for identity" do
      t = described_class.new
      expect(t.apply(50, 100)).to eq([50.0, 100.0])
    end

    it "translates by (e, f)" do
      t = described_class.new(e: 10, f: 20)
      expect(t.apply(5, 5)).to eq([15.0, 25.0])
    end

    it "scales by a, d" do
      t = described_class.new(a: 3, d: 4)
      expect(t.apply(2, 5)).to eq([6.0, 20.0])
    end

    it "rotates 90° counter-clockwise" do
      # a=0, b=1, c=-1, d=0 → (x, y) → (-y, x)
      t = described_class.new(a: 0, b: 1, c: -1, d: 0)
      expect(t.apply(1, 0)).to eq([0.0, 1.0])
      expect(t.apply(0, 1)).to eq([-1.0, 0.0])
    end

    it "coerces integer inputs to float" do
      t = described_class.new(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)
      expect(t.apply(1, 1)).to eq([1.0, 1.0])
    end
  end
end
