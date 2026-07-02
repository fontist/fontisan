# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff2"

RSpec.describe Fontisan::Tables::Cff2::FdSelect do
  describe ".build" do
    it "returns format 0 for all-same FD assignments" do
      bytes = described_class.build([0, 0, 0, 0])
      expect(bytes.getbyte(0)).to eq(0)
      expect(bytes.bytesize).to eq(5)
    end

    it "encodes per-glyph FD indices in format 0" do
      bytes = described_class.build([0, 1, 1, 0])
      expect(bytes.unpack("C5")).to eq([0, 0, 1, 1, 0])
    end
  end

  describe ".format3_bytes" do
    it "produces range records for clustered assignments" do
      bytes = described_class.format3_bytes([0, 0, 1, 1, 0])
      format, num_ranges = bytes.unpack("Cn")
      expect(format).to eq(3)
      expect(num_ranges).to eq(3)
    end

    it "ends with a sentinel equal to numGlyphs" do
      bytes = described_class.format3_bytes([0, 0, 0])
      expect(bytes[-2, 2].unpack1("n")).to eq(3)
    end
  end
end
