# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Export::TtxGenerator do
  let(:font) { Fontisan::FontLoader.load(font_path) }
  let(:generator) { described_class.new(font, font_path) }

  shared_examples "generates valid TTX" do
    it "generates valid XML" do
      ttx_xml = generator.generate

      expect(ttx_xml).to include('<?xml version="1.0" encoding="UTF-8"?>')
      expect(ttx_xml).to include("<ttFont")
      expect(ttx_xml).to include("</ttFont>")

      # Validate XML structure
      doc = Nokogiri::XML(ttx_xml)
      expect(doc.errors).to be_empty
    end

    it "includes GlyphOrder" do
      ttx_xml = generator.generate
      expect(ttx_xml).to include("<GlyphOrder>")
      expect(ttx_xml).to include("</GlyphOrder>")
      expect(ttx_xml).to include("<GlyphID")
    end

    it "sets sfntVersion attribute" do
      ttx_xml = generator.generate
      expect(ttx_xml).

        to match(/sfntVersion="/)
    end

    it "includes ttLibVersion attribute" do
      ttx_xml = generator.generate
      expect(ttx_xml).to include('ttLibVersion="4.0"')
    end
  end

  describe "with TestTTF font" do
    let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }

    include_examples "generates valid TTX"

    it "generates head table" do
      ttx_xml = generator.generate(tables: ["head"])

      expect(ttx_xml).to include("<head>")
      expect(ttx_xml).to include("</head>")
      expect(ttx_xml).to include("<tableVersion")
      expect(ttx_xml).to include("<unitsPerEm")
    end

    it "generates name table" do
      ttx_xml = generator.generate(tables: ["name"])

      expect(ttx_xml).to include("<name>")
      expect(ttx_xml).to include("</name>")
      expect(ttx_xml).to include("<namerecord")
    end

    it "generates maxp table" do
      ttx_xml = generator.generate(tables: ["maxp"])

      expect(ttx_xml).to include("<maxp>")
      expect(ttx_xml).to include("<numGlyphs")
    end

    it "generates multiple tables" do
      ttx_xml = generator.generate(tables: ["head", "name", "maxp"])

      expect(ttx_xml).to include("<head>")
      expect(ttx_xml).to include("<name>")
      expect(ttx_xml).to include("<maxp>")
    end

    it "generates all tables when :all is specified" do
      ttx_xml = generator.generate(tables: :all)

      expect(ttx_xml).to include("<head>")
      expect(ttx_xml).to include("<name>")
      expect(ttx_xml).to include("<maxp>")
      expect(ttx_xml).to include("<hhea>")
    end
  end

  describe "with TestOTF font" do
    let(:font_path) { "spec/fixtures/fonttools/TestOTF.otf" }

    include_examples "generates valid TTX"

    it "generates CFF table as binary" do
      ttx_xml = generator.generate(tables: ["CFF"])

      expect(ttx_xml).to include("<CFF>")
      expect(ttx_xml).to include("<hexdata>")
    end
  end

  describe "pretty printing" do
    let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }

    it "generates pretty-printed XML by default" do
      ttx_xml = generator.generate(tables: ["head"])

      # Check for indentation
      expect(ttx_xml).to match(/\n  </)
    end

    it "generates compact XML when pretty is false" do
      compact_generator = described_class.new(font, font_path, pretty: false)
      ttx_xml = compact_generator.generate(tables: ["head"])

      # Less whitespace in compact mode
      expect(ttx_xml.length).to be < generator.generate(tables: ["head"]).length
    end
  end

  describe "error handling" do
    let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }

    it "handles missing tables gracefully" do
      ttx_xml = generator.generate(tables: ["nonexistent"])

      # Should still generate valid XML without the table
      expect(ttx_xml).to include("<ttFont")
      expect(ttx_xml).not_to include("<nonexistent>")
    end

    it "falls back to binary for unparseable tables" do
      # Even if a table fails to parse properly, it should generate hexdata
      ttx_xml = generator.generate

      expect(ttx_xml).to be_a(String)
      expect(ttx_xml).to include("<ttFont")
    end
  end

  describe "glyph names" do
    let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }

    it "uses post table glyph names when available" do
      ttx_xml = generator.generate

      # TestTTF has named glyphs
      expect(ttx_xml).to include('name=".notdef"')
      expect(ttx_xml).to include('name="space"')
      expect(ttx_xml).to include('name="period"')
    end

    it "includes correct glyph count" do
      ttx_xml = generator.generate
      doc = Nokogiri::XML(ttx_xml)
      glyph_count = doc.xpath("//GlyphID").count

      maxp = font.table("maxp")
      expect(glyph_count).to eq(maxp.num_glyphs.to_i)
    end
  end
end
