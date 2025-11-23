# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff/index_builder"
require "fontisan/tables/cff/index"

RSpec.describe Fontisan::Tables::Cff::IndexBuilder do
  describe ".build" do
    context "with empty array" do
      it "builds empty INDEX" do
        index_data = described_class.build([])

        expect(index_data).to be_a(String)
        expect(index_data.encoding).to eq(Encoding::BINARY)
        expect(index_data.bytesize).to eq(2) # Just count field
        expect(index_data).to eq("\x00\x00".b)
      end

      it "can be parsed back" do
        index_data = described_class.build([])
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.count).to eq(0)
        expect(index.empty?).to be true
      end
    end

    context "with single item" do
      let(:items) { ["test".b] }

      it "builds valid INDEX" do
        index_data = described_class.build(items)

        expect(index_data).to be_a(String)
        expect(index_data.encoding).to eq(Encoding::BINARY)
        expect(index_data.bytesize).to be > 2
      end

      it "can be parsed back" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.count).to eq(1)
        expect(index[0]).to eq("test".b)
      end

      it "uses single-byte offsets" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        # offSize should be 1 for small data
        expect(index.off_size).to eq(1)
      end
    end

    context "with multiple items" do
      let(:items) { ["first".b, "second".b, "third".b] }

      it "builds valid INDEX" do
        index_data = described_class.build(items)

        expect(index_data).to be_a(String)
        expect(index_data.encoding).to eq(Encoding::BINARY)
      end

      it "can be parsed back" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.count).to eq(3)
        expect(index[0]).to eq("first".b)
        expect(index[1]).to eq("second".b)
        expect(index[2]).to eq("third".b)
      end

      it "preserves item order" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.to_a).to eq(items)
      end
    end

    context "with varying item sizes" do
      let(:items) do
        [
          "a".b,
          "bb".b,
          "ccc".b,
          "dddd".b,
        ]
      end

      it "builds valid INDEX" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.count).to eq(4)
        items.each_with_index do |item, i|
          expect(index[i]).to eq(item)
        end
      end

      it "calculates correct item sizes" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.item_size(0)).to eq(1)
        expect(index.item_size(1)).to eq(2)
        expect(index.item_size(2)).to eq(3)
        expect(index.item_size(3)).to eq(4)
      end
    end

    context "with binary data containing null bytes" do
      let(:items) { ["\x00\x01\x02".b, "\x03\x00\x04".b] }

      it "preserves null bytes" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index[0]).to eq("\x00\x01\x02".b)
        expect(index[1]).to eq("\x03\x00\x04".b)
      end
    end

    context "with large data requiring 2-byte offsets" do
      let(:items) do
        # Create items totaling > 255 bytes to require 2-byte offsets
        Array.new(100) { ("x" * 3).b }
      end

      it "uses 2-byte offsets" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.off_size).to eq(2)
      end

      it "can be parsed back correctly" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.count).to eq(100)
        expect(index[0]).to eq("xxx".b)
        expect(index[99]).to eq("xxx".b)
      end
    end

    context "with large data requiring 3-byte offsets" do
      let(:items) do
        # Create items totaling > 65535 bytes for 3-byte offsets
        Array.new(500) { ("x" * 140).b }
      end

      it "uses 3-byte offsets" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.off_size).to eq(3)
      end

      it "can be parsed back correctly" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.count).to eq(500)
        expect(index[0]).to eq(("x" * 140).b)
        expect(index[499]).to eq(("x" * 140).b)
      end
    end

    context "with empty strings" do
      let(:items) { ["".b, "data".b, "".b] }

      it "handles empty strings correctly" do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)

        expect(index.count).to eq(3)
        expect(index[0]).to eq("".b)
        expect(index[1]).to eq("data".b)
        expect(index[2]).to eq("".b)
        expect(index.item_size(0)).to eq(0)
        expect(index.item_size(2)).to eq(0)
      end
    end

    context "with round-trip validation" do
      let(:test_items) do
        [
          "Hello".b,
          "World".b,
          "\x00\xFF\x80".b,
          "Test Data".b,
        ]
      end

      it "preserves data through build → parse → build cycle" do
        # Build from items
        index_data1 = described_class.build(test_items)

        # Parse back
        index = Fontisan::Tables::Cff::Index.new(index_data1)
        parsed_items = index.to_a

        # Build again from parsed items
        index_data2 = described_class.build(parsed_items)

        # Should be identical
        expect(index_data2).to eq(index_data1)
        expect(parsed_items).to eq(test_items)
      end
    end
  end

  describe "error handling" do
    context "with invalid input type" do
      it "raises ArgumentError for non-Array" do
        expect do
          described_class.build("not an array")
        end.to raise_error(ArgumentError, /items must be Array/)
      end

      it "raises ArgumentError for nil" do
        expect do
          described_class.build(nil)
        end.to raise_error(ArgumentError, /items must be Array/)
      end
    end

    context "with invalid array elements" do
      it "raises ArgumentError for non-String elements" do
        expect do
          described_class.build([123, 456])
        end.to raise_error(ArgumentError, /item 0 must be String/)
      end

      it "raises ArgumentError for mixed types" do
        expect do
          described_class.build(["valid".b, 123])
        end.to raise_error(ArgumentError, /item 1 must be String/)
      end

      it "raises ArgumentError for non-binary encoding" do
        expect do
          described_class.build(["text"]) # UTF-8 string
        end.to raise_error(ArgumentError, /item 0 must have BINARY encoding/)
      end
    end
  end

  describe "offset calculation" do
    it "calculates 1-byte offsets for small data" do
      items = ["a".b] * 10 # Total: 10 bytes
      index_data = described_class.build(items)
      index = Fontisan::Tables::Cff::Index.new(index_data)

      expect(index.off_size).to eq(1)
    end

    it "calculates 2-byte offsets for medium data" do
      items = ["x".b] * 260 # Total: 260 bytes (> 255)
      index_data = described_class.build(items)
      index = Fontisan::Tables::Cff::Index.new(index_data)

      expect(index.off_size).to eq(2)
    end

    it "uses minimal offset size" do
      # Exactly at boundary: 255 bytes → 1-byte offsets
      # 256 bytes → 2-byte offsets
      items_onebyte_boundary = ["x".b] * 254 # 254 bytes + offset 1 = 255 max offset
      items_twobyte_boundary = ["x".b] * 255 # 255 bytes + offset 1 = 256 max offset

      index_onebyte = Fontisan::Tables::Cff::Index.new(described_class.build(items_onebyte_boundary))
      index_twobyte = Fontisan::Tables::Cff::Index.new(described_class.build(items_twobyte_boundary))

      expect(index_onebyte.off_size).to eq(1)
      expect(index_twobyte.off_size).to eq(2)
    end
  end

  describe "binary output format" do
    let(:items) { ["test".b, "data".b] }

    it "produces binary string" do
      index_data = described_class.build(items)

      expect(index_data.encoding).to eq(Encoding::BINARY)
      expect(index_data.valid_encoding?).to be true
    end

    it "has correct structure" do
      index_data = described_class.build(items)

      # Count (2 bytes) + offSize (1 byte) + offsets + data
      expect(index_data.bytesize).to be >= 3
    end

    it "starts with count field" do
      index_data = described_class.build(items)
      count = index_data[0, 2].unpack1("n")

      expect(count).to eq(2)
    end
  end

  describe "performance considerations" do
    it "handles many small items efficiently" do
      items = Array.new(1000) { "x".b }

      expect do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)
        expect(index.count).to eq(1000)
      end.not_to raise_error
    end

    it "handles few large items efficiently" do
      items = Array.new(10) { ("x" * 1000).b }

      expect do
        index_data = described_class.build(items)
        index = Fontisan::Tables::Cff::Index.new(index_data)
        expect(index.count).to eq(10)
      end.not_to raise_error
    end
  end

  describe "integration with Index parser" do
    it "produces output compatible with Index parser" do
      items = ["alpha".b, "beta".b, "gamma".b, "delta".b]
      index_data = described_class.build(items)
      index = Fontisan::Tables::Cff::Index.new(index_data)

      # Verify all parser methods work
      expect(index.count).to eq(4)
      expect(index.empty?).to be false
      expect(index[0]).to eq("alpha".b)
      expect(index[3]).to eq("delta".b)
      expect(index.to_a).to eq(items)

      # Verify iteration
      collected = []
      index.each { |item| collected << item }
      expect(collected).to eq(items)
    end

    it "correctly calculates total size" do
      items = ["one".b, "two".b, "three".b]
      index_data = described_class.build(items)
      index = Fontisan::Tables::Cff::Index.new(index_data)

      expect(index.total_size).to eq(index_data.bytesize)
    end
  end
end
