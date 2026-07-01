# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg_to_glyf"

RSpec.describe Fontisan::SvgToGlyf::Path::ContourBuilder do
  let(:parser) { Fontisan::SvgToGlyf::Path::Parser }
  let(:builder) { described_class.new }

  def build(path_string)
    builder.build(parser.parse(path_string))
  end

  def points_of(contour)
    contour.points.map { |p| [p.x, p.y, p.type] }
  end

  describe "#build" do
    it "produces one contour for a simple rectangle" do
      contours = build("M 0 0 L 100 0 L 100 100 L 0 100 Z")
      expect(contours.size).to eq(1)
      expect(contours.first.points.size).to eq(4)
      expect(contours.first.points.all? { |p| p.type == "line" }).to be(true)
    end

    it "emits two offcurve + one curve for a cubic segment" do
      contours = build("M 0 0 C 50 100 100 100 100 0 Z")
      points = contours.first.points
      expect(points.map(&:type)).to eq(%w[line offcurve offcurve curve])
    end

    it "emits one offcurve + one qcurve for a quadratic segment" do
      contours = build("M 0 0 Q 50 100 100 0 Z")
      points = contours.first.points
      expect(points.map(&:type)).to eq(%w[line offcurve qcurve])
    end

    it "resolves relative lowercase commands against current point" do
      absolute = build("M 0 0 L 100 100 Z")
      relative = build("M 0 0 l 100 100 Z")
      expect(points_of(absolute.first)).to eq(points_of(relative.first))
    end

    it "resolves relative cubic controls against current point" do
      absolute = build("M 0 0 C 50 50 100 50 100 0 Z")
      relative = build("M 0 0 c 50 50 100 50 100 0 Z")
      expect(points_of(absolute.first)).to eq(points_of(relative.first))
    end

    it "handles H and V commands" do
      contours = build("M 0 0 H 100 V 50 L 0 50 Z")
      pts = contours.first.points
      expect(pts.map { |p| [p.x, p.y] }).to eq([[0, 0], [100, 0], [100, 50], [0, 50]])
    end

    it "handles relative H and V" do
      contours = build("M 0 0 h 100 v 50 Z")
      pts = contours.first.points
      expect(pts.map { |p| [p.x, p.y] }).to eq([[0, 0], [100, 0], [100, 50]])
    end

    it "produces multiple contours for multiple subpaths" do
      contours = build("M 0 0 L 10 10 Z M 20 20 L 30 30 Z")
      expect(contours.size).to eq(2)
    end

    it "reflects control for S after C" do
      contours = build("M 0 0 C 25 50 75 50 100 0 S 175 -50 200 0 Z")
      pts = contours.first.points
      # M(0,0,line), C1(25,50,off), C2(75,50,off), P3(100,0,curve),
      # reflected C1(125,-50,off), C2(175,-50,off), P3(200,0,curve)
      expect(pts.map { |p| [p.x, p.y] }).to eq(
        [[0, 0], [25, 50], [75, 50], [100, 0], [125, -50], [175, -50], [200, 0]],
      )
    end

    it "uses current point as control for S with no preceding C" do
      contours = build("M 0 0 S 50 50 100 0 Z")
      pts = contours.first.points
      # No prior C, so reflected control = current point = (0,0)
      expect(pts.map { |p| [p.x, p.y] }).to eq(
        [[0, 0], [0, 0], [50, 50], [100, 0]],
      )
    end

    it "reflects control for T after Q" do
      contours = build("M 0 0 Q 50 100 100 0 T 200 0 Z")
      pts = contours.first.points
      # M(0,0,line), control(50,100,off), P2(100,0,qcurve),
      # reflected control(150, -100, off), P2(200,0,qcurve)
      expect(pts.map { |p| [p.x, p.y] }).to eq(
        [[0, 0], [50, 100], [100, 0], [150, -100], [200, 0]],
      )
    end

    it "drops a degenerate subpath with only a move" do
      contours = build("M 50 50 Z")
      expect(contours).to be_empty
    end

    it "keeps a contour that has move + one drawing command" do
      contours = build("M 0 0 L 100 100 Z")
      expect(contours.size).to eq(1)
      expect(contours.first.points.size).to eq(2)
    end
  end
end
