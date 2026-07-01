# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe "CFF2 binary primitives" do
  describe Fontisan::Tables::Cff2::Header do
    it "returns a 5-byte header with version 2.0" do
      bytes = described_class.build(top_dict_size: 42)
      expect(bytes.bytesize).to eq(5)
      major, minor, header_size, top_dict_size = bytes.unpack("CCCn")
      expect(major).to eq(2)
      expect(minor).to eq(0)
      expect(header_size).to eq(5)
      expect(top_dict_size).to eq(42)
    end
  end

  describe Fontisan::Tables::Cff2::IndexBuilder do
    it "returns a 4-byte empty INDEX for no items" do
      bytes = described_class.build([])
      expect(bytes.bytesize).to eq(4)
      expect(bytes.unpack1("N")).to eq(0)
    end

    it "encodes count as uint32 (4 bytes)" do
      bytes = described_class.build(["AAA".b, "BB".b])
      expect(bytes.unpack1("N")).to eq(2)
    end

    it "packs offsets with the smallest sufficient offSize" do
      bytes = described_class.build(["X".b * 300])
      expect(bytes[4].unpack1("C")).to eq(2) # > 255 → offSize 2
    end

    it "uses offSize=1 for small data" do
      bytes = described_class.build(["X".b])
      expect(bytes[4].unpack1("C")).to eq(1)
    end

    it "preserves item data after the header and offsets" do
      items = ["hello".b, "world".b]
      bytes = described_class.build(items)
      data_start = 4 + 1 + (items.size + 1) * 1
      expect(bytes[data_start..]).to eq("helloworld")
    end
  end

  describe Fontisan::Tables::Cff2::DictEncoder do
    it "encodes -107..107 in 1 byte" do
      expect(described_class.encode_integer(0).bytesize).to eq(1)
      expect(described_class.encode_integer(107).bytesize).to eq(1)
      expect(described_class.encode_integer(-107).bytesize).to eq(1)
    end

    it "encodes 108..1131 in 2 bytes" do
      expect(described_class.encode_integer(108).bytesize).to eq(2)
      expect(described_class.encode_integer(1131).bytesize).to eq(2)
    end

    it "encodes large integers in 5 bytes" do
      expect(described_class.encode_integer(100_000).bytesize).to eq(5)
    end

    it "round-trips single-byte integers" do
      byte = described_class.encode_integer(42).unpack1("C")
      expect(byte - 139).to eq(42)
    end

    it "places operands before operator" do
      entry = described_class.encode_entry([42], 17)
      expect(entry.unpack("CC")).to eq([181, 17])
    end

    it "encodes 2-byte operators as [12, xx]" do
      entry = described_class.encode_entry([100], [12, 36])
      expect(entry.bytes.last(2)).to eq([12, 36])
    end
  end
end
