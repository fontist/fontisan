# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Color Emoji Fonts Integration", :integration do
  let(:output_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(output_dir) if File.exist?(output_dir)
  end

  describe "EmojiOneColor.otf (CFF with SVG)" do
    let(:font_path) { font_fixture_path("EmojiOneColor", "EmojiOneColor.otf") }

    it "loads successfully" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font).to be_a(Fontisan::OpenTypeFont)
    end

    it "has SVG table" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font.has_table?("SVG ")).to be true
    end

    it "parses SVG table structure" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      svg = font.table("SVG ")

      expect(svg).not_to be_nil
      expect(svg.version).to eq(0)
      expect(svg.num_entries).to be > 0
    end

    it "extracts SVG documents" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      svg = font.table("SVG ")

      # Get first document record
      record = svg.document_records.first
      expect(record).not_to be_nil

      # Extract document for first glyph in range
      doc = svg.svg_for_glyph(record.start_glyph_id)
      expect(doc).not_to be_nil
    end

    it "handles SVG compression" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      svg = font.table("SVG ")
      record = svg.document_records.first

      doc = svg.svg_for_glyph(record.start_glyph_id)
      # svg_for_glyph returns the SVG data as a string
      expect(doc).to be_a(String)
      expect(doc).not_to be_empty
    end

    it "validates SVG structure" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      svg = font.table("SVG ")

      expect(svg.valid?).to be true
    end

    it "reports SVG in FontInfo" do
      info = Fontisan.info(font_path)
      expect(info.has_svg_table).to be true
      expect(info.svg_glyph_count).to be > 0
    end
  end

  describe "TwitterColorEmoji-SVGinOT.ttf (TTF with SVG)" do
    let(:font_path) do
      font_fixture_path("TwitterColorEmoji", "TwitterColorEmoji-SVGinOT.ttf")
    end

    it "loads successfully" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font).to be_a(Fontisan::TrueTypeFont)
    end

    it "has SVG table" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font.has_table?("SVG ")).to be true
    end

    it "is TrueType format" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font.truetype?).to be true
    end

    it "parses SVG table" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      svg = font.table("SVG ")

      expect(svg.num_entries).to be > 0
      expect(svg.document_records.length).to eq(svg.num_entries)
    end

    it "extracts SVG documents from TTF" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      svg = font.table("SVG ")
      record = svg.document_records.first

      doc = svg.svg_for_glyph(record.start_glyph_id)
      # svg_for_glyph returns the SVG data as a string
      expect(doc).to be_a(String)
      expect(doc).not_to be_empty
    end

    it "reports SVG in FontInfo" do
      info = Fontisan.info(font_path)
      expect(info.has_svg_table).to be true
    end
  end

  describe "Gilbert-Color Bold Preview5.otf (CFF with SVG)" do
    let(:font_path) do
      font_fixture_path("Gilbert", "Gilbert-Color Bold Preview5.otf")
    end

    it "loads successfully" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font).to be_a(Fontisan::OpenTypeFont)
    end

    it "has SVG table" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font.has_table?("SVG ")).to be true
    end

    it "has CFF outlines" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font.has_table?("CFF ")).to be true
    end

    it "parses SVG table in CFF font" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      svg = font.table("SVG ")

      expect(svg.num_entries).to be > 0
      expect(svg.valid?).to be true
    end

    it "reports SVG in FontInfo" do
      info = Fontisan.info(font_path)
      expect(info.has_svg_table).to be true
    end
  end

  describe "TwemojiMozilla.ttf (TTF with COLR/CPAL)" do
    let(:font_path) { font_fixture_path("TwemojiMozilla", "Twemoji.Mozilla.ttf") }

    it "loads successfully" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font).to be_a(Fontisan::TrueTypeFont)
    end

    it "has COLR table" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font.has_table?("COLR")).to be true
    end

    it "has CPAL table" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      expect(font.has_table?("CPAL")).to be true
    end

    it "parses COLR table structure" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      colr = font.table("COLR")

      expect(colr).not_to be_nil
      expect(colr.version).to be >= 0
      expect(colr.num_base_glyph_records).to be > 0
    end

    it "parses CPAL table structure" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      cpal = font.table("CPAL")

      expect(cpal).not_to be_nil
      expect(cpal.version).to be >= 0
      expect(cpal.num_palettes).to be > 0
      expect(cpal.num_palette_entries).to be > 0
    end

    it "extracts color layers from COLR" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      colr = font.table("COLR")

      # Get first base glyph
      if colr.num_base_glyph_records > 0
        base_glyph = colr.base_glyph_records.first
        layers = colr.layers_for_glyph(base_glyph.glyph_id)

        expect(layers).not_to be_nil
        expect(layers).not_to be_empty
      end
    end

    it "extracts color palette from CPAL" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      cpal = font.table("CPAL")

      palette = cpal.palette(0)
      expect(palette).not_to be_nil
      expect(palette).not_to be_empty

      # Check color structure - colors are hex strings
      color = palette.first
      expect(color).to be_a(String)
      expect(color).to match(/^#[0-9A-F]{8}$/)  # Hex format: #RRGGBBAA
    end

    it "validates COLR structure" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      colr = font.table("COLR")

      expect(colr.valid?).to be true
    end

    it "validates CPAL structure" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      cpal = font.table("CPAL")

      expect(cpal.valid?).to be true
    end

    it "accesses multiple palettes" do
      font = Fontisan::FontLoader.load(font_path, mode: :full)
      cpal = font.table("CPAL")

      # Try to access all available palettes
      (0...cpal.num_palettes).each do |palette_index|
        palette = cpal.palette(palette_index)
        expect(palette).not_to be_nil
        expect(palette.length).to eq(cpal.num_palette_entries)
      end
    end

    it "reports COLR/CPAL in FontInfo" do
      info = Fontisan.info(font_path)
      expect(info.is_color_font).to be true
      expect(info.color_glyphs).to be > 0
      expect(info.color_palettes).to be > 0
    end
  end

  describe "FontInfo integration with COLR/CPAL" do
    it "detects COLR/CPAL in TwemojiMozilla" do
      info = Fontisan.info(
        font_fixture_path("TwemojiMozilla", "Twemoji.Mozilla.ttf")
      )

      expect(info.is_color_font).to be true
      expect(info.color_glyphs).to be > 0
      expect(info.color_palettes).to be > 0
      expect(info.colors_per_palette).to be > 0
    end

    it "serializes COLR/CPAL info to YAML" do
      info = Fontisan.info(
        font_fixture_path("TwemojiMozilla", "Twemoji.Mozilla.ttf")
      )

      yaml = info.to_yaml
      expect(yaml).to include("is_color_font: true")
      expect(yaml).to include("color_glyphs:")
      expect(yaml).to include("color_palettes:")
    end

    it "serializes COLR/CPAL info to JSON" do
      info = Fontisan.info(
        font_fixture_path("TwemojiMozilla", "Twemoji.Mozilla.ttf")
      )

      json = info.to_json
      expect(json).to include('"is_color_font":true')
      expect(json).to include('"color_glyphs":')
    end
  end

  describe "FontInfo integration with SVG" do
    it "detects SVG in EmojiOneColor" do
      info = Fontisan.info(
        font_fixture_path("EmojiOneColor", "EmojiOneColor.otf")
      )

      expect(info.has_svg_table).to be true
      expect(info.svg_glyph_count).to be > 0
    end

    it "serializes SVG info to YAML" do
      info = Fontisan.info(
        font_fixture_path("EmojiOneColor", "EmojiOneColor.otf")
      )

      yaml = info.to_yaml
      expect(yaml).to include("has_svg_table: true")
      expect(yaml).to include("svg_glyph_count:")
    end

    it "serializes SVG info to JSON" do
      info = Fontisan.info(
        font_fixture_path("EmojiOneColor", "EmojiOneColor.otf")
      )

      json = info.to_json
      expect(json).to include('"has_svg_table":true')
      expect(json).to include('"svg_glyph_count":')
    end
  end

  describe "Color format detection" do
    it "distinguishes SVG vs COLR/CPAL fonts" do
      # SVG font
      svg_info = Fontisan.info(
        font_fixture_path("EmojiOneColor", "EmojiOneColor.otf")
      )
      expect(svg_info.has_svg_table).to be true
      # is_color_font is nil for SVG-only fonts (it specifically refers to COLR/CPAL)
      expect(svg_info.is_color_font).to be_nil

      # COLR/CPAL font
      colr_info = Fontisan.info(
        font_fixture_path("TwemojiMozilla", "Twemoji.Mozilla.ttf")
      )
      expect(colr_info.is_color_font).to be true
      # has_svg_table can be falsy (nil or false) for fonts without SVG
      expect(colr_info.has_svg_table).to be_falsy
    end

    it "detects different SVG fonts correctly" do
      # Twitter emoji (TTF with SVG)
      twitter_info = Fontisan.info(
        font_fixture_path("TwitterColorEmoji", "TwitterColorEmoji-SVGinOT.ttf")
      )
      expect(twitter_info.has_svg_table).to be true

      # Gilbert (CFF with SVG)
      gilbert_info = Fontisan.info(
        font_fixture_path("Gilbert", "Gilbert-Color Bold Preview5.otf")
      )
      expect(gilbert_info.has_svg_table).to be true
    end
  end

  describe "Error handling" do
    it "handles missing SVG documents gracefully" do
      font = Fontisan::FontLoader.load(
        font_fixture_path("EmojiOneColor", "EmojiOneColor.otf"),
        mode: :full
      )
      svg = font.table("SVG ")

      # Try to access non-existent glyph ID
      doc = svg.svg_for_glyph(999999)
      expect(doc).to be_nil
    end

    it "handles invalid palette index gracefully" do
      font = Fontisan::FontLoader.load(
        font_fixture_path("TwemojiMozilla", "Twemoji.Mozilla.ttf"),
        mode: :full
      )
      cpal = font.table("CPAL")

      # Try to access non-existent palette
      palette = cpal.palette(999)
      expect(palette).to be_nil
    end
  end
end
