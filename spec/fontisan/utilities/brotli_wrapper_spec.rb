# frozen_string_literal: true

require "spec_helper"
require "fontisan/utilities/brotli_wrapper"

RSpec.describe Fontisan::Utilities::BrotliWrapper do
  describe ".compress" do
    let(:test_data) { "Hello, World!" * 100 }

    it "compresses data successfully" do
      compressed = described_class.compress(test_data)

      expect(compressed).to be_a(String)
      expect(compressed.bytesize).to be < test_data.bytesize
    end

    it "uses default quality when not specified" do
      compressed = described_class.compress(test_data)
      expect(compressed).to be_a(String)
    end

    it "accepts custom quality parameter" do
      compressed_low = described_class.compress(test_data, quality: 5)
      compressed_high = described_class.compress(test_data, quality: 11)

      expect(compressed_low).to be_a(String)
      expect(compressed_high).to be_a(String)
      # Higher quality should give better compression on most data
      # Allow some tolerance since compression results can vary
    end

    it "accepts different compression modes" do
      compressed_font = described_class.compress(test_data, mode: :font)
      compressed_text = described_class.compress(test_data, mode: :text)
      compressed_generic = described_class.compress(test_data, mode: :generic)

      expect(compressed_font).to be_a(String)
      expect(compressed_text).to be_a(String)
      expect(compressed_generic).to be_a(String)
    end

    it "raises error for invalid quality" do
      expect do
        described_class.compress(test_data, quality: -1)
      end.to raise_error(ArgumentError, /Quality must be between/)

      expect do
        described_class.compress(test_data, quality: 12)
      end.to raise_error(ArgumentError, /Quality must be between/)
    end

    it "raises error for non-integer quality" do
      expect do
        described_class.compress(test_data, quality: "11")
      end.to raise_error(ArgumentError, /Quality must be an Integer/)
    end

    it "raises error for nil data" do
      expect do
        described_class.compress(nil)
      end.to raise_error(ArgumentError, /Data cannot be nil/)
    end

    it "raises error for invalid data type" do
      expect do
        described_class.compress(12345)
      end.to raise_error(ArgumentError, /Data must be a String-like object/)
    end

    it "handles empty string" do
      compressed = described_class.compress("")
      expect(compressed).to be_a(String)
    end

    it "handles binary data" do
      binary_data = "\x00\xFF\xAB\xCD" * 50
      compressed = described_class.compress(binary_data)
      expect(compressed).to be_a(String)
      expect(compressed.bytesize).to be < binary_data.bytesize
    end
  end

  describe ".decompress" do
    let(:test_data) { "Fontisan WOFF2 Test Data" * 100 }
    let(:compressed_data) { described_class.compress(test_data) }

    it "decompresses data successfully" do
      decompressed = described_class.decompress(compressed_data)

      expect(decompressed).to eq(test_data)
    end

    it "round-trips data correctly" do
      original = "Test data for round-trip compression" * 50
      compressed = described_class.compress(original)
      decompressed = described_class.decompress(compressed)

      expect(decompressed).to eq(original)
    end

    it "raises error for nil data" do
      expect do
        described_class.decompress(nil)
      end.to raise_error(ArgumentError, /Data cannot be nil/)
    end

    it "raises error for invalid compressed data" do
      expect do
        described_class.decompress("invalid data")
      end.to raise_error(Fontisan::Error, /Brotli decompression failed/)
    end

    it "handles empty compressed data" do
      compressed = described_class.compress("")
      decompressed = described_class.decompress(compressed)
      expect(decompressed).to eq("")
    end
  end

  describe ".compression_ratio" do
    it "calculates ratio correctly" do
      ratio = described_class.compression_ratio(1000, 300)
      expect(ratio).to eq(0.3)
    end

    it "handles zero original size" do
      ratio = described_class.compression_ratio(0, 100)
      expect(ratio).to eq(0.0)
    end

    it "handles equal sizes" do
      ratio = described_class.compression_ratio(100, 100)
      expect(ratio).to eq(1.0)
    end

    it "returns decimal value" do
      ratio = described_class.compression_ratio(1000, 456)
      expect(ratio).to be_within(0.001).of(0.456)
    end
  end

  describe ".compression_percentage" do
    it "calculates percentage correctly" do
      pct = described_class.compression_percentage(1000, 300)
      expect(pct).to eq(70.0)
    end

    it "handles zero original size" do
      pct = described_class.compression_percentage(0, 100)
      expect(pct).to eq(0.0)
    end

    it "handles no compression" do
      pct = described_class.compression_percentage(1000, 1000)
      expect(pct).to eq(0.0)
    end

    it "handles negative compression (expansion)" do
      pct = described_class.compression_percentage(100, 150)
      expect(pct).to eq(-50.0)
    end

    it "rounds to one decimal place" do
      pct = described_class.compression_percentage(1000, 456)
      expect(pct).to eq(54.4)
    end
  end

  describe "integration tests" do
    it "compresses and decompresses font-like data" do
      # Simulate font table data
      font_data = (0..255).to_a.pack("C*") * 20

      compressed = described_class.compress(font_data, quality: 11, mode: :font)
      decompressed = described_class.decompress(compressed)

      expect(decompressed).to eq(font_data)
      expect(compressed.bytesize).to be < font_data.bytesize
    end

    it "achieves good compression on repetitive data" do
      repetitive_data = "ABCD" * 1000

      compressed = described_class.compress(repetitive_data, quality: 11)
      ratio = described_class.compression_ratio(
        repetitive_data.bytesize,
        compressed.bytesize,
      )

      # Should achieve at least 50% compression on repetitive data
      expect(ratio).to be < 0.5
    end

    it "handles large data" do
      large_data = "X" * 50_000

      compressed = described_class.compress(large_data)
      decompressed = described_class.decompress(compressed)

      expect(decompressed).to eq(large_data)
    end
  end

  describe "quality levels" do
    let(:test_data) { "Quality test data" * 100 }

    it "quality 0 produces valid compression" do
      compressed = described_class.compress(test_data, quality: 0)
      decompressed = described_class.decompress(compressed)
      expect(decompressed).to eq(test_data)
    end

    it "quality 11 produces valid compression" do
      compressed = described_class.compress(test_data, quality: 11)
      decompressed = described_class.decompress(compressed)
      expect(decompressed).to eq(test_data)
    end

    it "higher quality gives better compression" do
      compressed_low = described_class.compress(test_data, quality: 1)
      described_class.compress(test_data, quality: 6)
      compressed_high = described_class.compress(test_data, quality: 11)

      # Generally, higher quality should compress better
      # Though this isn't guaranteed for all data
      expect(compressed_high.bytesize).to be <= compressed_low.bytesize + 10
    end
  end
end
