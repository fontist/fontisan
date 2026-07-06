# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Fontisan::Woff2::UInt255 do
  describe ".encode / .decode round-trip" do
    boundary_values = [0, 1, 100, 252, 253, 254, 300, 505, 506, 507, 600,
                       761, 762, 763, 1000, 5000, 65_535]

    boundary_values.each do |v|
      it "round-trips #{v}" do
        encoded = described_class.encode(v)
        decoded = described_class.decode(StringIO.new(encoded))
        expect(decoded).to eq(v)
      end
    end

    it "round-trips every value 250..260 (boundary between literal and multi-byte)" do
      (250..260).each do |v|
        encoded = described_class.encode(v)
        decoded = described_class.decode(StringIO.new(encoded))
        expect(decoded).to eq(v), "value #{v} encoded as #{encoded.unpack1('H*')} decoded as #{decoded}"
      end
    end

    it "round-trips every value 503..510 (boundary between code 255 and 254)" do
      (503..510).each do |v|
        encoded = described_class.encode(v)
        decoded = described_class.decode(StringIO.new(encoded))
        expect(decoded).to eq(v), "value #{v} failed"
      end
    end

    it "round-trips every value 759..765 (boundary between code 254 and 253)" do
      (759..765).each do |v|
        encoded = described_class.encode(v)
        decoded = described_class.decode(StringIO.new(encoded))
        expect(decoded).to eq(v), "value #{v} failed"
      end
    end
  end

  describe ".encode — matches fontTools byte-for-byte" do
    # fontTools pack255UShort docstring examples
    it "encodes 252 as single byte 0xFC" do
      expect(described_class.encode(252).unpack1("H*")).to eq("fc")
    end

    it "encodes 506 as code 254 + byte 0 (2 bytes)" do
      expect(described_class.encode(506).unpack1("H*")).to eq("fe00")
    end

    it "encodes 762 as code 253 + uint16 (3 bytes)" do
      expect(described_class.encode(762).unpack1("H*")).to eq("fd02fa")
    end

    # Specific variant ranges per spec
    it "uses code 255 (1 byte + 253) for values 253..505" do
      expect(described_class.encode(253).unpack1("H*")).to eq("ff00")
      expect(described_class.encode(505).unpack1("H*")).to eq("fffc")
    end

    it "uses code 254 (1 byte + 506) for values 506..761" do
      expect(described_class.encode(506).unpack1("H*")).to eq("fe00")
      expect(described_class.encode(761).unpack1("H*")).to eq("feff")
    end

    it "uses code 253 (uint16) for values 762..65535" do
      expect(described_class.encode(762).unpack1("H*")).to eq("fd02fa")
      expect(described_class.encode(65535).unpack1("H*")).to eq("fdffff")
    end

    it "uses literal for values 0..252" do
      expect(described_class.encode(0).unpack1("H*")).to eq("00")
      expect(described_class.encode(252).unpack1("H*")).to eq("fc")
    end
  end

  describe ".decode — matches fontTools multi-encoding acceptance" do
    # fontTools unpack255UShort accepts multiple encodings for the same value.
    # Per spec: "An encoder may produce any of these, and a decoder MUST
    # accept them all."

    it "decodes 506 from code 254, byte 0" do
      expect(described_class.decode(StringIO.new("\xFE\x00"))).to eq(506)
    end

    it "decodes 506 from code 255, byte 253" do
      expect(described_class.decode(StringIO.new("\xFF\xFD"))).to eq(506)
    end

    it "decodes 506 from code 253, uint16 506" do
      expect(described_class.decode(StringIO.new("\xFD\x01\xFA"))).to eq(506)
    end
  end

  describe ".decode_at" do
    it "decodes from a flat String at the given position" do
      data = String.new(encoding: Encoding::BINARY)
      data << "\x00\x00"
      data << described_class.encode(300)
      data << "\xFF".b
      value, pos = described_class.decode_at(data, 2)
      expect(value).to eq(300)
      expect(pos).to eq(4) # 300 encodes as 2 bytes (code 255 + byte)
    end
  end

  describe ".encode — rejects out-of-range values" do
    it "raises ArgumentError for negative values" do
      expect { described_class.encode(-1) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for values > 65535" do
      expect { described_class.encode(65_536) }.to raise_error(ArgumentError)
    end
  end
end
