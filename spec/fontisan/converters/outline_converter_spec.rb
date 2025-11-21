# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Converters::OutlineConverter do
  let(:converter) { described_class.new }
  let(:ttf_font) { double("TrueTypeFont") }
  let(:otf_font) { double("OpenTypeFont") }

  before do
    # Setup TTF font mock
    allow(ttf_font).to receive(:has_table?).with("glyf").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("loca").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("CFF ").and_return(false)
    allow(ttf_font).to receive(:has_table?).with("CFF2").and_return(false)
    allow(ttf_font).to receive(:table).with("glyf").and_return(double)
    allow(ttf_font).to receive(:table).with("loca").and_return(double)
    allow(ttf_font).to receive(:table).with("head").and_return(double)
    allow(ttf_font).to receive(:table).with("hhea").and_return(double)
    allow(ttf_font).to receive(:table).with("maxp").and_return(double)
    allow(ttf_font).to receive(:table).with("CFF ").and_return(nil)
    allow(ttf_font).to receive(:table).with("CFF2").and_return(nil)
    allow(ttf_font).to receive_messages(tables: {}, table_data: {})

    # Setup OTF font mock
    allow(otf_font).to receive(:has_table?).with("glyf").and_return(false)
    allow(otf_font).to receive(:has_table?).with("CFF ").and_return(true)
    allow(otf_font).to receive(:has_table?).with("CFF2").and_return(false)
    allow(otf_font).to receive(:table).with("CFF ").and_return(double)
    allow(otf_font).to receive(:table).with("CFF2").and_return(nil)
    allow(otf_font).to receive(:table).with("glyf").and_return(nil)
    allow(otf_font).to receive(:table).with("head").and_return(double)
    allow(otf_font).to receive(:table).with("hhea").and_return(double)
    allow(otf_font).to receive(:table).with("maxp").and_return(double)
    allow(otf_font).to receive_messages(tables: {}, table_data: {})
  end

  describe "#convert" do
    context "TTF to OTF conversion" do
      it "raises NotImplementedError with explanation" do
        expect do
          converter.convert(ttf_font, target_format: :otf)
        end.to raise_error(NotImplementedError,
                           /TTF to OTF.*CFF table generation/)
      end

      it "explains what needs to be implemented" do
        converter.convert(ttf_font, target_format: :otf)
      rescue NotImplementedError => e
        expect(e.message).to include("CFF INDEX")
        expect(e.message).to include("CharStrings")
        expect(e.message).to include("DICT")
      end
    end

    context "OTF to TTF conversion" do
      it "raises NotImplementedError with explanation" do
        expect do
          converter.convert(otf_font, target_format: :ttf)
        end.to raise_error(NotImplementedError, /OTF to TTF.*glyf\/loca/)
      end

      it "explains what needs to be implemented" do
        converter.convert(otf_font, target_format: :ttf)
      rescue NotImplementedError => e
        expect(e.message).to include("glyf/loca table generation")
        expect(e.message).to include("cubic-to-quadratic")
      end
    end

    context "with invalid parameters" do
      it "raises ArgumentError for nil font" do
        expect do
          converter.convert(nil, target_format: :otf)
        end.to raise_error(ArgumentError, /Font cannot be nil/)
      end

      it "raises ArgumentError for font without tables method" do
        invalid_font = double("InvalidFont")
        allow(invalid_font).to receive(:table).and_return(double)

        expect do
          converter.convert(invalid_font, target_format: :otf)
        end.to raise_error(ArgumentError, /must respond to :tables/)
      end
    end
  end

  describe "#supported_conversions" do
    it "includes TTF to OTF" do
      conversions = converter.supported_conversions
      expect(conversions).to include(%i[ttf otf])
    end

    it "includes OTF to TTF" do
      conversions = converter.supported_conversions
      expect(conversions).to include(%i[otf ttf])
    end

    it "does not include same-format conversions" do
      conversions = converter.supported_conversions
      expect(conversions).not_to include(%i[ttf ttf])
      expect(conversions).not_to include(%i[otf otf])
    end
  end

  describe "#validate" do
    context "with valid fonts" do
      it "validates TTF to OTF conversion" do
        expect do
          converter.validate(ttf_font, :otf)
        end.not_to raise_error
      end

      it "validates OTF to TTF conversion" do
        expect do
          converter.validate(otf_font, :ttf)
        end.not_to raise_error
      end
    end

    context "with invalid fonts" do
      it "rejects nil font" do
        expect do
          converter.validate(nil, :otf)
        end.to raise_error(ArgumentError, /Font cannot be nil/)
      end

      it "rejects unsupported conversion" do
        allow(ttf_font).to receive(:table).with("loca").and_return(nil)

        expect do
          converter.validate(ttf_font, :svg)
        end.to raise_error(Fontisan::Error, /not supported/)
      end
    end

    context "with missing required tables" do
      it "rejects TTF without glyf table" do
        # Keep has_table? true so format detection works
        # But make table() return nil so validation fails
        allow(ttf_font).to receive(:table).with("glyf").and_return(nil)

        expect do
          converter.validate(ttf_font, :otf)
        end.to raise_error(Fontisan::MissingTableError, /glyf or loca/)
      end

      it "rejects TTF without loca table" do
        allow(ttf_font).to receive(:has_table?).with("loca").and_return(false)
        allow(ttf_font).to receive(:table).with("loca").and_return(nil)

        expect do
          converter.validate(ttf_font, :otf)
        end.to raise_error(Fontisan::MissingTableError, /glyf or loca/)
      end

      it "rejects OTF without CFF table" do
        # Keep has_table? true for format detection
        # But make table() return nil for validation failure
        allow(otf_font).to receive(:table).with("CFF ").and_return(nil)

        expect do
          converter.validate(otf_font, :ttf)
        end.to raise_error(Fontisan::MissingTableError, /CFF/)
      end

      it "rejects font without head table" do
        allow(ttf_font).to receive(:table).with("head").and_return(nil)

        expect do
          converter.validate(ttf_font, :otf)
        end.to raise_error(Fontisan::MissingTableError, /head/)
      end
    end
  end

  describe "#supports?" do
    it "returns true for TTF to OTF" do
      expect(converter.supports?(:ttf, :otf)).to be true
    end

    it "returns true for OTF to TTF" do
      expect(converter.supports?(:otf, :ttf)).to be true
    end

    it "returns false for TTF to TTF" do
      expect(converter.supports?(:ttf, :ttf)).to be false
    end

    it "returns false for OTF to OTF" do
      expect(converter.supports?(:otf, :otf)).to be false
    end
  end

  describe "curve conversion mathematics" do
    describe "#quadratic_to_cubic" do
      it "converts quadratic Bézier to cubic Bézier" do
        p0 = { x: 0, y: 0 }
        p1 = { x: 50, y: 100 }
        p2 = { x: 100, y: 0 }

        cp1, cp2 = converter.send(:quadratic_to_cubic, p0, p1, p2)

        # Verify control points are between start/end and control
        expect(cp1[:x]).to be_between(p0[:x], p1[:x])
        expect(cp2[:x]).to be_between(p1[:x], p2[:x])
      end

      it "uses 2/3 ratio for control point calculation" do
        p0 = { x: 0, y: 0 }
        p1 = { x: 60, y: 90 }
        p2 = { x: 120, y: 0 }

        cp1, = converter.send(:quadratic_to_cubic, p0, p1, p2)

        # CP1 = P0 + 2/3 * (P1 - P0)
        expected_cp1_x = 0 + (2.0 / 3.0) * 60
        expected_cp1_y = 0 + (2.0 / 3.0) * 90

        expect(cp1[:x]).to eq(expected_cp1_x.round)
        expect(cp1[:y]).to eq(expected_cp1_y.round)
      end
    end

    describe "#cubic_to_quadratic" do
      it "approximates cubic Bézier as quadratic" do
        p0 = { x: 0, y: 0 }
        cp1 = { x: 30, y: 100 }
        cp2 = { x: 70, y: 100 }
        p3 = { x: 100, y: 0 }

        control = converter.send(:cubic_to_quadratic, p0, cp1, cp2, p3)

        # Control point should be between cubic control points
        expect(control[:x]).to be_between(cp1[:x], cp2[:x])
        expect(control[:y]).to eq(100)
      end

      it "uses midpoint of cubic control points" do
        p0 = { x: 0, y: 0 }
        cp1 = { x: 40, y: 80 }
        cp2 = { x: 60, y: 80 }
        p3 = { x: 100, y: 0 }

        control = converter.send(:cubic_to_quadratic, p0, cp1, cp2, p3)

        expected_x = ((40 + 60) / 2.0).round
        expected_y = ((80 + 80) / 2.0).round

        expect(control[:x]).to eq(expected_x)
        expect(control[:y]).to eq(expected_y)
      end
    end
  end

  describe "format detection" do
    it "detects TTF from glyf table" do
      format = converter.send(:detect_format, ttf_font)
      expect(format).to eq(:ttf)
    end

    it "detects OTF from CFF table" do
      format = converter.send(:detect_format, otf_font)
      expect(format).to eq(:otf)
    end

    it "prefers CFF over CFF2" do
      allow(otf_font).to receive(:table).with("CFF2").and_return(double)
      format = converter.send(:detect_format, otf_font)
      expect(format).to eq(:otf)
    end

    it "raises error for unknown format" do
      unknown_font = double("UnknownFont")
      allow(unknown_font).to receive_messages(has_table?: false, table: nil)

      expect do
        converter.send(:detect_format, unknown_font)
      end.to raise_error(Fontisan::Error, /Cannot detect font format/)
    end
  end
end
