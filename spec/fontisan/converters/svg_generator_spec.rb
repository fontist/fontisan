# frozen_string_literal: true

require "spec_helper"
require "fontisan/converters/svg_generator"

RSpec.describe Fontisan::Converters::SvgGenerator do
  let(:font) { Fontisan::FontLoader.load(font_fixture_path("MonaSans", "fonts/static/ttf/MonaSans-ExtraLightItalic.ttf")) }
  let(:generator) { described_class.new }

  describe "#initialize" do
    it "creates generator" do
      expect(generator).to be_a(described_class)
    end
  end

  describe "#supported_conversions" do
    it "supports TTF to SVG" do
      conversions = generator.supported_conversions
      expect(conversions).to include(%i[ttf svg])
    end

    it "supports OTF to SVG" do
      conversions = generator.supported_conversions
      expect(conversions).to include(%i[otf svg])
    end
  end

  describe "#supports?" do
    it "returns true for TTF to SVG" do
      expect(generator.supports?(:ttf, :svg)).to be true
    end

    it "returns true for OTF to SVG" do
      expect(generator.supports?(:otf, :svg)).to be true
    end

    it "returns false for unsupported conversions" do
      expect(generator.supports?(:ttf, :woff2)).to be false
      expect(generator.supports?(:svg, :ttf)).to be false
    end
  end

  describe "#validate" do
    it "validates TTF to SVG conversion" do
      expect(generator.validate(font, :svg)).to be true
    end

    it "raises error for wrong target format" do
      expect do
        generator.validate(font, :woff2)
      end.to raise_error(Fontisan::Error, /only supports conversion to svg/)
    end

    it "raises error for missing required tables" do
      minimal_font = double("font")
      allow(minimal_font).to receive(:table).and_return(nil)

      expect do
        generator.validate(minimal_font, :svg)
      end.to raise_error(Fontisan::Error, /missing required table/)
    end
  end

  describe "#convert" do
    it "converts font to SVG" do
      result = generator.convert(font)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:svg_xml)
      expect(result[:svg_xml]).to be_a(String)
    end

    it "generates valid SVG XML structure" do
      result = generator.convert(font)
      svg = result[:svg_xml]

      expect(svg).to include('<?xml version="1.0"')
      expect(svg).to include("<svg")
      expect(svg).to include("<font")
      expect(svg).to include("<font-face")
      expect(svg).to include("</svg>")
    end

    it "includes glyphs in SVG" do
      result = generator.convert(font)
      svg = result[:svg_xml]

      expect(svg).to include("<glyph")
    end

    it "respects max_glyphs option" do
      result = generator.convert(font, max_glyphs: 5)
      svg = result[:svg_xml]

      # Should have limited number of glyphs
      glyph_count = svg.scan("<glyph").length
      expect(glyph_count).to be <= 5
    end

    it "handles glyph_ids option" do
      result = generator.convert(font, glyph_ids: [0, 65, 66])
      svg = result[:svg_xml]

      expect(svg).to be_a(String)
      expect(svg).to include("<svg")
    end

    context "with per-glyph unicode and glyph-name attributes (issue #80)" do
      let(:svg) { generator.convert(font)[:svg_xml] }

      it "emits glyph-name on every <glyph> element" do
        # Every glyph — including .notdef — should carry a glyph-name.
        # post v2.0 fonts supply canonical names; the gidN fallback
        # covers any gaps.
        glyph_lines = svg.scan(/<glyph [^>]*\/>/)
        expect(glyph_lines).not_to be_empty
        expect(glyph_lines).to all(match(/glyph-name="[^"]+"/))
      end

      it "emits unicode on <glyph> elements that have cmap mappings" do
        # At least the ASCII range should appear as unicode="...". We
        # pick a few printable ASCII characters that MonaSans-ExtraLightItalic
        # is guaranteed to map (letters, digits, common punctuation).
        expect(svg).to match(/unicode="[A-Za-z0-9]"/)
      end

      it "renders non-ASCII codepoints as numeric entities" do
        # Any glyph whose cmap mapping includes a codepoint > 0x7E must
        # surface that codepoint as a &#xHEX; entity in the unicode
        # attribute. We don't pin a specific codepoint — fonts differ
        # in cmap ordering — but every CJK/Latin-Extended font has at
        # least one.
        entities = svg.scan(/unicode="[^"]*(&#x[0-9A-Fa-f]+;)[^"]*"/)
          .map(&:first).uniq
        expect(entities).not_to be_empty

        # Every matched entity must be a codepoint above printable ASCII
        # (the whole point of entity-encoding).
        entities.each do |entity|
          hex = entity.match(/^&#x([0-9A-Fa-f]+);$/).captures.first
          expect(hex.to_i(16)).to be > 0x7E
        end
      end

      it "escapes XML-special ASCII codepoints rather than emitting them raw" do
        # If the font maps any of <, >, &, ", ' to a glyph, that codepoint
        # must appear in `unicode=` as the named entity (&lt; &gt; &amp;
        # &quot; &apos;), never as the raw character inside an attribute.
        # These are all in printable ASCII so they go through the
        # char-then-escape path, not the hex-entity path.
        cmap = font.table("cmap")
        named_entities = {
          0x3C => "&lt;",
          0x3E => "&gt;",
          0x26 => "&amp;",
          0x22 => "&quot;",
          0x27 => "&apos;",
        }
        present = named_entities.select do |cp, _|
          cmap.unicode_mappings.key?(cp)
        end
        skip "font has no XML-special codepoints in cmap" if present.empty?

        present.each_value do |entity|
          expect(svg).to include(%(unicode="#{entity}"))
        end

        # No attribute value should contain a raw < or unescaped &.
        svg.scan(/unicode="([^"]*)"/).each do |(value)|
          stripped = value
            .gsub("&lt;", "").gsub("&gt;", "").gsub("&quot;", "")
            .gsub("&apos;", "").gsub("&amp;", "").gsub(/&#x[0-9A-Fa-f]+;/, "")
          expect(stripped).not_to include("<")
          expect(stripped).not_to include("&")
        end
      end

      it "omits unicode= on .notdef (no cmap mapping)" do
        notdef_line = svg.scan(/<glyph [^>]*\/>/).find do |l|
          l.include?('glyph-name=".notdef"')
        end
        expect(notdef_line).not_to be_nil
        expect(notdef_line).not_to include("unicode=")
      end

      it "supports glyphs mapped from multiple codepoints" do
        # Find a glyph mapped from >1 codepoint (common: space and
        # non-breaking space share a glyph). The unicode attribute
        # should carry both, concatenated.
        cmap = font.table("cmap")
        gid_to_cps = cmap.unicode_mappings.each_with_object(Hash.new do |h, k|
          h[k] = []
        end) do |(cp, gid), h|
          h[gid] << cp
        end
        multi_cps_gid = gid_to_cps.find { |_gid, cps| cps.size > 1 }&.first
        skip "font has no multi-codepoint glyph" unless multi_cps_gid

        # Build the expected unicode string and verify it appears.
        expected = gid_to_cps[multi_cps_gid].map do |cp|
          (0x20..0x7E).cover?(cp) ? cp.chr(Encoding::UTF_8) : "&#x#{cp.to_s(16).upcase};"
        end.join
        expect(svg).to include(%(unicode="#{expected}"))
      end
    end
  end
end
