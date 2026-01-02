# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Sbix do
  describe ".read" do
    it "parses sbix table from binary data" do
      # Create minimal sbix v1 structure with proper offset calculation
      header = [
        1,  # version (uint16)
        0,  # flags (uint16)
        2,  # numStrikes (uint32)
      ].pack("nnN")

      # Strike offsets must be calculated precisely
      # Header: 8 bytes
      # Strike offsets: 2 * 4 = 8 bytes
      # Total header section: 16 bytes
      strike1_data = create_strike(ppem: 16, ppi: 72, num_glyphs: 3)
      strike2_data = create_strike(ppem: 32, ppi: 72, num_glyphs: 2)

      strike_offset_1 = 16  # After header (8) + offsets (8)
      strike_offset_2 = 16 + strike1_data.bytesize

      offsets = [strike_offset_1, strike_offset_2].pack("NN")

      data = header + offsets + strike1_data + strike2_data

      sbix = described_class.read(data)

      expect(sbix.version).to eq(1)
      expect(sbix.flags).to eq(0)
      expect(sbix.num_strikes).to eq(2)
      expect(sbix.strikes.length).to eq(2)
      expect(sbix.strikes[0][:ppem]).to eq(16)
      expect(sbix.strikes[1][:ppem]).to eq(32)
    end

    it "returns empty table for nil data" do
      sbix = described_class.read(nil)

      expect(sbix).to be_a(described_class)
      expect(sbix.version).to be_nil
    end

    it "handles StringIO input" do
      data = [1, 0, 0].pack("nnN")
      io = StringIO.new(data)

      sbix = described_class.read(io)

      expect(sbix.version).to eq(1)
    end
  end

  describe "#version" do
    it "returns sbix version number" do
      data = [1, 0, 0].pack("nnN")
      sbix = described_class.read(data)

      expect(sbix.version).to eq(1)
    end

    it "rejects unsupported version 0" do
      data = [0, 0, 0].pack("nnN")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Unsupported sbix version/)
    end

    it "rejects unsupported version 2" do
      data = [2, 0, 0].pack("nnN")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Unsupported sbix version/)
    end
  end

  describe "#strikes" do
    let(:sbix) do
      header = [1, 0, 2].pack("nnN")
      strike1_data = create_strike(ppem: 16, ppi: 72, num_glyphs: 2)
      strike2_data = create_strike(ppem: 32, ppi: 72, num_glyphs: 2)

      strike_offset_1 = 16
      strike_offset_2 = 16 + strike1_data.bytesize
      offsets = [strike_offset_1, strike_offset_2].pack("NN")

      data = header + offsets + strike1_data + strike2_data
      described_class.read(data)
    end

    it "returns all strike records" do
      strikes = sbix.strikes

      expect(strikes.length).to eq(2)
      expect(strikes[0]).to be_a(Hash)
      expect(strikes[1]).to be_a(Hash)
    end

    it "parses strike ppem values" do
      expect(sbix.strikes[0][:ppem]).to eq(16)
      expect(sbix.strikes[1][:ppem]).to eq(32)
    end

    it "parses strike ppi values" do
      expect(sbix.strikes[0][:ppi]).to eq(72)
      expect(sbix.strikes[1][:ppi]).to eq(72)
    end

    it "returns empty array for table with no strikes" do
      data = [1, 0, 0].pack("nnN")
      sbix = described_class.read(data)

      expect(sbix.strikes).to eq([])
    end
  end

  describe "#strike_for_ppem" do
    let(:sbix) do
      header = [1, 0, 3].pack("nnN")
      strike1_data = create_strike(ppem: 16, ppi: 72, num_glyphs: 2)
      strike2_data = create_strike(ppem: 32, ppi: 72, num_glyphs: 2)
      strike3_data = create_strike(ppem: 16, ppi: 144, num_glyphs: 2)  # retina

      strike_offset_1 = 20  # After header (8) + offsets (3*4=12)
      strike_offset_2 = strike_offset_1 + strike1_data.bytesize
      strike_offset_3 = strike_offset_2 + strike2_data.bytesize
      offsets = [strike_offset_1, strike_offset_2, strike_offset_3].pack("NNN")

      data = header + offsets + strike1_data + strike2_data + strike3_data
      described_class.read(data)
    end

    it "returns strike matching ppem size" do
      strike = sbix.strike_for_ppem(32)

      expect(strike).not_to be_nil
      expect(strike[:ppem]).to eq(32)
    end

    it "returns first strike when multiple match" do
      strike = sbix.strike_for_ppem(16)

      expect(strike[:ppem]).to eq(16)
      expect(strike[:ppi]).to eq(72)  # First one, not retina
    end

    it "returns nil when no strikes match" do
      strike = sbix.strike_for_ppem(64)

      expect(strike).to be_nil
    end
  end

  describe "#ppem_sizes" do
    it "returns sorted unique ppem sizes" do
      header = [1, 0, 4].pack("nnN")
      strike1_data = create_strike(ppem: 16, ppi: 72, num_glyphs: 2)
      strike2_data = create_strike(ppem: 32, ppi: 72, num_glyphs: 2)
      strike3_data = create_strike(ppem: 16, ppi: 144, num_glyphs: 2)
      strike4_data = create_strike(ppem: 64, ppi: 72, num_glyphs: 2)

      strike_offset_1 = 24  # After header (8) + offsets (4*4=16)
      strike_offset_2 = strike_offset_1 + strike1_data.bytesize
      strike_offset_3 = strike_offset_2 + strike2_data.bytesize
      strike_offset_4 = strike_offset_3 + strike3_data.bytesize
      offsets = [strike_offset_1, strike_offset_2, strike_offset_3, strike_offset_4].pack("NNNN")

      data = header + offsets + strike1_data + strike2_data + strike3_data + strike4_data

      sbix = described_class.read(data)
      sizes = sbix.ppem_sizes

      expect(sizes).to eq([16, 32, 64])
    end

    it "returns empty array for table with no strikes" do
      data = [1, 0, 0].pack("nnN")
      sbix = described_class.read(data)

      expect(sbix.ppem_sizes).to eq([])
    end
  end

  describe "#glyph_data" do
    let(:sbix) do
      header = [1, 0, 1].pack("nnN")

      # Build glyphs first to get accurate sizes
      png_data = "\x89PNG\r\n\x1a\n".b + "test".b
      glyph0 = create_glyph_data(
        origin_x: 5,
        origin_y: 10,
        type: described_class::GRAPHIC_TYPE_PNG,
        data: png_data
      )

      jpeg_data = "\xff\xd8\xff\xe0".b + "jpeg".b
      glyph1 = create_glyph_data(
        origin_x: -2,
        origin_y: 8,
        type: described_class::GRAPHIC_TYPE_JPG,
        data: jpeg_data
      )

      glyph2 = create_glyph_data(
        origin_x: 0,
        origin_y: 0,
        type: described_class::GRAPHIC_TYPE_DUPE,
        data: "".b
      )

      # Now calculate offsets based on actual sizes
      strike_header = [16, 72].pack("nn")  # ppem, ppi (4 bytes)
      offset_base = 4 + (4 * 4)  # strike header (4) + 4 offsets (16) = 20

      glyph_offsets = [
        offset_base,                                    # glyph 0 at 20
        offset_base + glyph0.bytesize,                  # glyph 1 at 20 + glyph0_size
        offset_base + glyph0.bytesize + glyph1.bytesize, # glyph 2 at 20 + glyph0 + glyph1
        offset_base + glyph0.bytesize + glyph1.bytesize + glyph2.bytesize,  # end
      ].pack("NNNN")

      strike_data = strike_header + glyph_offsets + glyph0 + glyph1 + glyph2
      strike_offset = 12  # After header (8) + offset (4)
      offsets = [strike_offset].pack("N")

      data = header + offsets + strike_data

      described_class.read(data)
    end

    it "extracts glyph data at specific ppem" do
      data = sbix.glyph_data(0, 16)

      expect(data).not_to be_nil
      expect(data[:origin_x]).to eq(5)
      expect(data[:origin_y]).to eq(10)
      expect(data[:graphic_type]).to eq(described_class::GRAPHIC_TYPE_PNG)
      expect(data[:data][0..7].b).to eq("\x89PNG\r\n\x1a\n".b)
    end

    it "extracts JPEG glyph data" do
      data = sbix.glyph_data(1, 16)

      expect(data).not_to be_nil
      expect(data[:origin_x]).to eq(-2)
      expect(data[:origin_y]).to eq(8)
      expect(data[:graphic_type]).to eq(described_class::GRAPHIC_TYPE_JPG)
      expect(data[:graphic_type_name]).to eq("JPEG")
    end

    it "handles dupe graphic type" do
      data = sbix.glyph_data(2, 16)

      expect(data).not_to be_nil
      expect(data[:graphic_type]).to eq(described_class::GRAPHIC_TYPE_DUPE)
      expect(data[:graphic_type_name]).to eq("dupe")
    end

    it "returns nil for non-existent ppem" do
      data = sbix.glyph_data(0, 64)

      expect(data).to be_nil
    end

    it "returns nil for glyph beyond range" do
      data = sbix.glyph_data(999, 16)

      expect(data).to be_nil
    end
  end

  describe "#has_glyph_at_ppem?" do
    let(:sbix) do
      header = [1, 0, 1].pack("nnN")

      # Build glyphs first
      png_data = "\x89PNG\r\n\x1a\n".b
      glyph0 = create_glyph_data(
        origin_x: 0, origin_y: 0,
        type: described_class::GRAPHIC_TYPE_PNG,
        data: png_data
      )

      strike_header = [16, 72].pack("nn")
      offset_base = 4 + (3 * 4)  # 3 offsets for 2 glyphs (including end marker)
      glyph_offsets = [
        offset_base,
        offset_base + glyph0.bytesize,
        offset_base + glyph0.bytesize,  # Glyph 1 is empty (both offsets same)
      ].pack("NNN")

      strike_data = strike_header + glyph_offsets + glyph0
      strike_offset = 12
      offsets = [strike_offset].pack("N")

      data = header + offsets + strike_data

      described_class.read(data)
    end

    it "returns true when glyph has bitmap data" do
      expect(sbix.has_glyph_at_ppem?(0, 16)).to be true
    end

    it "returns false for empty glyph" do
      expect(sbix.has_glyph_at_ppem?(1, 16)).to be false
    end

    it "returns false for non-existent glyph" do
      expect(sbix.has_glyph_at_ppem?(999, 16)).to be false
    end

    it "returns false for non-existent ppem" do
      expect(sbix.has_glyph_at_ppem?(0, 64)).to be false
    end
  end

  describe "#supported_formats" do
    it "detects PNG format" do
      header = [1, 0, 1].pack("nnN")

      png_data = "\x89PNG\r\n\x1a\n".b
      glyph0 = create_glyph_data(
        origin_x: 0, origin_y: 0,
        type: described_class::GRAPHIC_TYPE_PNG,
        data: png_data
      )

      strike_header = [16, 72].pack("nn")
      offset_base = 4 + (2 * 4)  # 2 offsets for 1 glyph
      glyph_offsets = [
        offset_base,
        offset_base + glyph0.bytesize,
      ].pack("NN")

      strike_data = strike_header + glyph_offsets + glyph0
      strike_offset = 12
      offsets = [strike_offset].pack("N")

      data = header + offsets + strike_data

      sbix = described_class.read(data)
      formats = sbix.supported_formats

      expect(formats).to include("PNG")
    end

    it "detects JPEG format" do
      header = [1, 0, 1].pack("nnN")

      jpeg_data = "\xff\xd8\xff\xe0".b
      glyph0 = create_glyph_data(
        origin_x: 0, origin_y: 0,
        type: described_class::GRAPHIC_TYPE_JPG,
        data: jpeg_data
      )

      strike_header = [16, 72].pack("nn")
      offset_base = 4 + (2 * 4)
      glyph_offsets = [
        offset_base,
        offset_base + glyph0.bytesize,
      ].pack("NN")

      strike_data = strike_header + glyph_offsets + glyph0
      strike_offset = 12
      offsets = [strike_offset].pack("N")

      data = header + offsets + strike_data

      sbix = described_class.read(data)
      formats = sbix.supported_formats

      expect(formats).to include("JPEG")
    end

    it "detects TIFF format" do
      header = [1, 0, 1].pack("nnN")

      tiff_data = "TIFF".b
      glyph0 = create_glyph_data(
        origin_x: 0, origin_y: 0,
        type: described_class::GRAPHIC_TYPE_TIFF,
        data: tiff_data
      )

      strike_header = [16, 72].pack("nn")
      offset_base = 4 + (2 * 4)
      glyph_offsets = [
        offset_base,
        offset_base + glyph0.bytesize,
      ].pack("NN")

      strike_data = strike_header + glyph_offsets + glyph0
      strike_offset = 12
      offsets = [strike_offset].pack("N")

      data = header + offsets + strike_data

      sbix = described_class.read(data)
      formats = sbix.supported_formats

      expect(formats).to include("TIFF")
    end

    it "excludes dupe and mask types" do
      header = [1, 0, 1].pack("nnN")

      glyph0 = create_glyph_data(
        origin_x: 0, origin_y: 0,
        type: described_class::GRAPHIC_TYPE_DUPE,
        data: "".b
      )

      glyph1 = create_glyph_data(
        origin_x: 0, origin_y: 0,
        type: described_class::GRAPHIC_TYPE_MASK,
        data: "".b
      )

      strike_header = [16, 72].pack("nn")
      offset_base = 4 + (3 * 4)  # 3 offsets for 2 glyphs
      glyph_offsets = [
        offset_base,
        offset_base + glyph0.bytesize,
        offset_base + glyph0.bytesize + glyph1.bytesize,
      ].pack("NNN")

      strike_data = strike_header + glyph_offsets + glyph0 + glyph1
      strike_offset = 12
      offsets = [strike_offset].pack("N")

      data = header + offsets + strike_data

      sbix = described_class.read(data)
      formats = sbix.supported_formats

      expect(formats).to eq([])
    end

    it "returns empty array for table with no strikes" do
      data = [1, 0, 0].pack("nnN")
      sbix = described_class.read(data)

      expect(sbix.supported_formats).to eq([])
    end
  end

  describe "#valid?" do
    it "returns true for valid sbix v1 table" do
      header = [1, 0, 1].pack("nnN")
      offsets = [12].pack("N")
      strike = create_strike(ppem: 16, ppi: 72, num_glyphs: 1)
      data = header + offsets + strike

      sbix = described_class.read(data)

      expect(sbix.valid?).to be true
    end

    it "validates version number" do
      sbix = described_class.new
      sbix.instance_variable_set(:@version, 0)
      sbix.instance_variable_set(:@num_strikes, 0)
      sbix.instance_variable_set(:@strikes, [])

      expect(sbix.valid?).to be false
    end

    it "validates num_strikes is non-negative" do
      sbix = described_class.new
      sbix.instance_variable_set(:@version, 1)
      sbix.instance_variable_set(:@num_strikes, -1)
      sbix.instance_variable_set(:@strikes, [])

      expect(sbix.valid?).to be false
    end

    it "returns false for nil version" do
      sbix = described_class.new

      expect(sbix.valid?).to be false
    end

    it "returns false for missing strikes" do
      sbix = described_class.new
      sbix.instance_variable_set(:@version, 1)
      sbix.instance_variable_set(:@num_strikes, 1)

      expect(sbix.valid?).to be false
    end
  end

  describe "error handling" do
    it "raises CorruptedTableError for invalid data" do
      expect do
        described_class.read("abc")
      end.to raise_error(Fontisan::CorruptedTableError, /Failed to parse sbix table/)
    end

    it "raises CorruptedTableError for truncated data" do
      header = [1, 0, 1].pack("nnN")
      offsets = "ab"  # Not 4 bytes

      expect do
        described_class.read(header + offsets)
      end.to raise_error(Fontisan::CorruptedTableError, /Failed to parse sbix table/)
    end
  end

  # Helper method to create a strike with glyphs
  def create_strike(ppem:, ppi:, num_glyphs:)
    strike_header = [ppem, ppi].pack("nn")

    # Create glyph data offsets (num_glyphs + 1)
    offset = 4 + ((num_glyphs + 1) * 4)  # After header and offsets
    glyph_offsets = []

    (num_glyphs + 1).times do |i|
      glyph_offsets << offset
      offset += 20  # Each glyph is ~20 bytes
    end

    offsets_data = glyph_offsets.pack("N*")

    # Create dummy glyph data
    glyphs_data = "".b  # Force binary encoding
    num_glyphs.times do
      glyphs_data += create_glyph_data(
        origin_x: 0,
        origin_y: 0,
        type: described_class::GRAPHIC_TYPE_PNG,
        data: "\x89PNG".b
      )
    end

    (strike_header + offsets_data + glyphs_data).b
  end

  # Helper method to create glyph data record
  def create_glyph_data(origin_x:, origin_y:, type:, data:)
    header = [
      origin_x,  # originOffsetX (int16, signed, big-endian)
      origin_y,  # originOffsetY (int16, signed, big-endian)
      type,      # graphicType (uint32)
    ].pack("s>s>N")

    (header + data.b).b  # Force binary encoding
  end
end
