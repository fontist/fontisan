# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff::Header do
  describe "CFF version 1.0 header" do
    let(:header_data) do
      # CFF 1.0 header: major=1, minor=0, hdr_size=4, off_size=4
      [0x01, 0x00, 0x04, 0x04].pack("C4")
    end

    let(:header) { described_class.read(header_data) }

    it "parses major version correctly" do
      expect(header.major).to eq(1)
    end

    it "parses minor version correctly" do
      expect(header.minor).to eq(0)
    end

    it "parses header size correctly" do
      expect(header.hdr_size).to eq(4)
    end

    it "parses offset size correctly" do
      expect(header.off_size).to eq(4)
    end

    it "identifies as CFF version 1" do
      expect(header.cff?).to be true
      expect(header.cff2?).to be false
    end

    it "returns version string" do
      expect(header.version).to eq("1.0")
    end

    it "is valid" do
      expect(header.valid?).to be true
      expect { header.validate! }.not_to raise_error
    end
  end

  describe "CFF2 header" do
    let(:header_data) do
      # CFF2 header: major=2, minor=0, hdr_size=5, off_size=4
      [0x02, 0x00, 0x05, 0x04].pack("C4")
    end

    let(:header) { described_class.read(header_data) }

    it "parses major version correctly" do
      expect(header.major).to eq(2)
    end

    it "identifies as CFF2" do
      expect(header.cff2?).to be true
      expect(header.cff?).to be false
    end

    it "returns version string" do
      expect(header.version).to eq("2.0")
    end

    it "is valid" do
      expect(header.valid?).to be true
    end
  end

  describe "header with different offset sizes" do
    it "accepts 1-byte offset size" do
      data = [0x01, 0x00, 0x04, 0x01].pack("C4")
      header = described_class.read(data)

      expect(header.off_size).to eq(1)
      expect(header.valid?).to be true
    end

    it "accepts 2-byte offset size" do
      data = [0x01, 0x00, 0x04, 0x02].pack("C4")
      header = described_class.read(data)

      expect(header.off_size).to eq(2)
      expect(header.valid?).to be true
    end

    it "accepts 3-byte offset size" do
      data = [0x01, 0x00, 0x04, 0x03].pack("C4")
      header = described_class.read(data)

      expect(header.off_size).to eq(3)
      expect(header.valid?).to be true
    end

    it "accepts 4-byte offset size" do
      data = [0x01, 0x00, 0x04, 0x04].pack("C4")
      header = described_class.read(data)

      expect(header.off_size).to eq(4)
      expect(header.valid?).to be true
    end
  end

  describe "header with extended size" do
    let(:header_data) do
      # Header with hdr_size=6 (has 2 extra bytes)
      [0x01, 0x00, 0x06, 0x04].pack("C4")
    end

    let(:header) { described_class.read(header_data) }

    it "parses extended header size" do
      expect(header.hdr_size).to eq(6)
      expect(header.valid?).to be true
    end
  end

  describe "validation" do
    it "rejects invalid major version" do
      data = [0x03, 0x00, 0x04, 0x04].pack("C4")
      header = described_class.read(data)

      expect(header.valid?).to be false
      expect do
        header.validate!
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Invalid CFF header/)
    end

    it "rejects invalid minor version" do
      data = [0x01, 0x01, 0x04, 0x04].pack("C4")
      header = described_class.read(data)

      expect(header.valid?).to be false
      expect { header.validate! }.to raise_error(Fontisan::CorruptedTableError)
    end

    it "rejects invalid header size" do
      data = [0x01, 0x00, 0x03, 0x04].pack("C4")
      header = described_class.read(data)

      expect(header.valid?).to be false
      expect { header.validate! }.to raise_error(Fontisan::CorruptedTableError)
    end

    it "rejects invalid offset size (0)" do
      data = [0x01, 0x00, 0x04, 0x00].pack("C4")
      header = described_class.read(data)

      expect(header.valid?).to be false
      expect { header.validate! }.to raise_error(Fontisan::CorruptedTableError)
    end

    it "rejects invalid offset size (5)" do
      data = [0x01, 0x00, 0x04, 0x05].pack("C4")
      header = described_class.read(data)

      expect(header.valid?).to be false
      expect { header.validate! }.to raise_error(Fontisan::CorruptedTableError)
    end
  end

  describe "error handling" do
    it "handles truncated data" do
      data = [0x01, 0x00].pack("C2") # Only 2 bytes instead of 4

      expect { described_class.read(data) }.to raise_error(EOFError)
    end

    it "handles empty data gracefully" do
      # BaseRecord.read returns a new empty instance for empty data
      header = described_class.read("")
      expect(header).to be_a(described_class)
    end
  end
end
