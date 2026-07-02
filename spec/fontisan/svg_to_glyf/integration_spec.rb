# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg_to_glyf"
require "tmpdir"

RSpec.describe "SvgToGlyf integration" do
  let(:ucode_fixture) do
    "/Users/mulgogi/src/fontist/ucode/tmp/sample_output_17.0.0/blocks/Basic_Latin/U+0052/glyph.svg"
  end

  describe Fontisan::SvgToGlyf do
    describe ".convert" do
      it "produces a Ufo::Glyph from a simple path" do
        glyph = described_class.convert(
          "M 0 0 L 500 0 L 500 700 L 0 700 Z",
          upm: 1000,
          codepoint: 0x41,
          viewbox: { width: 1000, height: 1000 },
        )
        expect(glyph).to be_a(Fontisan::Ufo::Glyph)
        expect(glyph.unicodes).to include(0x41)
        expect(glyph.contours.size).to eq(1)
        expect(glyph.contours.first.points.size).to eq(4)
      end

      it "flips Y so SVG top maps to font top" do
        glyph = described_class.convert(
          "M 0 1000 L 100 1000 Z",
          upm: 1000,
          viewbox: { width: 1000, height: 1000 },
        )
        first_point = glyph.contours.first.points.first
        expect(first_point.y).to eq(0)
      end

      it "rounds all points to integers" do
        glyph = described_class.convert(
          "M 0.5 0.5 L 100.7 200.3 Z",
          upm: 1000,
          viewbox: { width: 1000, height: 1000 },
        )
        glyph.contours.first.points.each do |pt|
          expect(pt.x).to eq(pt.x.to_i)
          expect(pt.y).to eq(pt.y.to_i)
        end
      end

      it "applies a group transform" do
        affine = Fontisan::SvgToGlyf::Geometry::AffineTransform

        no_transform = described_class.convert(
          "M 100 0 L 200 0 Z",
          upm: 1000,
          viewbox: { width: 1000, height: 1000 },
        )
        with_scale = described_class.convert(
          "M 100 0 L 200 0 Z",
          upm: 1000,
          viewbox: { width: 1000, height: 1000 },
          transform: affine.scale(2),
        )
        plain_x = no_transform.contours.first.points.first.x
        scaled_x = with_scale.contours.first.points.first.x
        expect(scaled_x).to eq(plain_x * 2)
      end

      it "emits cubic offcurve/curve points that the TtfCompiler filter can convert" do
        glyph = described_class.convert(
          "M 0 0 C 250 700 750 700 1000 0 Z",
          upm: 1000,
          viewbox: { width: 1000, height: 1000 },
        )
        types = glyph.contours.first.points.map(&:type)
        expect(types).to include("offcurve")
        expect(types).to include("curve")
      end
    end

    describe ".from_svg_file" do
      it "converts the real ucode R-glyph fixture into a multi-contour glyph" do
        skip "ucode fixture not available" unless File.exist?(ucode_fixture)

        glyph = described_class.from_svg_file(ucode_fixture, upm: 1000)
        expect(glyph).to be_a(Fontisan::Ufo::Glyph)
        # The R glyph has 3 subpaths (outer outline + two counters)
        expect(glyph.contours.size).to eq(3)
        glyph.contours.each do |contour|
          expect(contour.points.size).to be > 2
        end
      end

      it "derives the codepoint from the filename" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "U+10940.svg")
          File.write(path, <<~SVG)
            <svg viewBox="0 0 1000 1000"><path d="M 0 0 L 100 100 Z"/></svg>
          SVG
          glyph = described_class.from_svg_file(path, upm: 1000)
          expect(glyph.unicodes).to include(0x10940)
        end
      end

      it "produces font-space coordinates for a controlled SVG with scale transform" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "U+0041.svg")
          # Path in a 10×10 coordinate space, scaled to fill a 1000×1000 viewBox
          File.write(path, <<~SVG)
            <svg viewBox="0 0 1000 1000">
              <g transform="scale(100)">
                <path d="M 1 1 L 9 1 L 5 9 Z"/>
              </g>
            </svg>
          SVG
          glyph = described_class.from_svg_file(path, upm: 1000)
          pts = glyph.contours.first.points
          # scale(100) maps (1,1) → (100,100) in viewBox space.
          # Y-flip + UPM normalization: (100, 100) → (100, 1000-100) = (100, 900)
          expect(pts.map { |p| [p.x, p.y] }).to eq([[100, 900], [900, 900], [500, 100]])
        end
      end
    end

    describe ".from_directory" do
      it "produces a Ufo::Font with one glyph per SVG file" do
        Dir.mktmpdir do |dir|
          %w[U+10940 U+10941 U+10942].each do |cp|
            File.write(File.join(dir, "#{cp}.svg"), <<~SVG)
              <svg viewBox="0 0 1000 1000"><path d="M 0 0 L 100 100 Z"/></svg>
            SVG
          end
          font = described_class.from_directory(dir, upm: 1000)
          expect(font).to be_a(Fontisan::Ufo::Font)
          expect(font.glyphs.size).to eq(3)
          expect(font.info.units_per_em).to eq(1000)
        end
      end
    end
  end

  describe "compilation through TtfCompiler" do
    it "converts an SVG glyph to a valid TTF via the UFO pipeline" do
      glyph = Fontisan::SvgToGlyf.convert(
        "M 100 0 L 900 0 L 500 900 Z",
        upm: 1000,
        codepoint: 0x41,
        viewbox: { width: 1000, height: 1000 },
      )

      font = Fontisan::Ufo::Font.new
      font.info.family_name = "Test"
      font.info.units_per_em = 1000
      font.glyphs[".notdef"] = Fontisan::Ufo::Glyph.new(name: ".notdef")
      font.glyphs[glyph.name] = glyph

      Dir.mktmpdir do |dir|
        output_path = File.join(dir, "out.ttf")
        Fontisan::Ufo::Compile::TtfCompiler.new(font).compile(output_path: output_path)

        reopened = Fontisan::FontLoader.load(output_path)
        expect(reopened.table("maxp").num_glyphs).to eq(2)
        expect(reopened.table("cmap").unicode_mappings.key?(0x41)).to be(true)
      end
    end

    it "feeds into the Stitcher as a UFO source" do
      glyph = Fontisan::SvgToGlyf.convert(
        "M 100 0 L 900 0 L 500 900 Z",
        upm: 1000,
        codepoint: 0x42,
        viewbox: { width: 1000, height: 1000 },
      )
      chart_font = Fontisan::Ufo::Font.new
      chart_font.info.units_per_em = 1000
      chart_font.glyphs[".notdef"] = Fontisan::Ufo::Glyph.new(name: ".notdef")
      chart_font.glyphs[glyph.name] = glyph

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:chart, chart_font)
      stitcher.include_notdef(from: :chart, into: :main)
      stitcher.include_codepoints([0x42], from: :chart, into: :main)

      Dir.mktmpdir do |dir|
        output_path = File.join(dir, "stitched.ttf")
        stitcher.write_to(output_path, format: :ttf, subfont: :main)

        reopened = Fontisan::FontLoader.load(output_path)
        expect(reopened.table("cmap").unicode_mappings.key?(0x42)).to be(true)
      end
    end
  end
end
