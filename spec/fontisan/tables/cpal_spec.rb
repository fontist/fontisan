# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cpal do
  describe ".read" do
    it "parses CPAL table from binary data" do
      # Create minimal CPAL v0 structure:
      # Header: version(2) + numPaletteEntries(2) + numPalettes(2) +
      #         numColorRecords(2) + colorRecordsArrayOffset(4) = 12 bytes
      # Palette indices: 2 palettes × 2 bytes = 4 bytes
      # Color records: 6 colors × 4 bytes = 24 bytes (BGRA format)

      header = [
        0,   # version (uint16)
        3,   # numPaletteEntries (uint16) - 3 colors per palette
        2,   # numPalettes (uint16) - 2 palettes
        6,   # numColorRecords (uint16) - total 6 color records
        16,  # colorRecordsArrayOffset (uint32) - after header + palette indices
      ].pack("nnnnN")

      # Palette indices (uint16 each): start index for each palette
      palette_indices = [
        0,  # palette 0 starts at color record 0
        3,  # palette 1 starts at color record 3
      ].pack("n*")

      # Color records (BGRA format, 4 bytes each)
      colors = [
        # Palette 0 colors (indices 0-2)
        255, 0, 0, 255,      # Blue=255, Green=0, Red=0, Alpha=255 → #0000FFFF
        0, 255, 0, 255,      # Blue=0, Green=255, Red=0, Alpha=255 → #00FF00FF
        0, 0, 255, 255,      # Blue=0, Green=0, Red=255, Alpha=255 → #FF0000FF
        # Palette 1 colors (indices 3-5)
        128, 128, 128, 255,  # Gray → #808080FF
        255, 255, 255, 255,  # White → #FFFFFFFF
        0, 0, 0, 255 # Black → #000000FF
      ].pack("C*")

      data = header + palette_indices + colors

      cpal = described_class.read(data)

      expect(cpal.version).to eq(0)
      expect(cpal.num_palette_entries).to eq(3)
      expect(cpal.num_palettes).to eq(2)
      expect(cpal.num_color_records).to eq(6)
    end

    it "returns empty table for nil data" do
      cpal = described_class.read(nil)

      expect(cpal).to be_a(described_class)
      expect(cpal.version).to be_nil
    end

    it "handles StringIO input" do
      header = [0, 1, 1, 1, 14].pack("nnnnN")
      palette_indices = [0].pack("n")
      colors = [255, 0, 0, 255].pack("C*")
      data = header + palette_indices + colors

      io = StringIO.new(data)
      cpal = described_class.read(io)

      expect(cpal.version).to eq(0)
    end
  end

  describe "#version" do
    it "returns CPAL version 0" do
      header = [0, 1, 1, 1, 14].pack("nnnnN")
      palette_indices = [0].pack("n")
      colors = [255, 0, 0, 255].pack("C*")
      data = header + palette_indices + colors

      cpal = described_class.read(data)

      expect(cpal.version).to eq(0)
    end

    it "supports CPAL version 1" do
      # Version 1 adds 12 more bytes to header (3 uint32 offsets)
      header = [1, 1, 1, 1, 26].pack("nnnnN")
      # Version 1 extra fields (all zeros/null for this test)
      v1_extra = [0, 0, 0].pack("NNN")
      palette_indices = [0].pack("n")
      colors = [255, 0, 0, 255].pack("C*")
      data = header + v1_extra + palette_indices + colors

      cpal = described_class.read(data)

      expect(cpal.version).to eq(1)
    end
  end

  describe "#palette" do
    let(:cpal) do
      header = [0, 3, 2, 6, 16].pack("nnnnN")
      palette_indices = [0, 3].pack("n*")
      colors = [
        255, 0, 0, 255,      # #0000FFFF (blue)
        0, 255, 0, 255,      # #00FF00FF (green)
        0, 0, 255, 255,      # #FF0000FF (red)
        128, 128, 128, 255,  # #808080FF (gray)
        255, 255, 255, 255,  # #FFFFFFFF (white)
        0, 0, 0, 255 # #000000FF (black)
      ].pack("C*")
      data = header + palette_indices + colors
      described_class.read(data)
    end

    it "returns array of hex color strings" do
      palette = cpal.palette(0)

      expect(palette).to be_an(Array)
      expect(palette.length).to eq(3)
      expect(palette[0]).to be_a(String)
    end

    it "returns colors in #RRGGBBAA format" do
      palette = cpal.palette(0)

      expect(palette[0]).to eq("#0000FFFF")  # Blue
      expect(palette[1]).to eq("#00FF00FF")  # Green
      expect(palette[2]).to eq("#FF0000FF")  # Red
    end

    it "returns correct number of colors" do
      palette0 = cpal.palette(0)
      palette1 = cpal.palette(1)

      expect(palette0.length).to eq(3)
      expect(palette1.length).to eq(3)
    end

    it "returns nil for invalid palette index" do
      expect(cpal.palette(2)).to be_nil
      expect(cpal.palette(10)).to be_nil
    end

    it "handles negative indices" do
      expect(cpal.palette(-1)).to be_nil
    end

    it "handles out-of-range indices" do
      expect(cpal.palette(999)).to be_nil
    end

    it "correctly converts BGRA to RGBA" do
      palette = cpal.palette(1)

      expect(palette[0]).to eq("#808080FF")  # Gray
      expect(palette[1]).to eq("#FFFFFFFF")  # White
      expect(palette[2]).to eq("#000000FF")  # Black
    end
  end

  describe "#all_palettes" do
    it "returns array of all palettes" do
      header = [0, 2, 2, 4, 16].pack("nnnnN")
      palette_indices = [0, 2].pack("n*")
      colors = [
        255, 0, 0, 255,      # Palette 0
        0, 255, 0, 255,
        0, 0, 255, 255,      # Palette 1
        128, 128, 128, 255
      ].pack("C*")
      data = header + palette_indices + colors

      cpal = described_class.read(data)
      palettes = cpal.all_palettes

      expect(palettes.length).to eq(2)
      expect(palettes[0].length).to eq(2)
      expect(palettes[1].length).to eq(2)
    end

    it "returns correct number of palettes" do
      header = [0, 1, 3, 3, 18].pack("nnnnN")
      palette_indices = [0, 1, 2].pack("n*")
      colors = [
        255, 0, 0, 255,
        0, 255, 0, 255,
        0, 0, 255, 255
      ].pack("C*")
      data = header + palette_indices + colors

      cpal = described_class.read(data)

      expect(cpal.all_palettes.length).to eq(3)
    end
  end

  describe "#color_at" do
    let(:cpal) do
      header = [0, 2, 2, 4, 16].pack("nnnnN")
      palette_indices = [0, 2].pack("n*")
      colors = [
        255, 0, 0, 255,      # Palette 0, entry 0
        0, 255, 0, 128,      # Palette 0, entry 1 (semi-transparent)
        0, 0, 255, 255,      # Palette 1, entry 0
        128, 128, 128, 0 # Palette 1, entry 1 (fully transparent)
      ].pack("C*")
      data = header + palette_indices + colors
      described_class.read(data)
    end

    it "returns hex color at specific palette/entry" do
      expect(cpal.color_at(0, 0)).to eq("#0000FFFF")
      expect(cpal.color_at(0, 1)).to eq("#00FF0080")
      expect(cpal.color_at(1, 0)).to eq("#FF0000FF")
      expect(cpal.color_at(1, 1)).to eq("#80808000")
    end

    it "returns nil for invalid indices" do
      expect(cpal.color_at(2, 0)).to be_nil
      expect(cpal.color_at(0, 2)).to be_nil
      expect(cpal.color_at(-1, 0)).to be_nil
      expect(cpal.color_at(0, -1)).to be_nil
    end

    it "preserves alpha channel" do
      # Semi-transparent green
      expect(cpal.color_at(0, 1)).to eq("#00FF0080")
      # Fully transparent gray
      expect(cpal.color_at(1, 1)).to eq("#80808000")
    end

    it "handles opaque colors (alpha=255)" do
      expect(cpal.color_at(0, 0)).to end_with("FF")
    end

    it "handles transparent colors (alpha=0)" do
      expect(cpal.color_at(1, 1)).to end_with("00")
    end
  end

  describe "#valid?" do
    it "returns true for valid CPAL table" do
      header = [0, 1, 1, 1, 14].pack("nnnnN")
      palette_indices = [0].pack("n")
      colors = [255, 0, 0, 255].pack("C*")
      data = header + palette_indices + colors

      cpal = described_class.read(data)

      expect(cpal.valid?).to be true
    end

    it "validates version number" do
      cpal = described_class.new
      cpal.instance_variable_set(:@version, 2)

      expect(cpal.valid?).to be false
    end

    it "validates non-negative counts" do
      cpal = described_class.new
      cpal.instance_variable_set(:@version, 0)
      cpal.instance_variable_set(:@num_palette_entries, -1)

      expect(cpal.valid?).to be false
    end

    it "returns false for nil version" do
      cpal = described_class.new

      expect(cpal.valid?).to be false
    end

    it "validates palette indices present" do
      cpal = described_class.new
      cpal.instance_variable_set(:@version, 0)
      cpal.instance_variable_set(:@num_palette_entries, 1)
      cpal.instance_variable_set(:@num_palettes, 1)
      cpal.instance_variable_set(:@num_color_records, 1)
      cpal.instance_variable_set(:@palette_indices, nil)

      expect(cpal.valid?).to be false
    end
  end

  describe "color format conversion" do
    let(:cpal) do
      header = [0, 4, 1, 4, 14].pack("nnnnN")
      palette_indices = [0].pack("n")
      colors = [
        255, 0, 0, 255,       # Pure blue, opaque
        0, 255, 0, 128,       # Pure green, semi-transparent
        0, 0, 255, 64,        # Pure red, mostly transparent
        128, 64, 192, 255 # Mixed color: B=128, G=64, R=192, A=255
      ].pack("C*")
      data = header + palette_indices + colors
      described_class.read(data)
    end

    it "converts BGRA to RGBA hex correctly" do
      palette = cpal.palette(0)

      expect(palette[0]).to eq("#0000FFFF")  # B=255, G=0, R=0, A=255
      expect(palette[1]).to eq("#00FF0080")  # B=0, G=255, R=0, A=128
      expect(palette[2]).to eq("#FF000040")  # B=0, G=0, R=255, A=64
      expect(palette[3]).to eq("#C04080FF")  # B=128, G=64, R=192, A=255 → RGBA: R=192, G=64, B=128, A=255
    end

    it "preserves all alpha values" do
      palette = cpal.palette(0)

      expect(palette[0][-2..]).to eq("FF")  # Full opacity
      expect(palette[1][-2..]).to eq("80")  # Half opacity (128/255)
      expect(palette[2][-2..]).to eq("40")  # Quarter opacity (64/255)
    end
  end

  describe "error handling" do
    it "raises CorruptedTableError for invalid data" do
      expect do
        described_class.read("abc")
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Failed to parse CPAL table/)
    end

    it "validates sufficient color records" do
      # 2 palettes with 3 colors each needs 6 records, but only claim 5
      header = [0, 3, 2, 5, 16].pack("nnnnN")
      palette_indices = [0, 3].pack("n*")
      colors = [255, 0, 0, 255] * 5
      data = header + palette_indices + colors.pack("C*")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Insufficient color records/)
    end
  end
end
