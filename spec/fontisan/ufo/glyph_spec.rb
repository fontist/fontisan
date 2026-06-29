# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/glyph"

RSpec.describe Fontisan::Ufo::Glyph do
  let(:ufo_path) { "/Users/mulgogi/src/external/unicode/last-resort-font/font.ufo" }

  before { skip "last-resort-font not available" unless Dir.exist?(ufo_path) }

  describe ".from_glif" do
    it "parses .notdef with two contours" do
      xml = File.read(File.join(ufo_path, "glyphs/_notdef.glif"))
      glyph = described_class.from_glif(xml)

      expect(glyph.name).to eq(".notdef")
      expect(glyph.width).to eq(1024.0)
      expect(glyph.contours.size).to eq(2)
      expect(glyph.point_count).to eq(8)
    end

    it "parses contour points with correct types" do
      xml = File.read(File.join(ufo_path, "glyphs/_notdef.glif"))
      glyph = described_class.from_glif(xml)
      contour = glyph.contours.first

      expect(contour.points.size).to eq(4)
      expect(contour.points.first.x).to eq(896.0)
      expect(contour.points.first.y).to eq(0.0)
      expect(contour.points.first.type).to eq("line")
      expect(contour.points.first.on_curve?).to be(true)
    end

    it "parses off-curve control points correctly" do
      xml = File.read(File.join(ufo_path, "glyphs/lastresortadlam.glif"))
      glyph = described_class.from_glif(xml)

      expect(glyph.contours.size).to eq(33)
      expect(glyph.point_count).to be > 100
      # First contour contains both on-curve and off-curve points
      types = glyph.contours.first.points.map(&:type).uniq
      expect(types).to include("curve", "offcurve")
    end

    it "computes the bounding box from contour points" do
      xml = File.read(File.join(ufo_path, "glyphs/lastresortadlam.glif"))
      glyph = described_class.from_glif(xml)

      bbox = glyph.bbox
      expect(bbox.x_min).to eq(196.0)
      expect(bbox.x_max).to eq(2154.0)
    end
  end

  describe "#to_glif round-trip" do
    it "preserves contour count and point coordinates" do
      xml = File.read(File.join(ufo_path, "glyphs/_notdef.glif"))
      glyph = described_class.from_glif(xml)
      re_xml = glyph.to_glif
      glyph2 = described_class.from_glif(re_xml)

      expect(glyph2.contours.size).to eq(glyph.contours.size)
      expect(glyph2.point_count).to eq(glyph.point_count)
      expect(glyph2.contours.first.points.first.x).to eq(glyph.contours.first.points.first.x)
    end

    it "preserves advance width" do
      xml = File.read(File.join(ufo_path, "glyphs/_notdef.glif"))
      glyph = described_class.from_glif(xml)
      glyph2 = described_class.from_glif(glyph.to_glif)

      expect(glyph2.width).to eq(glyph.width)
    end
  end

  describe "#composite?" do
    it "is false for a simple glyph" do
      xml = File.read(File.join(ufo_path, "glyphs/_notdef.glif"))
      expect(described_class.from_glif(xml).composite?).to be(false)
    end
  end
end
