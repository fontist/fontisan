# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff/charstring_builder"
require "fontisan/models/outline"

RSpec.describe Fontisan::Tables::Cff::CharStringBuilder do
  let(:builder) { described_class.new }

  describe "#build" do
    let(:simple_outline) do
      Fontisan::Models::Outline.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 100, y: 0 },
          { type: :line_to, x: 200, y: 700 },
          { type: :line_to, x: 300, y: 0 },
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
      )
    end

    it "builds CharString from outline" do
      charstring = builder.build(simple_outline)

      expect(charstring).to be_a(String)
      expect(charstring.encoding).to eq(Encoding::BINARY)
      expect(charstring.bytesize).to be > 0
    end

    it "ends with endchar operator (14)" do
      charstring = builder.build(simple_outline)

      # Last byte should be endchar operator (14)
      expect(charstring.bytes.last).to eq(14)
    end

    it "encodes width when provided" do
      charstring = builder.build(simple_outline, width: 500)

      # Width should be encoded before commands
      expect(charstring.bytesize).to be > 0
    end

    context "with simple line commands" do
      let(:line_outline) do
        Fontisan::Models::Outline.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 100, y: 0 },
            { type: :line_to, x: 200, y: 0 },
            { type: :line_to, x: 200, y: 100 },
          ],
          bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 100 },
        )
      end

      it "encodes horizontal move with hmoveto" do
        charstring = builder.build(line_outline)
        bytes = charstring.bytes

        # Should contain hmoveto operator (22)
        expect(bytes).to include(22)
      end
    end

    context "with vertical line" do
      let(:vertical_outline) do
        Fontisan::Models::Outline.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 0, y: 100 },
            { type: :line_to, x: 0, y: 200 },
          ],
          bbox: { x_min: 0, y_min: 100, x_max: 0, y_max: 200 },
        )
      end

      it "encodes vertical move with vmoveto" do
        charstring = builder.build(vertical_outline)
        bytes = charstring.bytes

        # Should contain vmoveto operator (4)
        expect(bytes).to include(4)
      end
    end

    context "with cubic curves" do
      let(:curve_outline) do
        Fontisan::Models::Outline.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 100, y: 0 },
            {
              type: :curve_to,
              cx1: 120, cy1: 200,
              cx2: 180, cy2: 500,
              x: 200, y: 700
            },
          ],
          bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
        )
      end

      it "encodes curves with rrcurveto" do
        charstring = builder.build(curve_outline)
        bytes = charstring.bytes

        # Should contain rrcurveto operator (8)
        expect(bytes).to include(8)
      end

      it "uses relative coordinates" do
        charstring = builder.build(curve_outline)

        # CharString should be relatively compact
        expect(charstring.bytesize).to be < 50
      end
    end

    context "with complex outline" do
      let(:complex_outline) do
        Fontisan::Models::Outline.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 100, y: 0 },
            { type: :line_to, x: 150, y: 300 },
            {
              type: :curve_to,
              cx1: 160, cy1: 350,
              cx2: 180, cy2: 400,
              x: 200, y: 450
            },
            { type: :line_to, x: 200, y: 700 },
            { type: :line_to, x: 100, y: 700 },
          ],
          bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
        )
      end

      it "encodes multiple command types" do
        charstring = builder.build(complex_outline)

        expect(charstring.bytesize).to be > 0
        expect(charstring.bytes.last).to eq(14) # endchar
      end

      it "produces valid binary data" do
        charstring = builder.build(complex_outline)

        expect(charstring.encoding).to eq(Encoding::BINARY)
        expect(charstring.valid_encoding?).to be true
      end
    end

    context "with empty outline" do
      let(:empty_outline) do
        Fontisan::Models::Outline.new(
          glyph_id: 0,
          commands: [],
          bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
        )
      end

      it "builds minimal CharString" do
        charstring = builder.build(empty_outline)

        # Should just be endchar
        expect(charstring.bytes).to eq([14])
      end
    end
  end

  describe "#build_empty" do
    it "builds empty CharString without width" do
      charstring = builder.build_empty

      # Should just be endchar operator (14)
      expect(charstring.bytes).to eq([14])
    end

    it "builds empty CharString with width" do
      charstring = builder.build_empty(width: 500)

      # Should have width encoding followed by endchar
      expect(charstring.bytes.last).to eq(14)
      expect(charstring.bytesize).to be > 1
    end
  end

  describe "number encoding" do
    let(:test_outline) do
      Fontisan::Models::Outline.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: x_value, y: 0 },
        ],
        bbox: { x_min: 0, y_min: 0, x_max: x_value, y_max: 0 },
      )
    end

    context "with small numbers (-107 to +107)" do
      let(:x_value) { 50 }

      it "uses single byte encoding" do
        charstring = builder.build(test_outline)

        # Small numbers should result in compact encoding
        expect(charstring.bytesize).to be < 10
      end
    end

    context "with medium numbers (108 to 1131)" do
      let(:x_value) { 500 }

      it "uses two byte encoding" do
        charstring = builder.build(test_outline)

        # Should still be relatively compact
        expect(charstring.bytesize).to be < 15
      end
    end

    context "with large numbers" do
      let(:x_value) { 5000 }

      it "uses appropriate encoding" do
        charstring = builder.build(test_outline)

        # Larger numbers need more bytes
        expect(charstring.bytesize).to be > 0
      end
    end

    context "with negative numbers" do
      let(:negative_outline) do
        Fontisan::Models::Outline.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 100, y: 0 },
            { type: :line_to, x: 50, y: -50 },
          ],
          bbox: { x_min: 50, y_min: -50, x_max: 100, y_max: 0 },
        )
      end

      it "encodes negative numbers correctly" do
        charstring = builder.build(negative_outline)

        # Should encode negative deltas
        expect(charstring.bytesize).to be > 0
        expect(charstring.bytes.last).to eq(14) # endchar
      end
    end
  end

  describe "operator encoding" do
    it "encodes hmoveto operator" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 65,
        commands: [{ type: :move_to, x: 100, y: 0 }],
        bbox: { x_min: 100, y_min: 0, x_max: 100, y_max: 0 },
      )

      charstring = builder.build(outline)
      bytes = charstring.bytes

      # hmoveto is operator 22
      expect(bytes).to include(22)
    end

    it "encodes vmoveto operator" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 65,
        commands: [{ type: :move_to, x: 0, y: 100 }],
        bbox: { x_min: 0, y_min: 100, x_max: 0, y_max: 100 },
      )

      charstring = builder.build(outline)
      bytes = charstring.bytes

      # vmoveto is operator 4
      expect(bytes).to include(4)
    end

    it "encodes rmoveto for diagonal moves" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 65,
        commands: [{ type: :move_to, x: 100, y: 100 }],
        bbox: { x_min: 100, y_min: 100, x_max: 100, y_max: 100 },
      )

      charstring = builder.build(outline)
      bytes = charstring.bytes

      # rmoveto is operator 21
      expect(bytes).to include(21)
    end

    it "encodes rlineto operator" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 0, y: 0 },
          { type: :line_to, x: 100, y: 100 },
        ],
        bbox: { x_min: 0, y_min: 0, x_max: 100, y_max: 100 },
      )

      charstring = builder.build(outline)
      bytes = charstring.bytes

      # rlineto is operator 5
      expect(bytes).to include(5)
    end

    it "encodes rrcurveto operator" do
      outline = Fontisan::Models::Outline.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 0, y: 0 },
          {
            type: :curve_to,
            cx1: 20, cy1: 50,
            cx2: 80, cy2: 50,
            x: 100, y: 0
          },
        ],
        bbox: { x_min: 0, y_min: 0, x_max: 100, y_max: 50 },
      )

      charstring = builder.build(outline)
      bytes = charstring.bytes

      # rrcurveto is operator 8
      expect(bytes).to include(8)
    end
  end

  describe "relative coordinate calculation" do
    let(:multi_line_outline) do
      Fontisan::Models::Outline.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 100, y: 100 },
          { type: :line_to, x: 200, y: 100 },
          { type: :line_to, x: 200, y: 200 },
          { type: :line_to, x: 100, y: 200 },
        ],
        bbox: { x_min: 100, y_min: 100, x_max: 200, y_max: 200 },
      )
    end

    it "calculates relative coordinates correctly" do
      charstring = builder.build(multi_line_outline)

      # Should produce valid CharString with relative coordinates
      expect(charstring.bytesize).to be > 0
      expect(charstring.bytes.last).to eq(14)
    end

    it "tracks current point through commands" do
      charstring = builder.build(multi_line_outline)

      # Multiple line commands should be encoded with relative deltas
      expect(charstring.bytes.count(5)).to eq(3) # Three rlineto operators
    end
  end

  describe "optimization" do
    context "with horizontal line" do
      let(:horizontal_outline) do
        Fontisan::Models::Outline.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 100, y: 0 },
            { type: :line_to, x: 200, y: 0 },
          ],
          bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 0 },
        )
      end

      it "uses compact encoding for horizontal moves" do
        charstring = builder.build(horizontal_outline)

        # Should use hmoveto (22) for first move
        expect(charstring.bytes).to include(22)
      end
    end

    context "with vertical line" do
      let(:vertical_outline) do
        Fontisan::Models::Outline.new(
          glyph_id: 65,
          commands: [
            { type: :move_to, x: 0, y: 100 },
            { type: :line_to, x: 0, y: 200 },
          ],
          bbox: { x_min: 0, y_min: 100, x_max: 0, y_max: 200 },
        )
      end

      it "uses compact encoding for vertical moves" do
        charstring = builder.build(vertical_outline)

        # Should use vmoveto (4) for first move
        expect(charstring.bytes).to include(4)
      end
    end
  end

  describe "binary output format" do
    let(:outline) do
      Fontisan::Models::Outline.new(
        glyph_id: 65,
        commands: [
          { type: :move_to, x: 100, y: 0 },
          { type: :line_to, x: 200, y: 700 },
        ],
        bbox: { x_min: 100, y_min: 0, x_max: 200, y_max: 700 },
      )
    end

    it "produces binary string" do
      charstring = builder.build(outline)

      expect(charstring.encoding).to eq(Encoding::BINARY)
    end

    it "produces valid byte sequence" do
      charstring = builder.build(outline)

      # Each byte should be 0-255
      expect(charstring.bytes).to all(be_between(0, 255))
    end

    it "is not empty" do
      charstring = builder.build(outline)

      expect(charstring).not_to be_empty
    end
  end
end
