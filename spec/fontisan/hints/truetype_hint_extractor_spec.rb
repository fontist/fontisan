# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Hints::TrueTypeHintExtractor do
  let(:extractor) { described_class.new }

  describe "#extract_from_font" do
    context "with a font containing hint tables" do
      let(:font) { Fontisan::FontLoader.load(font_fixture_path("noto-sans", "NotoSans-Regular.ttf")) }

      it "returns a HintSet" do
        result = extractor.extract_from_font(font)
        expect(result).to be_a(Fontisan::Models::HintSet)
      end

      it "sets format to truetype" do
        result = extractor.extract_from_font(font)
        expect(result.format).to eq("truetype")
      end

      it "extracts font program if present" do
        result = extractor.extract_from_font(font)
        # DejaVuSans has fpgm table
        if font.has_table?("fpgm")
          expect(result.font_program).not_to be_empty
          expect(result.font_program.encoding.name).to eq("ASCII-8BIT")
        end
      end

      it "extracts control value program if present" do
        result = extractor.extract_from_font(font)
        # DejaVuSans has prep table
        if font.has_table?("prep")
          expect(result.control_value_program).not_to be_empty
          expect(result.control_value_program.encoding.name).to eq("ASCII-8BIT")
        end
      end

      it "extracts control values if present" do
        result = extractor.extract_from_font(font)
        # DejaVuSans has cvt table
        if font.has_table?("cvt ")
          expect(result.control_values).to be_an(Array)
          expect(result.control_values).not_to be_empty
          expect(result.control_values.first).to be_an(Integer)
        end
      end

      it "sets has_hints flag appropriately" do
        result = extractor.extract_from_font(font)
        # DejaVuSans has hints
        expect(result.has_hints).to be true
      end
    end

    context "with a font without hint tables" do
      # Some fonts may not have hinting tables
      it "returns empty HintSet without errors" do
        font = instance_double(Fontisan::TrueTypeFont)
        allow(font).to receive(:has_table?).and_return(false)
        allow(font).to receive(:table).and_return(nil)

        result = extractor.extract_from_font(font)
        expect(result).to be_a(Fontisan::Models::HintSet)
        expect(result.font_program).to be_empty
        expect(result.control_value_program).to be_empty
        expect(result.control_values).to be_empty
      end
    end
  end

  describe "#extract" do
    context "with glyph instructions" do
      it "extracts interpolation hints from IUP_Y" do
        glyph = double(
          "glyph",
          instructions: [0x30], # IUP_Y
          empty?: false
        )

        hints = extractor.extract(glyph)
        expect(hints).not_to be_empty
        expect(hints.first.type).to eq(:interpolate)
        expect(hints.first.data[:axis]).to eq(:y)
      end

      it "extracts interpolation hints from IUP_X" do
        glyph = double(
          "glyph",
          instructions: [0x31], # IUP_X
          empty?: false
        )

        hints = extractor.extract(glyph)
        expect(hints).not_to be_empty
        expect(hints.first.type).to eq(:interpolate)
        expect(hints.first.data[:axis]).to eq(:x)
      end

      it "returns empty array for empty glyph" do
        glyph = double("glyph", empty?: true)
        hints = extractor.extract(glyph)
        expect(hints).to be_empty
      end

      it "returns empty array for glyph without instructions" do
        glyph = double("glyph", empty?: false, instructions: nil)
        hints = extractor.extract(glyph)
        expect(hints).to be_empty
      end
    end
  end

  describe "private methods" do
    describe "#extract_control_values" do
      it "parses signed 16-bit integers from cvt table" do
        font = instance_double(Fontisan::TrueTypeFont)
        allow(font).to receive(:has_table?).with("cvt ").and_return(true)

        # Create sample CVT data: two 16-bit signed integers
        # 100 (positive) and -50 (negative)
        cvt_data = [100, 65536 - 50].pack("n*")
        allow(font).to receive(:instance_variable_get)
          .with(:@table_data)
          .and_return({ "cvt " => cvt_data })

        values = extractor.send(:extract_control_values, font)
        expect(values).to eq([100, -50])
      end
    end
  end
end