# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::MetricsCalculator do
  # Test fixtures acknowledgment:
  # Using Libertinus fonts (OFL licensed) from:
  # https://github.com/alerque/libertinus
  # Copyright © 2012-2023 The Libertinus Project Authors

  # Helper to create a mock font with specified tables
  def create_mock_font(tables = {})
    font = double("Font")
    allow(font).to receive(:table) do |tag|
      tables[tag]
    end
    font
  end

  # Helper to create mock hhea table
  def create_mock_hhea(ascent: 2048, descent: -512, line_gap: 90,
                       number_of_h_metrics: 256)
    hhea = double("Fontisan::Tables::Hhea")
    allow(hhea).to receive_messages(ascent: ascent, descent: descent,
                                    line_gap: line_gap, number_of_h_metrics: number_of_h_metrics)
    hhea
  end

  # Helper to create mock head table
  def create_mock_head(units_per_em: 2048)
    head = double("Fontisan::Tables::Head")
    allow(head).to receive(:units_per_em).and_return(units_per_em)
    head
  end

  # Helper to create mock maxp table
  def create_mock_maxp(num_glyphs: 256)
    maxp = double("Fontisan::Tables::Maxp")
    allow(maxp).to receive(:num_glyphs).and_return(num_glyphs)
    maxp
  end

  # Helper to create mock hmtx table
  def create_mock_hmtx(metrics: {}, parsed: true)
    hmtx = double("Fontisan::Tables::Hmtx")
    allow(hmtx).to receive(:parse_with_context)
    allow(hmtx).to receive(:parsed?).and_return(parsed)
    allow(hmtx).to receive(:metric_for) do |glyph_id|
      metrics[glyph_id]
    end
    hmtx
  end

  # Helper to create mock cmap table
  def create_mock_cmap(unicode_mappings: {})
    cmap = double("Fontisan::Tables::Cmap")
    allow(cmap).to receive(:unicode_mappings).and_return(unicode_mappings)
    cmap
  end

  describe "#initialize" do
    it "requires a font parameter" do
      expect { described_class.new(nil) }.to raise_error(
        ArgumentError,
        "Font cannot be nil",
      )
    end

    it "accepts a valid font object" do
      font = create_mock_font
      calculator = described_class.new(font)
      expect(calculator.font).to eq(font)
    end
  end

  describe "#ascent" do
    it "returns ascent from hhea table" do
      hhea = create_mock_hhea(ascent: 2048)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      expect(calculator.ascent).to eq(2048)
    end

    it "returns nil when hhea table is missing" do
      font = create_mock_font
      calculator = described_class.new(font)

      expect(calculator.ascent).to be_nil
    end

    it "handles typical TrueType ascent values" do
      hhea = create_mock_hhea(ascent: 1900)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      expect(calculator.ascent).to eq(1900)
    end

    it "handles typical PostScript ascent values" do
      hhea = create_mock_hhea(ascent: 850)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      expect(calculator.ascent).to eq(850)
    end
  end

  describe "#descent" do
    it "returns descent from hhea table" do
      hhea = create_mock_hhea(descent: -512)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      expect(calculator.descent).to eq(-512)
    end

    it "returns nil when hhea table is missing" do
      font = create_mock_font
      calculator = described_class.new(font)

      expect(calculator.descent).to be_nil
    end

    it "handles typical negative descent values" do
      hhea = create_mock_hhea(descent: -400)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      expect(calculator.descent).to eq(-400)
    end
  end

  describe "#line_gap" do
    it "returns line gap from hhea table" do
      hhea = create_mock_hhea(line_gap: 90)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      expect(calculator.line_gap).to eq(90)
    end

    it "returns nil when hhea table is missing" do
      font = create_mock_font
      calculator = described_class.new(font)

      expect(calculator.line_gap).to be_nil
    end

    it "handles zero line gap" do
      hhea = create_mock_hhea(line_gap: 0)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      expect(calculator.line_gap).to eq(0)
    end
  end

  describe "#units_per_em" do
    it "returns units per em from head table" do
      head = create_mock_head(units_per_em: 2048)
      font = create_mock_font("head" => head)
      calculator = described_class.new(font)

      expect(calculator.units_per_em).to eq(2048)
    end

    it "returns nil when head table is missing" do
      font = create_mock_font
      calculator = described_class.new(font)

      expect(calculator.units_per_em).to be_nil
    end

    it "handles typical TrueType units (2048)" do
      head = create_mock_head(units_per_em: 2048)
      font = create_mock_font("head" => head)
      calculator = described_class.new(font)

      expect(calculator.units_per_em).to eq(2048)
    end

    it "handles typical PostScript units (1000)" do
      head = create_mock_head(units_per_em: 1000)
      font = create_mock_font("head" => head)
      calculator = described_class.new(font)

      expect(calculator.units_per_em).to eq(1000)
    end
  end

  describe "#glyph_width" do
    it "returns advance width for a glyph" do
      hhea = create_mock_hhea(number_of_h_metrics: 256)
      maxp = create_mock_maxp(num_glyphs: 256)
      hmtx = create_mock_hmtx(metrics: {
                                42 => { advance_width: 1234, lsb: 50 },
                              })
      font = create_mock_font("hhea" => hhea, "maxp" => maxp, "hmtx" => hmtx)
      calculator = described_class.new(font)

      expect(calculator.glyph_width(42)).to eq(1234)
    end

    it "returns nil when hmtx table is missing" do
      font = create_mock_font
      calculator = described_class.new(font)

      expect(calculator.glyph_width(42)).to be_nil
    end

    it "returns nil for invalid glyph ID" do
      hhea = create_mock_hhea(number_of_h_metrics: 256)
      maxp = create_mock_maxp(num_glyphs: 256)
      hmtx = create_mock_hmtx(metrics: {})
      font = create_mock_font("hhea" => hhea, "maxp" => maxp, "hmtx" => hmtx)
      calculator = described_class.new(font)

      expect(calculator.glyph_width(999)).to be_nil
    end

    it "parses hmtx table on first access" do
      hhea = create_mock_hhea(number_of_h_metrics: 256)
      maxp = create_mock_maxp(num_glyphs: 256)
      hmtx = create_mock_hmtx(
        metrics: { 42 => { advance_width: 1234, lsb: 50 } },
        parsed: false,
      )
      font = create_mock_font("hhea" => hhea, "maxp" => maxp, "hmtx" => hmtx)
      calculator = described_class.new(font)

      expect(hmtx).to receive(:parse_with_context).with(256, 256).once
      calculator.glyph_width(42)
    end

    it "does not reparse hmtx table on subsequent access" do
      hhea = create_mock_hhea(number_of_h_metrics: 256)
      maxp = create_mock_maxp(num_glyphs: 256)
      hmtx = create_mock_hmtx(metrics: {
                                42 => { advance_width: 1234, lsb: 50 },
                                43 => { advance_width: 1500, lsb: 60 },
                              })
      font = create_mock_font("hhea" => hhea, "maxp" => maxp, "hmtx" => hmtx)
      calculator = described_class.new(font)

      expect(hmtx).to receive(:parse_with_context).once
      calculator.glyph_width(42)
      calculator.glyph_width(43)
    end
  end

  describe "#glyph_advance_width" do
    it "is an alias for glyph_width" do
      hhea = create_mock_hhea(number_of_h_metrics: 256)
      maxp = create_mock_maxp(num_glyphs: 256)
      hmtx = create_mock_hmtx(metrics: {
                                42 => { advance_width: 1234, lsb: 50 },
                              })
      font = create_mock_font("hhea" => hhea, "maxp" => maxp, "hmtx" => hmtx)
      calculator = described_class.new(font)

      expect(calculator.glyph_advance_width(42)).to eq(1234)
      expect(calculator.glyph_advance_width(42)).to eq(calculator.glyph_width(42))
    end
  end

  describe "#glyph_left_side_bearing" do
    it "returns left side bearing for a glyph" do
      hhea = create_mock_hhea(number_of_h_metrics: 256)
      maxp = create_mock_maxp(num_glyphs: 256)
      hmtx = create_mock_hmtx(metrics: {
                                42 => { advance_width: 1234, lsb: 50 },
                              })
      font = create_mock_font("hhea" => hhea, "maxp" => maxp, "hmtx" => hmtx)
      calculator = described_class.new(font)

      expect(calculator.glyph_left_side_bearing(42)).to eq(50)
    end

    it "returns nil when hmtx table is missing" do
      font = create_mock_font
      calculator = described_class.new(font)

      expect(calculator.glyph_left_side_bearing(42)).to be_nil
    end

    it "handles negative left side bearings" do
      hhea = create_mock_hhea(number_of_h_metrics: 256)
      maxp = create_mock_maxp(num_glyphs: 256)
      hmtx = create_mock_hmtx(metrics: {
                                42 => { advance_width: 1234, lsb: -50 },
                              })
      font = create_mock_font("hhea" => hhea, "maxp" => maxp, "hmtx" => hmtx)
      calculator = described_class.new(font)

      expect(calculator.glyph_left_side_bearing(42)).to eq(-50)
    end
  end

  describe "#string_width" do
    let(:hhea) { create_mock_hhea(number_of_h_metrics: 256) }
    let(:maxp) { create_mock_maxp(num_glyphs: 256) }
    let(:head) { create_mock_head(units_per_em: 2048) }

    it "calculates total width for a string" do
      # A=65, B=66, C=67
      cmap = create_mock_cmap(unicode_mappings: {
                                65 => 10,
                                66 => 11,
                                67 => 12,
                              })
      hmtx = create_mock_hmtx(metrics: {
                                10 => { advance_width: 1000, lsb: 50 },
                                11 => { advance_width: 900, lsb: 40 },
                                12 => { advance_width: 1100, lsb: 60 },
                              })
      font = create_mock_font(
        "hhea" => hhea,
        "maxp" => maxp,
        "head" => head,
        "hmtx" => hmtx,
        "cmap" => cmap,
      )
      calculator = described_class.new(font)

      expect(calculator.string_width("ABC")).to eq(3000)
    end

    it "returns 0 for empty string" do
      font = create_mock_font(
        "hhea" => hhea,
        "maxp" => maxp,
        "head" => head,
        "hmtx" => create_mock_hmtx,
        "cmap" => create_mock_cmap,
      )
      calculator = described_class.new(font)

      expect(calculator.string_width("")).to eq(0)
    end

    it "returns 0 for nil string" do
      font = create_mock_font(
        "hhea" => hhea,
        "maxp" => maxp,
        "head" => head,
        "hmtx" => create_mock_hmtx,
        "cmap" => create_mock_cmap,
      )
      calculator = described_class.new(font)

      expect(calculator.string_width(nil)).to eq(0)
    end

    it "skips unmapped characters" do
      # H=72, e=101, l=108, o=111
      cmap = create_mock_cmap(unicode_mappings: {
                                72 => 10,  # H
                                101 => 11, # e
                                # l missing
                                111 => 12, # o
                              })
      hmtx = create_mock_hmtx(metrics: {
                                10 => { advance_width: 1000, lsb: 50 },
                                11 => { advance_width: 800, lsb: 40 },
                                12 => { advance_width: 900, lsb: 60 },
                              })
      font = create_mock_font(
        "hhea" => hhea,
        "maxp" => maxp,
        "head" => head,
        "hmtx" => hmtx,
        "cmap" => cmap,
      )
      calculator = described_class.new(font)

      # "Hello" = H(1000) + e(800) + l(skip) + l(skip) + o(900) = 2700
      expect(calculator.string_width("Hello")).to eq(2700)
    end

    it "returns nil when metrics are not available" do
      font = create_mock_font
      calculator = described_class.new(font)

      expect(calculator.string_width("Hello")).to be_nil
    end

    it "handles repeated characters" do
      # A=65
      cmap = create_mock_cmap(unicode_mappings: { 65 => 10 })
      hmtx = create_mock_hmtx(metrics: {
                                10 => { advance_width: 1000, lsb: 50 },
                              })
      font = create_mock_font(
        "hhea" => hhea,
        "maxp" => maxp,
        "head" => head,
        "hmtx" => hmtx,
        "cmap" => cmap,
      )
      calculator = described_class.new(font)

      expect(calculator.string_width("AAA")).to eq(3000)
    end

    it "handles Unicode characters" do
      # €=8364
      cmap = create_mock_cmap(unicode_mappings: { 8364 => 10 })
      hmtx = create_mock_hmtx(metrics: {
                                10 => { advance_width: 1200, lsb: 50 },
                              })
      font = create_mock_font(
        "hhea" => hhea,
        "maxp" => maxp,
        "head" => head,
        "hmtx" => hmtx,
        "cmap" => cmap,
      )
      calculator = described_class.new(font)

      expect(calculator.string_width("€")).to eq(1200)
    end
  end

  describe "#line_height" do
    it "calculates line height as ascent - descent + line_gap" do
      hhea = create_mock_hhea(ascent: 2048, descent: -512, line_gap: 90)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      # 2048 - (-512) + 90 = 2650
      expect(calculator.line_height).to eq(2650)
    end

    it "returns nil when hhea table is missing" do
      font = create_mock_font
      calculator = described_class.new(font)

      expect(calculator.line_height).to be_nil
    end

    it "handles zero line gap" do
      hhea = create_mock_hhea(ascent: 1900, descent: -400, line_gap: 0)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      # 1900 - (-400) + 0 = 2300
      expect(calculator.line_height).to eq(2300)
    end

    it "handles typical TrueType values" do
      hhea = create_mock_hhea(ascent: 1900, descent: -400, line_gap: 100)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      # 1900 - (-400) + 100 = 2400
      expect(calculator.line_height).to eq(2400)
    end
  end

  describe "#em_height" do
    it "is an alias for units_per_em" do
      head = create_mock_head(units_per_em: 2048)
      font = create_mock_font("head" => head)
      calculator = described_class.new(font)

      expect(calculator.em_height).to eq(2048)
      expect(calculator.em_height).to eq(calculator.units_per_em)
    end
  end

  describe "#has_metrics?" do
    it "returns true when all required tables are present" do
      hhea = create_mock_hhea
      hmtx = create_mock_hmtx
      head = create_mock_head
      maxp = create_mock_maxp
      font = create_mock_font(
        "hhea" => hhea,
        "hmtx" => hmtx,
        "head" => head,
        "maxp" => maxp,
      )
      calculator = described_class.new(font)

      expect(calculator.has_metrics?).to be true
    end

    it "returns false when hhea table is missing" do
      hmtx = create_mock_hmtx
      head = create_mock_head
      maxp = create_mock_maxp
      font = create_mock_font("hmtx" => hmtx, "head" => head, "maxp" => maxp)
      calculator = described_class.new(font)

      expect(calculator.has_metrics?).to be false
    end

    it "returns false when hmtx table is missing" do
      hhea = create_mock_hhea
      head = create_mock_head
      maxp = create_mock_maxp
      font = create_mock_font("hhea" => hhea, "head" => head, "maxp" => maxp)
      calculator = described_class.new(font)

      expect(calculator.has_metrics?).to be false
    end

    it "returns false when head table is missing" do
      hhea = create_mock_hhea
      hmtx = create_mock_hmtx
      maxp = create_mock_maxp
      font = create_mock_font("hhea" => hhea, "hmtx" => hmtx, "maxp" => maxp)
      calculator = described_class.new(font)

      expect(calculator.has_metrics?).to be false
    end

    it "returns false when maxp table is missing" do
      hhea = create_mock_hhea
      hmtx = create_mock_hmtx
      head = create_mock_head
      font = create_mock_font("hhea" => hhea, "hmtx" => hmtx, "head" => head)
      calculator = described_class.new(font)

      expect(calculator.has_metrics?).to be false
    end

    it "returns false when all tables are missing" do
      font = create_mock_font
      calculator = described_class.new(font)

      expect(calculator.has_metrics?).to be false
    end
  end

  describe "integration with real fonts" do
    let(:libertinus_serif_path) do
      font_fixture_path("Libertinus", "static/TTF/LibertinusSerif-Regular.ttf")
    end

    context "when using TrueType font" do
      it "successfully calculates metrics from Libertinus Serif" do
        skip "Font file not available" unless File.exist?(libertinus_serif_path)

        font = Fontisan::TrueTypeFont.from_file(libertinus_serif_path)
        calculator = described_class.new(font)

        # Verify has_metrics?
        expect(calculator.has_metrics?).to be true

        # Verify basic metrics
        expect(calculator.ascent).to be > 0
        expect(calculator.descent).to be < 0
        expect(calculator.line_gap).to be >= 0
        expect(calculator.units_per_em).to be > 0

        # Verify line height calculation
        line_height = calculator.line_height
        expect(line_height).to be > 0
        expect(line_height).to eq(calculator.ascent - calculator.descent + calculator.line_gap)

        # Verify em_height alias
        expect(calculator.em_height).to eq(calculator.units_per_em)

        # Verify glyph metrics for .notdef (glyph 0)
        width = calculator.glyph_width(0)
        expect(width).to be >= 0

        lsb = calculator.glyph_left_side_bearing(0)
        expect(lsb).not_to be_nil

        # Verify glyph_advance_width alias
        expect(calculator.glyph_advance_width(0)).to eq(width)
      end

      it "calculates string width for ASCII text" do
        skip "Font file not available" unless File.exist?(libertinus_serif_path)

        font = Fontisan::TrueTypeFont.from_file(libertinus_serif_path)
        calculator = described_class.new(font)

        width = calculator.string_width("Hello")
        expect(width).to be > 0
      end

      it "handles repeated characters correctly" do
        skip "Font file not available" unless File.exist?(libertinus_serif_path)

        font = Fontisan::TrueTypeFont.from_file(libertinus_serif_path)
        calculator = described_class.new(font)

        single_width = calculator.string_width("A")
        triple_width = calculator.string_width("AAA")

        expect(triple_width).to eq(single_width * 3)
      end

      it "returns 0 for empty string" do
        skip "Font file not available" unless File.exist?(libertinus_serif_path)

        font = Fontisan::TrueTypeFont.from_file(libertinus_serif_path)
        calculator = described_class.new(font)

        expect(calculator.string_width("")).to eq(0)
      end
    end

    context "when using OpenType/CFF font" do
      let(:libertinus_serif_otf_path) do
        font_fixture_path("Libertinus", "static/OTF/LibertinusSerif-Regular.otf")
      end

      it "successfully calculates metrics from Libertinus Serif OTF" do
        skip "Font file not available" unless File.exist?(libertinus_serif_otf_path)

        font = Fontisan::OpenTypeFont.from_file(libertinus_serif_otf_path)
        calculator = described_class.new(font)

        # CFF fonts also have horizontal metrics
        expect(calculator.has_metrics?).to be true
        expect(calculator.ascent).to be > 0
        expect(calculator.descent).to be < 0
        expect(calculator.units_per_em).to be > 0
        expect(calculator.line_height).to be > 0
      end
    end
  end

  describe "edge cases and error handling" do
    it "handles font with missing cmap for string_width" do
      hhea = create_mock_hhea(number_of_h_metrics: 256)
      maxp = create_mock_maxp(num_glyphs: 256)
      head = create_mock_head(units_per_em: 2048)
      hmtx = create_mock_hmtx
      # cmap is missing
      font = create_mock_font(
        "hhea" => hhea,
        "maxp" => maxp,
        "head" => head,
        "hmtx" => hmtx,
      )
      calculator = described_class.new(font)

      # Should return 0 since no characters can be mapped
      expect(calculator.string_width("Hello")).to eq(0)
    end

    it "caches table references" do
      hhea = create_mock_hhea
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      expect(font).to receive(:table).with("hhea").once.and_return(hhea)

      # Multiple calls should use cached reference
      calculator.ascent
      calculator.descent
      calculator.line_gap
    end

    it "handles zero units_per_em" do
      head = create_mock_head(units_per_em: 0)
      font = create_mock_font("head" => head)
      calculator = described_class.new(font)

      expect(calculator.units_per_em).to eq(0)
    end

    it "handles maximum int16 values" do
      hhea = create_mock_hhea(ascent: 32767, descent: -32768, line_gap: 32767)
      font = create_mock_font("hhea" => hhea)
      calculator = described_class.new(font)

      expect(calculator.ascent).to eq(32767)
      expect(calculator.descent).to eq(-32768)
      expect(calculator.line_gap).to eq(32767)
    end
  end
end
