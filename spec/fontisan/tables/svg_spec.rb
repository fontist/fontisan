# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Svg do
  describe ".read" do
    it "parses SVG table from binary data" do
      # Create minimal SVG v0 structure:
      # Header: version(2) + svgDocumentListOffset(4) + reserved(4) = 10 bytes
      # Document Index: numEntries(2) + entries(2 × 12 bytes) = 26 bytes
      # SVG Documents: 2 documents

      svg_doc1 = "<svg>test1</svg>"
      svg_doc2 = "<svg>test2</svg>"

      header = [
        0,    # version (uint16)
        10,   # svgDocumentListOffset (uint32) - right after header
        0,    # reserved (uint32)
      ].pack("nNN")

      # Document index at offset 10
      document_index = [
        2, # numEntries (uint16)
      ].pack("n")

      # Document records (12 bytes each): startGlyphID(2) + endGlyphID(2) +
      #                                    svgDocOffset(4) + svgDocLength(4)
      # Offsets are relative to start of documents area (after all records)
      records = [
        10, 15, 0, svg_doc1.length, # glyph 10-15: doc at offset 0
        20, 25, svg_doc1.length, svg_doc2.length # glyph 20-25: doc at offset len1
      ].pack("nnNNnnNN")

      data = header + document_index + records + svg_doc1 + svg_doc2

      svg = described_class.read(data)

      expect(svg.version).to eq(0)
      expect(svg.num_entries).to eq(2)
      expect(svg.document_records.length).to eq(2)
      expect(svg.document_records[0].start_glyph_id).to eq(10)
      expect(svg.document_records[0].end_glyph_id).to eq(15)
    end

    it "returns empty table for nil data" do
      svg = described_class.read(nil)

      expect(svg).to be_a(described_class)
      expect(svg.version).to be_nil
    end

    it "handles StringIO input" do
      data = [0, 10, 0].pack("nNN")
      io = StringIO.new(data)

      svg = described_class.read(io)

      expect(svg.version).to eq(0)
    end
  end

  describe "#version" do
    it "returns SVG version number" do
      data = [0, 10, 0].pack("nNN")
      svg = described_class.read(data)

      expect(svg.version).to eq(0)
    end

    it "rejects unsupported version 1" do
      data = [1, 10, 0].pack("nNN")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Unsupported SVG version/)
    end
  end

  describe "#svg_for_glyph" do
    let(:svg) do
      svg_doc1 = "<svg>glyph10-15</svg>"
      svg_doc2 = "<svg>glyph20-25</svg>"

      header = [0, 10, 0].pack("nNN")
      document_index = [2].pack("n")
      records = [
        10, 15, 0, svg_doc1.length,
        20, 25, svg_doc1.length, svg_doc2.length
      ].pack("nnNNnnNN")
      data = header + document_index + records + svg_doc1 + svg_doc2
      described_class.read(data)
    end

    it "returns SVG document for glyph in range" do
      svg_content = svg.svg_for_glyph(10)

      expect(svg_content).to eq("<svg>glyph10-15</svg>")
    end

    it "returns same SVG for any glyph in range" do
      svg_start = svg.svg_for_glyph(10)
      svg_end = svg.svg_for_glyph(15)

      expect(svg_start).to eq(svg_end)
      expect(svg_start).to eq("<svg>glyph10-15</svg>")
    end

    it "returns correct SVG for different ranges" do
      svg_first = svg.svg_for_glyph(10)
      svg_second = svg.svg_for_glyph(20)

      expect(svg_first).to eq("<svg>glyph10-15</svg>")
      expect(svg_second).to eq("<svg>glyph20-25</svg>")
    end

    it "returns nil for glyph not in table" do
      svg_content = svg.svg_for_glyph(999)

      expect(svg_content).to be_nil
    end

    it "returns nil for glyph between ranges" do
      svg_content = svg.svg_for_glyph(17)

      expect(svg_content).to be_nil
    end
  end

  describe "#has_svg_for_glyph?" do
    let(:svg) do
      svg_doc = "<svg>test</svg>"
      header = [0, 10, 0].pack("nNN")
      document_index = [1].pack("n")
      records = [10, 15, 0, svg_doc.length].pack("nnNN")
      data = header + document_index + records + svg_doc
      described_class.read(data)
    end

    it "returns true for glyph with SVG" do
      expect(svg.has_svg_for_glyph?(10)).to be true
      expect(svg.has_svg_for_glyph?(12)).to be true
      expect(svg.has_svg_for_glyph?(15)).to be true
    end

    it "returns false for glyph without SVG" do
      expect(svg.has_svg_for_glyph?(9)).to be false
      expect(svg.has_svg_for_glyph?(16)).to be false
      expect(svg.has_svg_for_glyph?(999)).to be false
    end
  end

  describe "#glyph_ids_with_svg" do
    it "returns array of all glyph IDs with SVG" do
      svg_doc1 = "<svg>1</svg>"
      svg_doc2 = "<svg>2</svg>"
      header = [0, 10, 0].pack("nNN")
      document_index = [2].pack("n")
      records = [
        10, 12, 0, svg_doc1.length, # glyphs 10, 11, 12
        20, 21, svg_doc1.length, svg_doc2.length # glyphs 20, 21
      ].pack("nnNNnnNN")
      data = header + document_index + records + svg_doc1 + svg_doc2

      svg = described_class.read(data)
      ids = svg.glyph_ids_with_svg

      expect(ids).to eq([10, 11, 12, 20, 21])
    end

    it "handles single glyph ranges" do
      svg_doc = "<svg>single</svg>"
      header = [0, 10, 0].pack("nNN")
      document_index = [1].pack("n")
      records = [10, 10, 0, svg_doc.length].pack("nnNN") # Single glyph
      data = header + document_index + records + svg_doc

      svg = described_class.read(data)
      ids = svg.glyph_ids_with_svg

      expect(ids).to eq([10])
    end

    it "returns empty array for table with no documents" do
      header = [0, 10, 0].pack("nNN")
      document_index = [0].pack("n")
      data = header + document_index

      svg = described_class.read(data)
      ids = svg.glyph_ids_with_svg

      expect(ids).to eq([])
    end
  end

  describe "#num_svg_documents" do
    it "returns number of SVG documents" do
      svg_doc = "<svg>test</svg>"
      header = [0, 10, 0].pack("nNN")
      document_index = [3].pack("n")
      records = [
        10, 10, 0, svg_doc.length,
        20, 20, svg_doc.length, svg_doc.length,
        30, 30, svg_doc.length * 2, svg_doc.length
      ].pack("nnNNnnNNnnNN")
      data = header + document_index + records + svg_doc + svg_doc + svg_doc

      svg = described_class.read(data)

      expect(svg.num_svg_documents).to eq(3)
    end

    it "returns 0 for table with no documents" do
      header = [0, 10, 0].pack("nNN")
      document_index = [0].pack("n")
      data = header + document_index

      svg = described_class.read(data)

      expect(svg.num_svg_documents).to eq(0)
    end
  end

  describe "gzip decompression" do
    it "decompresses gzipped SVG content" do
      require "stringio"
      require "zlib"

      # Create gzipped SVG content
      svg_content = "<svg>compressed</svg>"
      compressed = StringIO.new
      gz = Zlib::GzipWriter.new(compressed)
      gz.write(svg_content)
      gz.close
      compressed_data = compressed.string

      # Build SVG table with compressed document
      header = [0, 10, 0].pack("nNN")
      document_index = [1].pack("n")
      records = [10, 10, 0, compressed_data.length].pack("nnNN")
      data = header + document_index + records + compressed_data

      svg = described_class.read(data)
      result = svg.svg_for_glyph(10)

      expect(result).to eq(svg_content)
    end

    it "handles uncompressed SVG content" do
      svg_content = "<svg>uncompressed</svg>"

      header = [0, 10, 0].pack("nNN")
      document_index = [1].pack("n")
      records = [10, 10, 0, svg_content.length].pack("nnNN")
      data = header + document_index + records + svg_content

      svg = described_class.read(data)
      result = svg.svg_for_glyph(10)

      expect(result).to eq(svg_content)
    end

    it "raises error for corrupted gzip data" do
      # Create fake gzip header with invalid data
      fake_gzip = "#{[0x1f, 0x8b].pack('C*')}invalid data"

      header = [0, 10, 0].pack("nNN")
      document_index = [1].pack("n")
      records = [10, 10, 0, fake_gzip.length].pack("nnNN")
      data = header + document_index + records + fake_gzip

      svg = described_class.read(data)

      expect do
        svg.svg_for_glyph(10)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Failed to decompress SVG data/)
    end
  end

  describe "#valid?" do
    it "returns true for valid SVG table" do
      svg_doc = "<svg>test</svg>"
      header = [0, 10, 0].pack("nNN")
      document_index = [1].pack("n")
      records = [10, 10, 0, svg_doc.length].pack("nnNN")
      data = header + document_index + records + svg_doc

      svg = described_class.read(data)

      expect(svg.valid?).to be true
    end

    it "validates version number" do
      svg = described_class.new
      svg.instance_variable_set(:@version, 2)
      svg.instance_variable_set(:@num_entries, 0)
      svg.instance_variable_set(:@document_records, [])

      expect(svg.valid?).to be false
    end

    it "validates num_entries is non-negative" do
      svg = described_class.new
      svg.instance_variable_set(:@version, 0)
      svg.instance_variable_set(:@num_entries, -1)
      svg.instance_variable_set(:@document_records, [])

      expect(svg.valid?).to be false
    end

    it "returns false for nil version" do
      svg = described_class.new

      expect(svg.valid?).to be false
    end

    it "returns false for missing document_records" do
      svg = described_class.new
      svg.instance_variable_set(:@version, 0)
      svg.instance_variable_set(:@num_entries, 1)

      expect(svg.valid?).to be false
    end
  end

  describe "binary search" do
    let(:svg) do
      # Create table with 5 glyph ranges to test binary search
      svg_doc = "<svg>test</svg>"
      header = [0, 10, 0].pack("nNN")
      document_index = [5].pack("n")
      records = [
        10, 10, 0, svg_doc.length,
        20, 20, svg_doc.length, svg_doc.length,
        30, 30, svg_doc.length * 2, svg_doc.length,
        40, 40, svg_doc.length * 3, svg_doc.length,
        50, 50, svg_doc.length * 4, svg_doc.length
      ].pack("nnNNnnNNnnNNnnNNnnNN")
      docs = svg_doc * 5
      data = header + document_index + records + docs
      described_class.read(data)
    end

    it "finds glyph in O(log n) time using binary search" do
      # Should find middle element
      expect(svg.has_svg_for_glyph?(30)).to be true

      # Should find first element
      expect(svg.has_svg_for_glyph?(10)).to be true

      # Should find last element
      expect(svg.has_svg_for_glyph?(50)).to be true
    end

    it "returns false for non-existent glyph" do
      expect(svg.has_svg_for_glyph?(15)).to be false
      expect(svg.has_svg_for_glyph?(35)).to be false
      expect(svg.has_svg_for_glyph?(100)).to be false
    end
  end

  describe "SvgDocumentRecord" do
    describe "#includes_glyph?" do
      it "returns true for glyph in range" do
        data = [10, 15, 0, 100].pack("nnNN")
        record = described_class::SvgDocumentRecord.read(data)

        expect(record.includes_glyph?(10)).to be true
        expect(record.includes_glyph?(12)).to be true
        expect(record.includes_glyph?(15)).to be true
      end

      it "returns false for glyph outside range" do
        data = [10, 15, 0, 100].pack("nnNN")
        record = described_class::SvgDocumentRecord.read(data)

        expect(record.includes_glyph?(9)).to be false
        expect(record.includes_glyph?(16)).to be false
      end
    end

    describe "#glyph_range" do
      it "returns range of glyph IDs" do
        data = [10, 15, 0, 100].pack("nnNN")
        record = described_class::SvgDocumentRecord.read(data)

        expect(record.glyph_range).to eq(10..15)
      end
    end
  end

  describe "error handling" do
    it "raises CorruptedTableError for invalid data" do
      # Too short data
      expect do
        described_class.read("abc")
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Failed to parse SVG table/)
    end

    it "raises CorruptedTableError for invalid offset" do
      # Offset points beyond data length
      header = [0, 9999, 0].pack("nNN")

      expect do
        described_class.read(header)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Invalid svgDocumentListOffset/)
    end
  end
end
