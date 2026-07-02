# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Meta do
  describe ".build" do
    it "returns nil for nil data" do
      expect(described_class.build(data: nil)).to be_nil
    end

    it "returns nil for empty data" do
      expect(described_class.build(data: {})).to be_nil
    end

    it "produces a valid meta v1 header" do
      bytes = described_class.build(data: { "dlng" => "en" })
      version, _flags, data_maps_count, _data_offset = bytes.unpack("NNNN")
      expect(version).to eq(1)
      expect(data_maps_count).to eq(1)
    end

    it "encodes tag, offset, and length in each data map" do
      bytes = described_class.build(data: { "dlng" => "en-Latn" })
      # header(16) + 1 data map(12)
      tag, offset, length = bytes[16, 12].unpack("a4NN")
      expect(tag).to eq("dlng")
      expect(offset).to eq(28) # 16 + 12
      expect(length).to eq(7)  # "en-Latn"
    end

    it "appends data values after the data maps" do
      bytes = described_class.build(data: { "dlng" => "en-Latn", "slng" => "en" })
      # Header(16) + 2 data maps(24) = 40 bytes before data
      dlng_data = bytes[40, 7]
      slng_data = bytes[47, 2]
      expect(dlng_data).to eq("en-Latn")
      expect(slng_data).to eq("en")
    end
  end
end
