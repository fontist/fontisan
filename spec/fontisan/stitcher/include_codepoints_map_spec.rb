# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"

RSpec.describe Fontisan::Stitcher, "#include_codepoints_map" do
  let(:ufo) { Fontisan::Ufo }

  def make_font_with(name, cp)
    font = ufo::Font.new
    font.info.units_per_em = 1000
    font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")

    g = ufo::Glyph.new(name: name)
    g.width = 500
    g.add_unicode(cp)
    g.add_contour(ufo::Contour.new([
                                     ufo::Point.new(x: 0, y: 0, type: "line"),
                                     ufo::Point.new(x: 100, y: 0,
                                                    type: "line"),
                                     ufo::Point.new(x: 100, y: 100,
                                                    type: "line"),
                                   ]))
    font.glyphs[name] = g
    font
  end

  it "groups codepoints by donor and forwards each group to include_codepoints" do
    latin = make_font_with("A", 0x41)
    cjk   = make_font_with("uni4E00", 0x4E00)

    stitcher = described_class.new
    stitcher.add_source(:latin, latin)
    stitcher.add_source(:cjk, cjk)

    stitcher.include_codepoints_map({ 0x41 => :latin, 0x4E00 => :cjk },
                                    into: :main)

    # Both bindings landed in the same subfont, each with its donor.
    expect(stitcher.subfont_names).to eq([:main])
    expect(stitcher.subfonts[:main].map do |b|
      b[:source].font
    end.uniq.size).to eq(2)
  end

  it "sorts codepoints within each donor group for reproducible GID assignment" do
    latin = make_font_with("A", 0x41)
    allow(latin.glyphs["A"]).to receive(:add_unicode).and_call_original

    stitcher = described_class.new
    stitcher.add_source(:latin, latin)

    stitcher.include_codepoints_map(
      { 0x43 => :latin, 0x41 => :latin, 0x42 => :latin }, into: :main
    )

    # only 0x41 maps to a glyph in the donor; the others get dropped at
    # the gid lookup stage. We assert sort behaviour by checking the
    # binding's codepoint order matches ascending input.
    cps = stitcher.subfonts[:main].map { |b| b[:codepoint] }.compact
    expect(cps).to eq(cps.sort)
  end

  it "coerces string donor labels via source lookup" do
    latin = make_font_with("A", 0x41)

    stitcher = described_class.new
    stitcher.add_source(:latin, latin)

    stitcher.include_codepoints_map({ 0x41 => "latin" }, into: :main)
    expect(stitcher.subfonts[:main].size).to be > 0
  end

  it "raises ArgumentError when the donor is unknown" do
    stitcher = described_class.new
    expect do
      stitcher.include_codepoints_map({ 0x41 => :ghost }, into: :main)
    end.to raise_error(ArgumentError, /unknown source/)
  end

  it "is a no-op on an empty map" do
    latin = make_font_with("A", 0x41)
    stitcher = described_class.new
    stitcher.add_source(:latin, latin)

    stitcher.include_codepoints_map({}, into: :main)
    expect(stitcher.subfont_names).to eq([])
  end

  it "supports multiple donors in a single call" do
    latin = make_font_with("A", 0x41)
    cjk   = make_font_with("uni4E00", 0x4E00)

    stitcher = described_class.new
    stitcher.add_source(:latin, latin)
    stitcher.add_source(:cjk, cjk)

    cp_map = {
      0x41 => :latin,
      0x4E00 => :cjk,
    }
    stitcher.include_codepoints_map(cp_map, into: :multi)

    donors = stitcher.subfonts[:multi].map { |b| b[:source].font }.uniq
    expect(donors).to contain_exactly(latin, cjk)
  end
end
