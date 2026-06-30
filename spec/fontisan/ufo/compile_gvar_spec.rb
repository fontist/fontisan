# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Gvar do
  describe ".build" do
    let(:default_glyph) do
      g = Fontisan::Ufo::Glyph.new(name: "A")
      g.add_contour(Fontisan::Ufo::Contour.new([
                                                 Fontisan::Ufo::Point.new(x: 0, y: 0, type: "line"),
                                                 Fontisan::Ufo::Point.new(x: 100, y: 0, type: "line"),
                                                 Fontisan::Ufo::Point.new(x: 100, y: 100, type: "line"),
                                                 Fontisan::Ufo::Point.new(x: 0, y: 100, type: "line"),
                                               ]))
      g
    end

    let(:bold_glyph) do
      g = Fontisan::Ufo::Glyph.new(name: "A")
      g.add_contour(Fontisan::Ufo::Contour.new([
                                                 Fontisan::Ufo::Point.new(x: 0, y: 0, type: "line"),
                                                 Fontisan::Ufo::Point.new(x: 120, y: 0, type: "line"),
                                                 Fontisan::Ufo::Point.new(x: 120, y: 120, type: "line"),
                                                 Fontisan::Ufo::Point.new(x: 0, y: 120, type: "line"),
                                               ]))
      g
    end

    it "returns empty gvar when no masters are provided" do
      bytes = described_class.build(
        default_glyphs: [default_glyph],
        masters: [],
        axis_count: 1,
      )
      expect(bytes).not_to be_nil
      expect(bytes.bytesize).to be > 0
    end

    it "produces a valid gvar header with version 1.0" do
      bytes = described_class.build(
        default_glyphs: [default_glyph],
        masters: [{ axes: { "wght" => 1.0 }, glyphs: [bold_glyph] }],
        axis_count: 1,
      )
      major, minor = bytes.unpack("nn")
      expect(major).to eq(1)
      expect(minor).to eq(0)
    end

    it "encodes the correct axis count" do
      bytes = described_class.build(
        default_glyphs: [default_glyph],
        masters: [{ axes: { "wght" => 1.0 }, glyphs: [bold_glyph] }],
        axis_count: 1,
      )
      axis_count = bytes.unpack1("@4 n")
      expect(axis_count).to eq(1)
    end

    it "encodes the correct glyph count" do
      bytes = described_class.build(
        default_glyphs: [default_glyph],
        masters: [{ axes: { "wght" => 1.0 }, glyphs: [bold_glyph] }],
        axis_count: 1,
      )
      # Header layout: version(4) + axisCount(2) + sharedTupleCount(2)
      # + offsetToSharedTuples(4) + glyphCount(2) + flags(2) = 16 bytes
      glyph_count = bytes.unpack1("@12 n")
      expect(glyph_count).to eq(1)
    end

    it "produces non-empty variation data for a glyph that varies" do
      bytes = described_class.build(
        default_glyphs: [default_glyph],
        masters: [{ axes: { "wght" => 1.0 }, glyphs: [bold_glyph] }],
        axis_count: 1,
      )
      # The offset array should show non-zero offset for the data area
      flags = bytes.unpack1("@12 n")
      use_long = flags & 1 == 1
      use_long ? 4 : 2
      14 # 4+2+2+4+2+2... wait: version(4) + axisCount(2) + sharedTupleCount(2) + offsetToSharedTuples(4) + glyphCount(2) + flags(2) = 16? No...

      # Header: version(4) + axisCount(2) + sharedTupleCount(2) + offsetToSharedTuples(4) + glyphCount(2) + flags(2) = 16
      header_size = 16
      first_offset = if use_long
                       bytes.unpack1("@#{header_size} N")
                     else
                       bytes.unpack1("@#{header_size} n")
                     end
      second_offset = if use_long
                        bytes.unpack1("@#{header_size + 4} N")
                      else
                        bytes.unpack1("@#{header_size + 2} n")
                      end

      expect(second_offset).to be > first_offset
    end

    it "produces zero variation for identical glyphs" do
      bytes = described_class.build(
        default_glyphs: [default_glyph],
        masters: [{ axes: { "wght" => 1.0 }, glyphs: [default_glyph] }],
        axis_count: 1,
      )
      # Header is 16 bytes, then offset array (2 entries × 2 bytes = 4),
      # then glyph data (empty for zero-delta glyphs) = 20 bytes total
      expect(bytes.bytesize).to eq(20)
      # Both offsets in the array should be 0 (no variation data)
      first_offset = bytes.unpack1("@16 n")
      second_offset = bytes.unpack1("@18 n")
      expect(first_offset).to eq(0)
      expect(second_offset).to eq(0)
    end
  end
end
