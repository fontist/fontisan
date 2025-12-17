# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/delta_parser"

RSpec.describe Fontisan::Variation::DeltaParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "with zero deltas" do
      it "returns array of zero deltas for nil data" do
        deltas = parser.parse(nil, 5)
        expect(deltas).to eq([
          { x: 0, y: 0 },
          { x: 0, y: 0 },
          { x: 0, y: 0 },
          { x: 0, y: 0 },
          { x: 0, y: 0 }
        ])
      end

      it "returns array of zero deltas for empty data" do
        deltas = parser.parse("", 3)
        expect(deltas).to eq([
          { x: 0, y: 0 },
          { x: 0, y: 0 },
          { x: 0, y: 0 }
        ])
      end
    end

    context "with byte deltas" do
      it "parses simple byte deltas" do
        # Control byte (0x00 = bytes), 3 X deltas, 3 Y deltas
        data = [0x00, 10, -5, 3, 0x00, 2, -1, 4].pack("C*")
        deltas = parser.parse(data, 3)

        expect(deltas).to eq([
          { x: 10, y: 2 },
          { x: -5, y: -1 },
          { x: 3, y: 4 }
        ])
      end

      it "handles signed byte conversion" do
        # Byte 200 should be -56 when signed
        data = [0x00, 200, 0x00, 200].pack("C*")
        deltas = parser.parse(data, 1)

        expect(deltas[0][:x]).to eq(-56)
        expect(deltas[0][:y]).to eq(-56)
      end
    end

    context "with word deltas" do
      it "parses word deltas" do
        # Control byte with DELTAS_ARE_WORDS flag (0x40)
        # 2 X deltas as words, 2 Y deltas as words
        x_data = [0x40] + [1000, -500].pack("n*").bytes
        y_data = [0x40] + [300, -200].pack("n*").bytes
        data = (x_data + y_data).pack("C*")

        deltas = parser.parse(data, 2)

        expect(deltas[0][:x]).to eq(1000)
        expect(deltas[0][:y]).to eq(300)
        expect(deltas[1][:x]).to eq(-500)
        expect(deltas[1][:y]).to eq(-200)
      end

      it "handles large signed word values" do
        # 0xFFFF should be -1 when signed
        x_data = [0x40, 0xFF, 0xFF].pack("C*")
        y_data = [0x40, 0x80, 0x00].pack("C*")  # 0x8000 = -32768
        data = x_data + y_data

        deltas = parser.parse(data, 1)

        expect(deltas[0][:x]).to eq(-1)
        expect(deltas[0][:y]).to eq(-32768)
      end
    end

    context "with private point numbers" do
      it "applies deltas only to specified points" do
        # Point count: 3
        # Point numbers: 0, 2, 4 stored as deltas (0, +2, +2)
        # X deltas: 10, 20, 30
        # Y deltas: 5, 15, 25
        point_data = [3, 0x02, 0, 2, 2].pack("C*")  # Deltas: 0, +2, +2 → points 0, 2, 4
        x_data = [0x00, 10, 20, 30].pack("C*")
        y_data = [0x00, 5, 15, 25].pack("C*")
        data = point_data + x_data + y_data

        deltas = parser.parse(data, 6, private_points: true)

        expect(deltas).to eq([
          { x: 10, y: 5 },   # Point 0
          { x: 0, y: 0 },    # Point 1 (untouched)
          { x: 20, y: 15 },  # Point 2
          { x: 0, y: 0 },    # Point 3 (untouched)
          { x: 30, y: 25 },  # Point 4
          { x: 0, y: 0 }     # Point 5 (untouched)
        ])
      end
    end

    context "with shared point numbers" do
      it "uses shared point numbers for deltas" do
        shared_points = [1, 3, 5]
        x_data = [0x00, 10, 20, 30].pack("C*")
        y_data = [0x00, 5, 15, 25].pack("C*")
        data = x_data + y_data

        deltas = parser.parse(data, 7, shared_points: shared_points)

        expect(deltas).to eq([
          { x: 0, y: 0 },    # Point 0
          { x: 10, y: 5 },   # Point 1
          { x: 0, y: 0 },    # Point 2
          { x: 20, y: 15 },  # Point 3
          { x: 0, y: 0 },    # Point 4
          { x: 30, y: 25 },  # Point 5
          { x: 0, y: 0 }     # Point 6
        ])
      end
    end
  end

  describe "#parse_with_flags" do
    it "returns zero deltas when DELTAS_ARE_ZERO flag set" do
      flags = described_class::DELTAS_ARE_ZERO
      deltas = parser.parse_with_flags("dummy_data", 4, flags)

      expect(deltas).to eq([
        { x: 0, y: 0 },
        { x: 0, y: 0 },
        { x: 0, y: 0 },
        { x: 0, y: 0 }
      ])
    end

    it "parses normally when flag not set" do
      flags = 0
      data = [0x00, 10, 0x00, 5].pack("C*")
      deltas = parser.parse_with_flags(data, 1, flags)

      expect(deltas[0][:x]).to eq(10)
      expect(deltas[0][:y]).to eq(5)
    end
  end

  describe "error handling" do
    it "returns zero deltas on parse error" do
      # Invalid data that will cause parse error
      invalid_data = [0xFF].pack("C") * 5

      expect do
        deltas = parser.parse(invalid_data, 10)
        expect(deltas.length).to eq(10)
        expect(deltas.all? { |d| d[:x] == 0 && d[:y] == 0 }).to be true
      end.not_to raise_error
    end

    it "handles truncated data gracefully" do
      # Control byte indicating words but insufficient data
      data = [0x40, 0x00].pack("C*")  # Only 1 byte of word data

      deltas = parser.parse(data, 5)
      expect(deltas.length).to eq(5)
    end
  end

  describe "edge cases" do
    it "handles single point" do
      data = [0x00, 10, 0x00, 5].pack("C*")
      deltas = parser.parse(data, 1)

      expect(deltas).to eq([{ x: 10, y: 5 }])
    end

    it "handles zero point count" do
      data = [0x00].pack("C*")
      deltas = parser.parse(data, 0)

      expect(deltas).to eq([])
    end

    it "handles all points having same delta" do
      # All points get delta (10, 5)
      data = [0x00, 10, 10, 10, 0x00, 5, 5, 5].pack("C*")
      deltas = parser.parse(data, 3)

      expect(deltas).to eq([
        { x: 10, y: 5 },
        { x: 10, y: 5 },
        { x: 10, y: 5 }
      ])
    end
  end
end
