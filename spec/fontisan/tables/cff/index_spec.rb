# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff::Index do
  describe "empty INDEX" do
    let(:data) do
      # count = 0
      [0].pack("n")
    end

    let(:index) { described_class.new(data) }

    it "parses count correctly" do
      expect(index.count).to eq(0)
    end

    it "is empty" do
      expect(index.empty?).to be true
    end

    it "returns empty array" do
      expect(index.to_a).to eq([])
    end

    it "returns nil for any index access" do
      expect(index[0]).to be_nil
      expect(index[1]).to be_nil
    end

    it "iterates zero times" do
      count = 0
      index.each { count += 1 }
      expect(count).to eq(0)
    end

    it "has minimal total size" do
      expect(index.total_size).to eq(2) # Just the count field
    end
  end

  describe "INDEX with single item" do
    let(:data) do
      # count = 1
      # offSize = 1
      # offsets = [1, 6] (item is 5 bytes: "Hello")
      # data = "Hello"
      parts = []
      parts << [1].pack("n")           # count
      parts << [1].pack("C")           # offSize
      parts << [1, 6].pack("C2")       # offsets
      parts << "Hello"                 # data
      parts.join
    end

    let(:index) { described_class.new(data) }

    it "parses count correctly" do
      expect(index.count).to eq(1)
    end

    it "parses offSize correctly" do
      expect(index.off_size).to eq(1)
    end

    it "is not empty" do
      expect(index.empty?).to be false
    end

    it "returns correct item" do
      expect(index[0]).to eq("Hello")
    end

    it "returns nil for out of bounds access" do
      expect(index[1]).to be_nil
      expect(index[-1]).to be_nil
    end

    it "returns correct item size" do
      expect(index.item_size(0)).to eq(5)
    end

    it "iterates correctly" do
      items = []
      index.each { |item| items << item }
      expect(items).to eq(["Hello"])
    end

    it "returns correct array" do
      expect(index.to_a).to eq(["Hello"])
    end

    it "calculates total size correctly" do
      # count(2) + offSize(1) + offsets(2*1) + data(5) = 10
      expect(index.total_size).to eq(10)
    end
  end

  describe "INDEX with multiple items" do
    let(:data) do
      # count = 3
      # offSize = 1
      # offsets = [1, 4, 7, 12] (items: "Foo", "Bar", "Baz!!")
      # data = "FooBarBaz!!"
      parts = []
      parts << [3].pack("n")                    # count
      parts << [1].pack("C")                    # offSize
      parts << [1, 4, 7, 12].pack("C4")         # offsets
      parts << "FooBarBaz!!"                    # data
      parts.join
    end

    let(:index) { described_class.new(data) }

    it "parses count correctly" do
      expect(index.count).to eq(3)
    end

    it "returns correct items" do
      expect(index[0]).to eq("Foo")
      expect(index[1]).to eq("Bar")
      expect(index[2]).to eq("Baz!!")
    end

    it "returns correct item sizes" do
      expect(index.item_size(0)).to eq(3)
      expect(index.item_size(1)).to eq(3)
      expect(index.item_size(2)).to eq(5)
    end

    it "iterates correctly" do
      items = []
      index.each { |item| items << item }
      expect(items).to eq(["Foo", "Bar", "Baz!!"])
    end

    it "returns correct array" do
      expect(index.to_a).to eq(["Foo", "Bar", "Baz!!"])
    end

    it "returns enumerator when no block given" do
      expect(index.each).to be_a(Enumerator)
    end
  end

  describe "INDEX with 2-byte offsets" do
    let(:data) do
      # count = 2
      # offSize = 2
      # offsets = [1, 256, 512] (items of 255 and 256 bytes)
      # data = "A" * 255 + "B" * 256
      parts = []
      parts << [2].pack("n")                   # count
      parts << [2].pack("C")                   # offSize
      parts << [1, 256, 512].pack("n3")        # offsets (big-endian)
      parts << ("A" * 255)
      parts << ("B" * 256)
      parts.join
    end

    let(:index) { described_class.new(data) }

    it "parses count correctly" do
      expect(index.count).to eq(2)
    end

    it "parses offSize correctly" do
      expect(index.off_size).to eq(2)
    end

    it "returns correct item sizes" do
      expect(index.item_size(0)).to eq(255)
      expect(index.item_size(1)).to eq(256)
    end

    it "returns correct items" do
      expect(index[0]).to eq("A" * 255)
      expect(index[1]).to eq("B" * 256)
    end
  end

  describe "INDEX with 4-byte offsets" do
    let(:data) do
      # count = 1
      # offSize = 4
      # offsets = [1, 11] (item is 10 bytes)
      # data = "0123456789"
      parts = []
      parts << [1].pack("n")                    # count
      parts << [4].pack("C")                    # offSize
      parts << [1, 11].pack("N2")               # offsets (big-endian 32-bit)
      parts << "0123456789"                     # data
      parts.join
    end

    let(:index) { described_class.new(data) }

    it "parses offSize correctly" do
      expect(index.off_size).to eq(4)
    end

    it "returns correct item" do
      expect(index[0]).to eq("0123456789")
    end
  end

  describe "INDEX with empty items" do
    let(:data) do
      # count = 2
      # offSize = 1
      # offsets = [1, 1, 6] (first item empty, second is "Hello")
      # data = "Hello"
      parts = []
      parts << [2].pack("n")               # count
      parts << [1].pack("C")               # offSize
      parts << [1, 1, 6].pack("C3")        # offsets
      parts << "Hello"                     # data
      parts.join
    end

    let(:index) { described_class.new(data) }

    it "handles empty first item" do
      expect(index[0]).to eq("")
      expect(index[1]).to eq("Hello")
    end

    it "returns correct item sizes" do
      expect(index.item_size(0)).to eq(0)
      expect(index.item_size(1)).to eq(5)
    end
  end

  describe "validation" do
    it "rejects invalid offSize" do
      data = [1].pack("n") + [0].pack("C") # count=1, offSize=0
      expect do
        described_class.new(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Invalid INDEX offSize/)
    end

    it "rejects offSize greater than 4" do
      data = [1].pack("n") + [5].pack("C") # count=1, offSize=5
      expect do
        described_class.new(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Invalid INDEX offSize/)
    end

    it "rejects first offset not equal to 1" do
      # count = 1, offSize = 1, offsets = [2, 5] (invalid first offset)
      data = "#{[1].pack('n')}#{[1, 2, 5].pack('C3')}ABC"
      expect do
        described_class.new(data)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /first offset must be 1/)
    end

    it "rejects non-ascending offsets" do
      # count = 2, offSize = 1, offsets = [1, 5, 3] (descending)
      data = "#{[2].pack('n')}#{[1, 1, 5, 3].pack('C4')}ABCD"
      expect do
        described_class.new(data)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /not in ascending order/)
    end
  end

  describe "error handling" do
    it "handles truncated count" do
      data = "\x00" # Only 1 byte instead of 2
      expect do
        described_class.new(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Unexpected end/)
    end

    it "handles truncated offset array" do
      # count=2, offSize=1, but only 2 offsets instead of 3
      data = [2].pack("n") + [1, 1, 5].pack("C3")
      expect do
        described_class.new(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Unexpected end/)
    end

    it "handles truncated data section" do
      # count=1, offSize=1, offsets=[1,6], but only 3 bytes of data
      data = "#{[1].pack('n')}#{[1, 1, 6].pack('C3')}ABC"
      expect do
        described_class.new(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Unexpected end/)
    end
  end

  describe "start_offset parameter" do
    let(:data) do
      # Pre-data before INDEX + INDEX data
      prefix = "JUNK"
      index_data = "#{[1].pack('n')}#{[1].pack('C')}#{[1, 4].pack('C2')}Foo" # data
      prefix + index_data
    end

    it "parses from specified offset" do
      index = described_class.new(data, start_offset: 4)
      expect(index.count).to eq(1)
      expect(index[0]).to eq("Foo")
    end
  end

  describe "binary data handling" do
    it "preserves binary data correctly" do
      # INDEX with binary data including null bytes
      binary_item = [0x00, 0xFF, 0x00, 0xAA].pack("C4")
      parts = []
      parts << [1].pack("n")               # count
      parts << [1].pack("C")               # offSize
      parts << [1, 5].pack("C2")           # offsets
      parts << binary_item                 # data
      data = parts.join

      index = described_class.new(data)
      expect(index[0]).to eq(binary_item)
      expect(index[0].bytes).to eq([0x00, 0xFF, 0x00, 0xAA])
    end
  end
end
