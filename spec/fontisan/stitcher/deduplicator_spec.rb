# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"

RSpec.describe Fontisan::Stitcher::Deduplicator do
  let(:ufo) { Fontisan::Ufo }

  def make_glyph(name, width: 500, points: [[0, 0, "line"], [100, 0, "line"]])
    g = ufo::Glyph.new(name: name)
    g.width = width
    g.add_contour(ufo::Contour.new(points.map { |x, y, t| ufo::Point.new(x: x, y: y, type: t) }))
    g
  end

  describe "#register and #find" do
    it "returns nil for an unregistered glyph" do
      dedup = described_class.new
      expect(dedup.find(make_glyph("A"))).to be_nil
    end

    it "returns the canonical name after registering" do
      dedup = described_class.new
      glyph = make_glyph("A")
      dedup.register(glyph, "A")
      expect(dedup.find(glyph)).to eq("A")
    end

    it "finds a duplicate by outline, not by name" do
      dedup = described_class.new
      dedup.register(make_glyph("A"), "A")
      duplicate = make_glyph("B") # same outline, different name
      expect(dedup.find(duplicate)).to eq("A")
    end

    it "does not match glyphs with different outlines" do
      dedup = described_class.new
      dedup.register(make_glyph("A", points: [[0, 0, "line"], [100, 0, "line"]]), "A")
      different = make_glyph("B", points: [[0, 0, "line"], [200, 0, "line"]])
      expect(dedup.find(different)).to be_nil
    end

    it "overwrites the canonical name when the same signature is re-registered" do
      dedup = described_class.new
      g = make_glyph("A")
      dedup.register(g, "first")
      dedup.register(g, "second")
      expect(dedup.find(g)).to eq("second")
    end
  end

  describe "#size" do
    it "counts unique signatures" do
      dedup = described_class.new
      dedup.register(make_glyph("A"), "A")
      dedup.register(make_glyph("B"), "B") # same outline as A
      dedup.register(make_glyph("C", points: [[0, 0, "line"], [50, 50, "line"]]), "C")
      expect(dedup.size).to eq(2)
    end
  end

  describe "#empty?" do
    it "is true initially" do
      expect(described_class.new).to be_empty
    end

    it "is false after registering" do
      dedup = described_class.new
      dedup.register(make_glyph("A"), "A")
      expect(dedup).not_to be_empty
    end
  end
end
