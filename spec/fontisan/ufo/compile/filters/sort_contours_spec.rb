# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/filters"

RSpec.describe Fontisan::Ufo::Compile::Filters::SortContours do
  let(:make_contour) do
    ->(points) { Fontisan::Ufo::Contour.new(points.map { |(x, y, type)| Fontisan::Ufo::Point.new(x: x, y: y, type: type) }) }
  end

  def points_summary(contour)
    contour.points.map { |p| [p.x, p.y, p.type] }
  end

  describe ".run" do
    it "rotates each contour to start with an on-curve point" do
      contour = make_contour.call([
                                    [0, 0, "offcurve"],
                                    [100, 0, "line"],
                                    [100, 100, "line"],
                                  ])
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyph.add_contour(contour)

      described_class.run([glyph])

      expect(points_summary(glyph.contours[0])).to eq([
                                                        [100, 0, "line"],
                                                        [100, 100, "line"],
                                                        [0, 0, "offcurve"],
                                                      ])
    end

    it "leaves contours that already start with an on-curve point unchanged (rotation-wise)" do
      contour = make_contour.call([
                                    [10, 50, "line"],
                                    [20, 50, "line"],
                                  ])
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyph.add_contour(contour)

      described_class.run([glyph])

      expect(points_summary(glyph.contours[0])).to eq([
                                                        [10, 50, "line"],
                                                        [20, 50, "line"],
                                                      ])
    end

    it "orders contours within a glyph by descending Y then ascending X of the first on-curve point" do
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyph.add_contour(make_contour.call([
                                            [0, 0, "line"], [100, 0, "line"] # sort_key [0, 0]
                                          ]))
      glyph.add_contour(make_contour.call([
                                            [50, 100, "line"], [60, 100, "line"]  # sort_key [-100, 50]
                                          ]))
      glyph.add_contour(make_contour.call([
                                            [10, 100, "line"], [20, 100, "line"]  # sort_key [-100, 10]
                                          ]))

      described_class.run([glyph])

      # Expected order: contour @ (10,100) < contour @ (50,100) < contour @ (0,0)
      first_points = glyph.contours.map do |c|
        [c.points.first.x, c.points.first.y]
      end
      expect(first_points).to eq([[10, 100], [50, 100], [0, 0]])
    end

    it "handles empty contours gracefully" do
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyph.add_contour(Fontisan::Ufo::Contour.new([]))

      expect { described_class.run([glyph]) }.not_to raise_error
    end

    it "leaves all-off-curve contours rotation unchanged (no on-curve to rotate to)" do
      contour = make_contour.call([
                                    [0, 0, "offcurve"],
                                    [100, 0, "offcurve"],
                                  ])
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyph.add_contour(contour)

      described_class.run([glyph])

      expect(points_summary(glyph.contours[0])).to eq([
                                                        [0, 0, "offcurve"],
                                                        [100, 0, "offcurve"],
                                                      ])
    end

    it "returns the same glyph array (mutates in place)" do
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyphs = [glyph]
      result = described_class.run(glyphs)
      expect(result).to equal(glyphs)
    end
  end

  describe "Filters::REGISTRY" do
    it "registers SortContours under :sort_contours" do
      expect(Fontisan::Ufo::Compile::Filters::REGISTRY[:sort_contours])
        .to eq(described_class)
    end

    it "applies via the Filters hub by symbol" do
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyph.add_contour(make_contour.call([
                                            [0, 0, "offcurve"], [100, 0, "line"]
                                          ]))

      Fontisan::Ufo::Compile::Filters.apply([:sort_contours], [glyph])
      expect(glyph.contours[0].points.first.type).to eq("line")
    end
  end
end
