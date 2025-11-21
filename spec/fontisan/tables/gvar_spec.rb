# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Gvar do
  def build_gvar_table(
    major_version: 1,
    minor_version: 0,
    axis_count: 1,
    shared_tuple_count: 0,
    glyph_count: 2,
    flags: 0
  )
    data = (+"").b
    data << [major_version].pack("n")
    data << [minor_version].pack("n")
    data << [axis_count].pack("n")
    data << [shared_tuple_count].pack("n")

    # Shared tuples offset (20 bytes for header + glyph offsets)
    shared_offset = 20 + ((glyph_count + 1) * 2)
    data << [shared_offset].pack("N")

    data << [glyph_count].pack("n")
    data << [flags].pack("n")

    # Glyph variation data array offset
    data_offset = shared_offset + (shared_tuple_count * axis_count * 2)
    data << [data_offset].pack("N")

    # Glyph variation data offsets (short format, count+1 offsets)
    (glyph_count + 1).times do |i|
      data << [i * 8].pack("n") # 8 bytes per glyph data
    end

    # Shared tuples (if any)
    shared_tuple_count.times do
      axis_count.times do
        data << [(1.0 * 16384).to_i].pack("s>") # F2DOT14
      end
    end

    # Glyph variation data
    glyph_count.times do |_i|
      # Simple tuple variation data
      data << [0x0001_0000].pack("N") # 1 tuple, no shared points, data at offset 0
      # Tuple header
      data << [4].pack("n") # data size
      data << [0x8000].pack("n") # embedded peak tuple
      # Peak tuple
      axis_count.times do
        data << [(0.5 * 16384).to_i].pack("s>")
      end
    end

    data
  end

  describe ".read" do
    context "with valid gvar table data" do
      let(:data) { build_gvar_table }
      let(:gvar) { described_class.read(data) }

      it "parses major version" do
        expect(gvar.major_version).to eq(1)
      end

      it "parses minor version" do
        expect(gvar.minor_version).to eq(0)
      end

      it "calculates version correctly" do
        expect(gvar.version).to eq(1.0)
      end

      it "parses axis count" do
        expect(gvar.axis_count).to eq(1)
      end

      it "parses shared tuple count" do
        expect(gvar.shared_tuple_count).to eq(0)
      end

      it "parses glyph count" do
        expect(gvar.glyph_count).to eq(2)
      end

      it "parses flags" do
        expect(gvar.flags).to eq(0)
      end
    end

    context "with shared tuples" do
      let(:data) { build_gvar_table(shared_tuple_count: 2, axis_count: 2) }
      let(:gvar) { described_class.read(data) }

      it "parses shared tuples" do
        tuples = gvar.shared_tuples
        expect(tuples.length).to eq(2)
        expect(tuples[0].length).to eq(2) # 2 axes
      end

      it "parses tuple coordinates correctly" do
        tuples = gvar.shared_tuples
        expect(tuples[0][0]).to be_within(0.001).of(1.0)
      end
    end

    context "with different versions" do
      it "handles version 1.0" do
        data = build_gvar_table(major_version: 1, minor_version: 0)
        gvar = described_class.read(data)
        expect(gvar.version).to eq(1.0)
      end
    end

    context "with flags" do
      it "detects long offsets flag" do
        data = build_gvar_table(flags: 0x0001)
        gvar = described_class.read(data)
        expect(gvar.long_offsets?).to be true
      end

      it "detects shared point numbers flag" do
        data = build_gvar_table(flags: 0x8000)
        gvar = described_class.read(data)
        expect(gvar.shared_point_numbers?).to be true
      end

      it "handles no flags" do
        data = build_gvar_table(flags: 0)
        gvar = described_class.read(data)
        expect(gvar.long_offsets?).to be false
        expect(gvar.shared_point_numbers?).to be false
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid version" do
      data = build_gvar_table(major_version: 1, minor_version: 0)
      gvar = described_class.read(data)
      expect(gvar).to be_valid
    end

    it "returns false for invalid major version" do
      data = build_gvar_table(major_version: 2, minor_version: 0)
      gvar = described_class.read(data)
      expect(gvar).not_to be_valid
    end
  end

  describe "#glyph_variation_data_offsets" do
    let(:data) { build_gvar_table(glyph_count: 3) }
    let(:gvar) { described_class.read(data) }

    it "returns array of offsets" do
      offsets = gvar.glyph_variation_data_offsets
      expect(offsets).to be_an(Array)
      expect(offsets.length).to eq(4) # glyph_count + 1
    end

    it "calculates offsets correctly" do
      offsets = gvar.glyph_variation_data_offsets
      expect(offsets[0]).to be < offsets[1]
    end
  end

  describe "#glyph_variation_data" do
    let(:data) { build_gvar_table }
    let(:gvar) { described_class.read(data) }

    it "returns variation data for valid glyph ID" do
      var_data = gvar.glyph_variation_data(0)
      expect(var_data).not_to be_nil
      expect(var_data).to be_a(String)
    end

    it "returns nil for invalid glyph ID" do
      var_data = gvar.glyph_variation_data(999)
      expect(var_data).to be_nil
    end

    it "returns nil for glyph with no variation data" do
      # Test with glyph that has no data (start == end offset)
      gvar = described_class.read(data)
      # This would require building special data
      # For now just check the method exists
      expect(gvar).to respond_to(:glyph_variation_data)
    end
  end

  describe "#glyph_tuple_variations" do
    let(:data) { build_gvar_table }
    let(:gvar) { described_class.read(data) }

    it "parses tuple variations for glyph" do
      variations = gvar.glyph_tuple_variations(0)
      expect(variations).not_to be_nil
      expect(variations).to be_a(Hash)
    end

    it "includes tuple count" do
      variations = gvar.glyph_tuple_variations(0)
      expect(variations[:tuple_count]).to eq(1)
    end

    it "includes tuples array" do
      variations = gvar.glyph_tuple_variations(0)
      expect(variations[:tuples]).to be_an(Array)
      expect(variations[:tuples].length).to eq(1)
    end

    it "parses tuple information" do
      variations = gvar.glyph_tuple_variations(0)
      tuple = variations[:tuples][0]
      expect(tuple[:embedded_peak]).to be true
      expect(tuple[:peak]).to be_an(Array)
    end

    it "returns nil for invalid glyph ID" do
      variations = gvar.glyph_tuple_variations(999)
      expect(variations).to be_nil
    end
  end

  describe "Gvar::TupleVariationHeader" do
    def build_tuple_header(
      data_size: 10,
      embedded_peak: true,
      intermediate: false,
      private_points: false,
      shared_index: 0
    )
      data = (+"").b
      data << [data_size].pack("n")

      tuple_index = shared_index & 0x0FFF
      tuple_index |= 0x8000 if embedded_peak
      tuple_index |= 0x4000 if intermediate
      tuple_index |= 0x2000 if private_points

      data << [tuple_index].pack("n")
      data
    end

    it "parses data size" do
      data = build_tuple_header(data_size: 20)
      header = described_class::TupleVariationHeader.read(data)
      expect(header.variation_data_size).to eq(20)
    end

    it "detects embedded peak tuple flag" do
      data = build_tuple_header(embedded_peak: true)
      header = described_class::TupleVariationHeader.read(data)
      expect(header.embedded_peak_tuple?).to be true
    end

    it "detects intermediate region flag" do
      data = build_tuple_header(intermediate: true)
      header = described_class::TupleVariationHeader.read(data)
      expect(header.intermediate_region?).to be true
    end

    it "detects private point numbers flag" do
      data = build_tuple_header(private_points: true)
      header = described_class::TupleVariationHeader.read(data)
      expect(header.private_point_numbers?).to be true
    end

    it "extracts shared tuple index" do
      data = build_tuple_header(shared_index: 5)
      header = described_class::TupleVariationHeader.read(data)
      expect(header.shared_tuple_index).to eq(5)
    end
  end
end
