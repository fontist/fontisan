# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg_to_glyf"

RSpec.describe Fontisan::SvgToGlyf::Document do
  let(:affine) { Fontisan::SvgToGlyf::Geometry::AffineTransform }
  let(:bounds_class) { Fontisan::Ufo::Bounds }

  describe "viewbox extraction" do
    it "reads viewBox attribute as a Ufo::Bounds anchored at the viewBox origin" do
      doc = described_class.from_xml(<<~SVG)
        <svg viewBox="0 0 1000 1000"><path d="M 0 0"/></svg>
      SVG
      expect(doc.viewbox).to eq(bounds_class.new(min_x: 0, min_y: 0,
                                                 max_x: 1000, max_y: 1000))
    end

    it "preserves the viewBox min_x and min_y for non-origin viewboxes" do
      doc = described_class.from_xml(<<~SVG)
        <svg viewBox="100 100 800 800"><path d="M 0 0"/></svg>
      SVG
      expect(doc.viewbox).to eq(bounds_class.new(min_x: 100, min_y: 100,
                                                 max_x: 900, max_y: 900))
    end

    it "accepts comma-separated viewBox values" do
      doc = described_class.from_xml(<<~SVG)
        <svg viewBox="0,0,1000,1000"><path d="M 0 0"/></svg>
      SVG
      expect(doc.viewbox.max_x).to eq(1000.0)
      expect(doc.viewbox.max_y).to eq(1000.0)
    end

    it "falls back to width/height when viewBox is absent" do
      doc = described_class.from_xml(<<~SVG)
        <svg width="500" height="700"><path d="M 0 0"/></svg>
      SVG
      expect(doc.viewbox.max_x).to eq(500.0)
      expect(doc.viewbox.max_y).to eq(700.0)
      expect(doc.viewbox.min_x).to eq(0.0)
      expect(doc.viewbox.min_y).to eq(0.0)
    end

    it "returns nil when no geometry can be derived" do
      doc = described_class.from_xml(<<~SVG)
        <svg><path d="M 0 0"/></svg>
      SVG
      expect(doc.viewbox).to be_nil
    end
  end

  describe "#each_path" do
    it "yields path data with identity transform when no group" do
      doc = described_class.from_xml(<<~SVG)
        <svg viewBox="0 0 1000 1000"><path d="M 0 0 L 1 1"/></svg>
      SVG
      doc.each_path do |data, transform|
        expect(data).to eq("M 0 0 L 1 1")
        expect(transform).to eq(affine.identity)
      end
    end

    it "accumulates transform from a single <g>" do
      doc = described_class.from_xml(<<~SVG)
        <svg viewBox="0 0 1000 1000">
          <g transform="translate(50, 60)"><path d="M 0 0"/></g>
        </svg>
      SVG
      doc.each_path do |_data, transform|
        expect(transform.apply(0, 0)).to eq([50.0, 60.0])
      end
    end

    it "composes nested <g> transforms" do
      doc = described_class.from_xml(<<~SVG)
        <svg viewBox="0 0 1000 1000">
          <g transform="scale(2)">
            <g transform="translate(10, 0)">
              <path d="M 5 0"/>
            </g>
          </g>
        </svg>
      SVG
      doc.each_path do |_data, transform|
        # translate first: (5,0)→(15,0), then scale: →(30,0)
        expect(transform.apply(5, 0)).to eq([30.0, 0.0])
      end
    end

    it "yields each sibling <path> separately with the same transform" do
      doc = described_class.from_xml(<<~SVG)
        <svg viewBox="0 0 1000 1000">
          <g transform="scale(2)">
            <path d="M 0 0"/>
            <path d="M 1 1"/>
          </g>
        </svg>
      SVG
      paths = doc.each_path.to_a
      expect(paths.size).to eq(2)
      expect(paths[0][0]).to eq("M 0 0")
      expect(paths[1][0]).to eq("M 1 1")
    end

    it "handles the real ucode fixture" do
      fixture = "/Users/mulgogi/src/fontist/ucode/tmp/sample_output_17.0.0/blocks/Basic_Latin/U+0052/glyph.svg"
      skip "fixture not available" unless File.exist?(fixture)

      doc = described_class.from_file(fixture)
      expect(doc.viewbox.max_x).to eq(1000.0)
      paths = doc.each_path.to_a
      expect(paths.size).to eq(1)
      expect(paths[0][0]).to start_with("M ")
    end
  end
end
