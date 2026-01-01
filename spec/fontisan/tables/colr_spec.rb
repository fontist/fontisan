# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Colr do
  describe ".read" do
    it "parses COLR table from binary data" do
      # Create minimal COLR v0 structure:
      # Header: version(2) + numBaseGlyphRecords(2) + baseGlyphRecordsOffset(4) +
      #         layerRecordsOffset(4) + numLayerRecords(2) = 14 bytes
      # Base glyph records: 2 records × 6 bytes = 12 bytes
      # Layer records: 4 records × 4 bytes = 16 bytes

      header = [
        0,    # version (uint16)
        2,    # numBaseGlyphRecords (uint16)
        14,   # baseGlyphRecordsOffset (uint32) - right after header
        26,   # layerRecordsOffset (uint32) - after base glyphs
        4,    # numLayerRecords (uint16)
      ].pack("nnNNn")

      # Base glyph records (6 bytes each): glyphID(2) + firstLayerIndex(2) + numLayers(2)
      base_glyphs = [
        10, 0, 2,  # glyph 10: layers 0-1 (2 layers)
        20, 2, 2,  # glyph 20: layers 2-3 (2 layers)
      ].pack("n*")

      # Layer records (4 bytes each): glyphID(2) + paletteIndex(2)
      layers = [
        100, 0,  # layer 0: glyph 100, palette 0
        101, 1,  # layer 1: glyph 101, palette 1
        200, 0,  # layer 2: glyph 200, palette 0
        201, 2,  # layer 3: glyph 201, palette 2
      ].pack("n*")

      data = header + base_glyphs + layers

      colr = described_class.read(data)

      expect(colr.version).to eq(0)
      expect(colr.num_base_glyph_records).to eq(2)
      expect(colr.num_layer_records).to eq(4)
      expect(colr.base_glyph_records.length).to eq(2)
      expect(colr.layer_records.length).to eq(4)
    end

    it "returns empty table for nil data" do
      colr = described_class.read(nil)

      expect(colr).to be_a(described_class)
      expect(colr.version).to be_nil
    end

    it "handles StringIO input" do
      data = [0, 0, 14, 14, 0].pack("nnNNn")
      io = StringIO.new(data)

      colr = described_class.read(io)

      expect(colr.version).to eq(0)
    end
  end

  describe "#version" do
    it "returns COLR version number" do
      data = [0, 0, 14, 14, 0].pack("nnNNn")
      colr = described_class.read(data)

      expect(colr.version).to eq(0)
    end

    it "rejects unsupported version 1" do
      data = [1, 0, 14, 14, 0].pack("nnNNn")

      expect {
        described_class.read(data)
      }.to raise_error(Fontisan::CorruptedTableError, /Unsupported COLR version/)
    end
  end

  describe "#num_color_glyphs" do
    it "returns number of base glyph records" do
      header = [0, 3, 14, 32, 0].pack("nnNNn")
      base_glyphs = [10, 0, 1, 20, 1, 1, 30, 2, 1].pack("n*")
      data = header + base_glyphs

      colr = described_class.read(data)

      expect(colr.num_color_glyphs).to eq(3)
    end

    it "returns 0 for table with no color glyphs" do
      data = [0, 0, 14, 14, 0].pack("nnNNn")
      colr = described_class.read(data)

      expect(colr.num_color_glyphs).to eq(0)
    end
  end

  describe "#layers_for_glyph" do
    let(:colr) do
      header = [0, 2, 14, 26, 4].pack("nnNNn")
      base_glyphs = [10, 0, 2, 20, 2, 2].pack("n*")
      layers = [100, 0, 101, 1, 200, 0, 201, 2].pack("n*")
      data = header + base_glyphs + layers
      described_class.read(data)
    end

    it "returns array of LayerRecords for color glyph" do
      layers = colr.layers_for_glyph(10)

      expect(layers).to be_an(Array)
      expect(layers.length).to eq(2)
      expect(layers[0]).to be_a(Fontisan::Tables::Colr::LayerRecord)
      expect(layers[0].glyph_id).to eq(100)
      expect(layers[0].palette_index).to eq(0)
    end

    it "returns empty array for non-color glyph" do
      layers = colr.layers_for_glyph(999)

      expect(layers).to eq([])
    end

    it "returns correct number of layers" do
      layers = colr.layers_for_glyph(20)

      expect(layers.length).to eq(2)
    end

    it "returns layers with valid glyph IDs" do
      layers = colr.layers_for_glyph(20)

      expect(layers[0].glyph_id).to eq(200)
      expect(layers[1].glyph_id).to eq(201)
    end

    it "returns layers with valid palette indices" do
      layers = colr.layers_for_glyph(20)

      expect(layers[0].palette_index).to eq(0)
      expect(layers[1].palette_index).to eq(2)
    end
  end

  describe "#has_color_glyph?" do
    let(:colr) do
      header = [0, 1, 14, 20, 1].pack("nnNNn")
      base_glyphs = [10, 0, 1].pack("n*")
      layers = [100, 0].pack("n*")
      data = header + base_glyphs + layers
      described_class.read(data)
    end

    it "returns true for glyph with color layers" do
      expect(colr.has_color_glyph?(10)).to be true
    end

    it "returns false for glyph without color layers" do
      expect(colr.has_color_glyph?(999)).to be false
    end
  end

  describe "#color_glyph_ids" do
    it "returns array of all color glyph IDs" do
      header = [0, 3, 14, 32, 0].pack("nnNNn")
      base_glyphs = [10, 0, 0, 20, 0, 0, 30, 0, 0].pack("n*")
      data = header + base_glyphs

      colr = described_class.read(data)
      ids = colr.color_glyph_ids

      expect(ids).to eq([10, 20, 30])
    end

    it "returns sorted array (base glyphs must be sorted)" do
      header = [0, 3, 14, 32, 0].pack("nnNNn")
      base_glyphs = [5, 0, 0, 15, 0, 0, 25, 0, 0].pack("n*")
      data = header + base_glyphs

      colr = described_class.read(data)
      ids = colr.color_glyph_ids

      expect(ids).to eq([5, 15, 25])
    end
  end

  describe "#valid?" do
    it "returns true for valid COLR table" do
      header = [0, 1, 14, 20, 1].pack("nnNNn")
      base_glyphs = [10, 0, 1].pack("n*")
      layers = [100, 0].pack("n*")
      data = header + base_glyphs + layers

      colr = described_class.read(data)

      expect(colr.valid?).to be true
    end

    it "validates version number" do
      colr = described_class.new
      colr.instance_variable_set(:@version, 2)

      expect(colr.valid?).to be false
    end

    it "validates record counts are non-negative" do
      colr = described_class.new
      colr.instance_variable_set(:@version, 0)
      colr.instance_variable_set(:@num_base_glyph_records, -1)
      colr.instance_variable_set(:@base_glyph_records, [])
      colr.instance_variable_set(:@layer_records, [])

      expect(colr.valid?).to be false
    end

    it "returns false for nil version" do
      colr = described_class.new

      expect(colr.valid?).to be false
    end
  end

  describe "binary search" do
    let(:colr) do
      # Create table with 5 glyphs (10, 20, 30, 40, 50) to test binary search
      # Each glyph has 1 layer to make it a valid color glyph
      header = [0, 5, 14, 44, 5].pack("nnNNn")
      base_glyphs = [
        10, 0, 1,  # glyph 10: 1 layer at index 0
        20, 1, 1,  # glyph 20: 1 layer at index 1
        30, 2, 1,  # glyph 30: 1 layer at index 2
        40, 3, 1,  # glyph 40: 1 layer at index 3
        50, 4, 1,  # glyph 50: 1 layer at index 4
      ].pack("n*")
      # Add 5 layer records (even though we don't use them in this test)
      layers = [100, 0, 101, 0, 102, 0, 103, 0, 104, 0].pack("n*")
      data = header + base_glyphs + layers
      described_class.read(data)
    end

    it "finds glyph in O(log n) time using binary search" do
      # Should find middle element
      expect(colr.has_color_glyph?(30)).to be true

      # Should find first element
      expect(colr.has_color_glyph?(10)).to be true

      # Should find last element
      expect(colr.has_color_glyph?(50)).to be true
    end

    it "returns nil for non-existent glyph" do
      expect(colr.has_color_glyph?(15)).to be false
      expect(colr.has_color_glyph?(35)).to be false
      expect(colr.has_color_glyph?(100)).to be false
    end
  end

  describe "error handling" do
    it "raises CorruptedTableError for invalid data" do
      # Too short data
      expect {
        described_class.read("abc")
      }.to raise_error(Fontisan::CorruptedTableError, /Failed to parse COLR table/)
    end
  end
end