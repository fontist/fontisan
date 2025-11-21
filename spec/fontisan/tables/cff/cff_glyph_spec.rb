# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff::CFFGlyph do
  # Create mock objects for testing
  let(:glyph_id) { 42 }

  let(:mock_charstring) do
    double(
      "CharString",
      path: [
        { type: :move_to, x: 100.0, y: 200.0 },
        { type: :line_to, x: 300.0, y: 200.0 },
        { type: :line_to, x: 300.0, y: 400.0 },
        { type: :line_to, x: 100.0, y: 400.0 },
      ],
      width: 500,
      bounding_box: [100.0, 200.0, 300.0, 400.0],
      to_commands: [
        [:move_to, 100.0, 200.0],
        [:line_to, 300.0, 200.0],
        [:line_to, 300.0, 400.0],
        [:line_to, 100.0, 400.0],
      ],
    )
  end

  let(:mock_charset) do
    double(
      "Charset",
      glyph_name: "A",
    )
  end

  let(:mock_encoding) do
    double("Encoding")
  end

  let(:cff_glyph) do
    described_class.new(glyph_id, mock_charstring, mock_charset,
                        mock_encoding)
  end

  describe "#initialize" do
    it "accepts glyph_id, charstring, charset, and encoding" do
      expect do
        described_class.new(glyph_id, mock_charstring, mock_charset,
                            mock_encoding)
      end.not_to raise_error
    end

    it "accepts nil encoding" do
      expect do
        described_class.new(glyph_id, mock_charstring, mock_charset, nil)
      end.not_to raise_error
    end

    it "stores the glyph_id" do
      expect(cff_glyph.glyph_id).to eq(glyph_id)
    end

    it "stores the charstring" do
      expect(cff_glyph.charstring).to eq(mock_charstring)
    end
  end

  describe "#simple?" do
    it "returns true for all CFF glyphs" do
      expect(cff_glyph.simple?).to be true
    end
  end

  describe "#compound?" do
    it "returns false for all CFF glyphs" do
      expect(cff_glyph.compound?).to be false
    end
  end

  describe "#empty?" do
    context "with non-empty path" do
      it "returns false" do
        expect(cff_glyph.empty?).to be false
      end
    end

    context "with empty path" do
      let(:empty_charstring) do
        double("CharString", path: [])
      end

      let(:empty_glyph) do
        described_class.new(0, empty_charstring, mock_charset, mock_encoding)
      end

      it "returns true" do
        expect(empty_glyph.empty?).to be true
      end
    end

    context "with nil charstring" do
      let(:nil_glyph) do
        described_class.new(0, nil, mock_charset, mock_encoding)
      end

      it "returns true" do
        expect(nil_glyph.empty?).to be true
      end
    end
  end

  describe "#bounding_box" do
    it "returns the charstring's bounding box" do
      expect(cff_glyph.bounding_box).to eq([100.0, 200.0, 300.0, 400.0])
    end

    context "with nil charstring" do
      let(:nil_glyph) do
        described_class.new(0, nil, mock_charset, mock_encoding)
      end

      it "returns nil" do
        expect(nil_glyph.bounding_box).to be_nil
      end
    end
  end

  describe "#width" do
    it "returns the charstring's width" do
      expect(cff_glyph.width).to eq(500)
    end

    context "with nil charstring" do
      let(:nil_glyph) do
        described_class.new(0, nil, mock_charset, mock_encoding)
      end

      it "returns nil" do
        expect(nil_glyph.width).to be_nil
      end
    end
  end

  describe "#name" do
    it "returns the glyph name from charset" do
      expect(cff_glyph.name).to eq("A")
    end

    context "with nil charset" do
      let(:no_charset_glyph) do
        described_class.new(glyph_id, mock_charstring, nil, mock_encoding)
      end

      it "returns .notdef" do
        expect(no_charset_glyph.name).to eq(".notdef")
      end
    end

    context "when charset returns nil name" do
      let(:nil_name_charset) do
        double("Charset", glyph_name: nil)
      end

      let(:nil_name_glyph) do
        described_class.new(glyph_id, mock_charstring, nil_name_charset,
                            mock_encoding)
      end

      it "returns .notdef as fallback" do
        expect(nil_name_glyph.name).to eq(".notdef")
      end
    end
  end

  describe "#to_commands" do
    it "returns drawing commands from charstring" do
      commands = cff_glyph.to_commands
      expect(commands).to be_an(Array)
      expect(commands.size).to eq(4)
      expect(commands[0]).to eq([:move_to, 100.0, 200.0])
      expect(commands[1]).to eq([:line_to, 300.0, 200.0])
    end

    context "with nil charstring" do
      let(:nil_glyph) do
        described_class.new(0, nil, mock_charset, mock_encoding)
      end

      it "returns empty array" do
        expect(nil_glyph.to_commands).to eq([])
      end
    end
  end

  describe "#path" do
    it "returns the raw path data from charstring" do
      path = cff_glyph.path
      expect(path).to be_an(Array)
      expect(path.size).to eq(4)
      expect(path[0]).to include(type: :move_to, x: 100.0, y: 200.0)
    end

    context "with nil charstring" do
      let(:nil_glyph) do
        described_class.new(0, nil, mock_charset, mock_encoding)
      end

      it "returns empty array" do
        expect(nil_glyph.path).to eq([])
      end
    end
  end

  describe "#to_s" do
    it "returns a human-readable string representation" do
      str = cff_glyph.to_s
      expect(str).to include("CFFGlyph")
      expect(str).to include("gid=42")
      expect(str).to include('name="A"')
      expect(str).to include("width=500")
      expect(str).to include("bbox=[100.0, 200.0, 300.0, 400.0]")
    end
  end

  describe "#inspect" do
    it "returns same as to_s" do
      expect(cff_glyph.inspect).to eq(cff_glyph.to_s)
    end
  end

  describe "API compatibility with TrueType glyphs" do
    it "responds to simple?" do
      expect(cff_glyph).to respond_to(:simple?)
    end

    it "responds to compound?" do
      expect(cff_glyph).to respond_to(:compound?)
    end

    it "responds to empty?" do
      expect(cff_glyph).to respond_to(:empty?)
    end

    it "responds to bounding_box" do
      expect(cff_glyph).to respond_to(:bounding_box)
    end

    it "responds to width" do
      expect(cff_glyph).to respond_to(:width)
    end

    it "responds to name" do
      expect(cff_glyph).to respond_to(:name)
    end

    it "provides consistent API for GlyphAccessor" do
      # Verify CFFGlyph can be used interchangeably with TrueType glyphs
      expect(cff_glyph.simple?).to be(true).or be(false)
      expect(cff_glyph.compound?).to be(true).or be(false)
      expect(cff_glyph.empty?).to be(true).or be(false)
      expect(cff_glyph.bounding_box).to be_a(Array).or be_nil
      expect(cff_glyph.name).to be_a(String)
    end
  end

  describe "curve support" do
    let(:curve_charstring) do
      double(
        "CharString",
        path: [
          { type: :move_to, x: 0.0, y: 0.0 },
          {
            type: :curve_to,
            x1: 100.0, y1: 0.0,
            x2: 100.0, y2: 100.0,
            x: 0.0, y: 100.0
          },
        ],
        width: 200,
        bounding_box: [0.0, 0.0, 100.0, 100.0],
        to_commands: [
          [:move_to, 0.0, 0.0],
          [:curve_to, 100.0, 0.0, 100.0, 100.0, 0.0, 100.0],
        ],
      )
    end

    let(:curve_glyph) do
      described_class.new(1, curve_charstring, mock_charset, mock_encoding)
    end

    it "handles curve commands" do
      commands = curve_glyph.to_commands
      expect(commands[1][0]).to eq(:curve_to)
      expect(commands[1].size).to eq(7) # type + 6 coordinates
    end

    it "includes curve control points in path" do
      path = curve_glyph.path
      curve = path[1]
      expect(curve[:type]).to eq(:curve_to)
      expect(curve).to have_key(:x1)
      expect(curve).to have_key(:y1)
      expect(curve).to have_key(:x2)
      expect(curve).to have_key(:y2)
      expect(curve).to have_key(:x)
      expect(curve).to have_key(:y)
    end
  end
end
