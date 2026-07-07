# frozen_string: true

require "spec_helper"

RSpec.describe Fontisan::Utilities::Padding do
  describe ".boundary" do
    it "returns 0 when size is a multiple of boundary" do
      expect(described_class.boundary(16)).to eq(0)
      expect(described_class.boundary(8)).to eq(0)
      expect(described_class.boundary(0)).to eq(0)
    end

    it "returns the bytes needed to reach the next boundary" do
      expect(described_class.boundary(1)).to eq(3)
      expect(described_class.boundary(2)).to eq(2)
      expect(described_class.boundary(3)).to eq(1)
      expect(described_class.boundary(15)).to eq(1)
    end

    it "accepts a custom boundary" do
      expect(described_class.boundary(3, boundary: 8)).to eq(5)
      expect(described_class.boundary(8, boundary: 8)).to eq(0)
    end

    it "accepts a String-like input (uses #bytesize)" do
      expect(described_class.boundary("abc")).to eq(1)
      expect(described_class.boundary("abcd")).to eq(0)
      expect(described_class.boundary("")).to eq(0)
    end
  end

  describe ".pad" do
    it "returns the original string when already aligned" do
      input = "abcd"
      expect(described_class.pad(input)).to be(input)
    end

    it "returns a new binary string with trailing nulls when unaligned" do
      result = described_class.pad("abc")
      expect(result.encoding).to eq(Encoding::BINARY)
      expect(result.bytes).to eq([0x61, 0x62, 0x63, 0x00])
    end

    it "respects a custom boundary" do
      result = described_class.pad("ab", boundary: 4)
      expect(result.bytes).to eq([0x61, 0x62, 0x00, 0x00])
    end

    it "does not mutate the input" do
      input = "abc"
      original = input.dup
      described_class.pad(input)
      expect(input).to eq(original)
    end

    it "handles empty input" do
      expect(described_class.pad("")).to eq("")
    end
  end

  describe ".aligned_size" do
    it "returns the size after alignment" do
      expect(described_class.aligned_size(0)).to eq(0)
      expect(described_class.aligned_size(1)).to eq(4)
      expect(described_class.aligned_size(4)).to eq(4)
      expect(described_class.aligned_size(13)).to eq(16)
    end

    it "accepts a String-like input" do
      expect(described_class.aligned_size("abc")).to eq(4)
      expect(described_class.aligned_size("abcd")).to eq(4)
    end
  end
end
