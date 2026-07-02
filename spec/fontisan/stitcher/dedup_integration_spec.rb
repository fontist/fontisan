# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"
require "tmpdir"

RSpec.describe "Stitcher dedup + gid-cap integration" do
  let(:ufo) { Fontisan::Ufo }

  def make_font_with_glyph(name, codepoint, width: 500, points: [[0, 0, "line"], [100, 0, "line"], [100, 100, "line"]])
    font = ufo::Font.new
    font.info.units_per_em = 1000
    notdef = ufo::Glyph.new(name: ".notdef")
    font.glyphs[".notdef"] = notdef

    g = ufo::Glyph.new(name: name)
    g.width = width
    g.add_unicode(codepoint)
    g.add_contour(ufo::Contour.new(points.map { |x, y, t| ufo::Point.new(x: x, y: y, type: t) }))
    font.glyphs[name] = g
    font
  end

  def empty_font(_name)
    font = ufo::Font.new
    font.info.units_per_em = 1000
    font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")
    font
  end

  describe "signature-based deduplication" do
    it "merges identical glyphs from different donors into one gid" do
      donor_a = make_font_with_glyph("space", 0x20, width: 250, points: [])
      donor_b = make_font_with_glyph("SP", 0xA0, width: 250, points: [])

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:a, donor_a)
      stitcher.add_source(:b, donor_b)
      stitcher.include_notdef(from: :a, into: :main)
      stitcher.include_codepoints([0x20], from: :a, into: :main)
      stitcher.include_codepoints([0xA0], from: :b, into: :main)

      target = stitcher.build_target_font(subfont: :main)
      # .notdef + one merged glyph = 2 glyphs total
      expect(target.glyphs.size).to eq(2)
      # Both codepoints map to the same glyph
      merged = target.glyphs.values.find { |g| g.unicodes.include?(0x20) }
      expect(merged.unicodes).to include(0x20, 0xA0)
    end

    it "keeps separate gids for glyphs with different outlines" do
      donor = make_font_with_glyph("A", 0x41, points: [[0, 0, "line"], [100, 0, "line"]])
      donor.glyphs["B"] = ufo::Glyph.new(name: "B").tap do |g|
        g.width = 500
        g.add_unicode(0x42)
        g.add_contour(ufo::Contour.new([
                                         ufo::Point.new(x: 0, y: 0, type: "line"),
                                         ufo::Point.new(x: 200, y: 0, type: "line"),
                                       ]))
      end

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:d, donor)
      stitcher.include_notdef(from: :d, into: :main)
      stitcher.include_codepoints([0x41, 0x42], from: :d, into: :main)

      target = stitcher.build_target_font(subfont: :main)
      # .notdef + A + B = 3 glyphs
      expect(target.glyphs.size).to eq(3)
    end

    it "can be disabled with deduplicate: false" do
      donor_a = make_font_with_glyph("space", 0x20, width: 250, points: [])
      donor_b = make_font_with_glyph("SP", 0xA0, width: 250, points: [])

      stitcher = Fontisan::Stitcher.new(deduplicate: false)
      stitcher.add_source(:a, donor_a)
      stitcher.add_source(:b, donor_b)
      stitcher.include_notdef(from: :a, into: :main)
      stitcher.include_codepoints([0x20], from: :a, into: :main)
      stitcher.include_codepoints([0xA0], from: :b, into: :main)

      target = stitcher.build_target_font(subfont: :main)
      # .notdef + space + SP = 3 glyphs (no dedup)
      expect(target.glyphs.size).to eq(3)
    end

    it "preserves name-based dedup behavior for same-name glyphs" do
      # Two donors with identical "space" glyphs (same name, same outline)
      donor_a = make_font_with_glyph("space", 0x20, width: 250, points: [])
      donor_b = make_font_with_glyph("space", 0xA0, width: 250, points: [])

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:a, donor_a)
      stitcher.add_source(:b, donor_b)
      stitcher.include_notdef(from: :a, into: :main)
      stitcher.include_codepoints([0x20], from: :a, into: :main)
      stitcher.include_codepoints([0xA0], from: :b, into: :main)

      target = stitcher.build_target_font(subfont: :main)
      expect(target.glyphs.size).to eq(2) # .notdef + space
      space = target.glyphs["space"]
      expect(space.unicodes).to include(0x20, 0xA0)
    end
  end

  describe "glyph cap enforcement" do
    it "raises GlyphLimitExceededError when TTF cap is exceeded" do
      donor = make_font_with_glyph("A", 0x41)
      donor.glyphs["B"] = ufo::Glyph.new(name: "B").tap do |g|
        g.width = 500
        g.add_unicode(0x42)
      end
      donor.glyphs["C"] = ufo::Glyph.new(name: "C").tap do |g|
        g.width = 500
        g.add_unicode(0x43)
      end

      # Disable dedup so all 4 glyphs (.notdef + A + B + C) are counted
      stitcher = Fontisan::Stitcher.new(deduplicate: false)
      stitcher.add_source(:d, donor)
      stitcher.include_notdef(from: :d, into: :main)
      stitcher.include_codepoints([0x41, 0x42, 0x43], from: :d, into: :main)

      # Stub the cap to 3 glyphs (we have .notdef + 3 = 4 glyphs)
      stub_const("Fontisan::Stitcher::GlyphLimit::TTF_GLYPH_CAP", 3)

      Dir.mktmpdir do |dir|
        expect { stitcher.write_to(File.join(dir, "out.ttf"), format: :ttf, subfont: :main) }
          .to raise_error(Fontisan::GlyphLimitExceededError, /exceeding the TTF limit/)
      end
    end

    it "raises GlyphLimitExceededError for OTF when cap is exceeded" do
      donor = make_font_with_glyph("A", 0x41)
      donor.glyphs["B"] = ufo::Glyph.new(name: "B").tap do |g|
        g.width = 500
        g.add_unicode(0x42)
      end
      donor.glyphs["C"] = ufo::Glyph.new(name: "C").tap do |g|
        g.width = 500
        g.add_unicode(0x43)
      end

      # Disable dedup so all 4 glyphs (.notdef + A + B + C) are counted
      stitcher = Fontisan::Stitcher.new(deduplicate: false)
      stitcher.add_source(:d, donor)
      stitcher.include_notdef(from: :d, into: :main)
      stitcher.include_codepoints([0x41, 0x42, 0x43], from: :d, into: :main)

      # Both TTF and OTF cap at 65,535 in fontisan (CFF1's INDEX count
      # is card16). Stub the cap to 3 to trigger the error.
      stub_const("Fontisan::Stitcher::GlyphLimit::OTF_GLYPH_CAP", 3)

      Dir.mktmpdir do |dir|
        expect { stitcher.write_to(File.join(dir, "out.otf"), format: :otf, subfont: :main) }
          .to raise_error(Fontisan::GlyphLimitExceededError, /exceeding the OTF limit/)
      end
    end

    it "does not raise when glyph count is under the cap (OTF)" do
      donor = make_font_with_glyph("A", 0x41)
      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:d, donor)
      stitcher.include_notdef(from: :d, into: :main)
      stitcher.include_codepoints([0x41], from: :d, into: :main)

      Dir.mktmpdir do |dir|
        expect { stitcher.write_to(File.join(dir, "out.otf"), format: :otf, subfont: :main) }
          .not_to raise_error
      end
    end
  end
end
