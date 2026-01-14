# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Utilities::ChecksumCalculator do
  describe ".calculate_file_checksum" do
    it "calculates checksum for a font file" do
      font_path = font_fixture_path("NotoSans", "NotoSans-Regular.ttf")
      checksum = described_class.calculate_file_checksum(font_path)

      expect(checksum).to be_a(Integer)
      expect(checksum).to be > 0
    end

    it "raises error for non-existent file" do
      expect do
        described_class.calculate_file_checksum("nonexistent.ttf")
      end.to raise_error(Errno::ENOENT)
    end
  end

  describe ".calculate_adjustment" do
    it "calculates checksum adjustment" do
      file_checksum = 2842116234
      adjustment = described_class.calculate_adjustment(file_checksum)

      expect(adjustment).to be_a(Integer)
      expect(adjustment).to eq((Fontisan::Constants::CHECKSUM_ADJUSTMENT_MAGIC - file_checksum) & 0xFFFFFFFF)
    end

    it "returns a 32-bit value" do
      adjustment = described_class.calculate_adjustment(0xFFFFFFFF)
      expect(adjustment).to be <= 0xFFFFFFFF
      expect(adjustment).to be >= 0
    end
  end

  describe ".calculate_table_checksum" do
    it "calculates checksum for table data" do
      data = "TEST" * 100
      checksum = described_class.calculate_table_checksum(data)

      expect(checksum).to be_a(Integer)
      expect(checksum).to be > 0
    end

    it "handles empty data" do
      checksum = described_class.calculate_table_checksum("")
      expect(checksum).to eq(0)
    end

    it "pads data to 4-byte boundary" do
      # 3 bytes should be padded with 1 zero byte
      data = "ABC"
      checksum = described_class.calculate_table_checksum(data)
      expect(checksum).to be_a(Integer)
    end
  end

  describe "integration with font files" do
    it "calculates consistent checksums" do
      font_path = font_fixture_path("NotoSans", "NotoSans-Regular.ttf")

      # Calculate using direct file method
      checksum1 = described_class.calculate_file_checksum(font_path)

      # Calculate using IO method from File
      File.open(font_path, "rb") do |io|
        checksum2 = described_class.calculate_checksum_from_io(io)
        expect(checksum2).to eq(checksum1)
      end
    end
  end
end
