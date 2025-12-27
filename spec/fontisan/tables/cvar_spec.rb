# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cvar do
  def build_cvar_table(
    major_version: 1,
    minor_version: 0,
    tuple_variation_count: 1,
    data_offset: 12
  )
    data = (+"").b
    data << [major_version].pack("n")
    data << [minor_version].pack("n")
    data << [tuple_variation_count].pack("n")
    data << [data_offset].pack("n")

    # Add tuple variation header
    data << [8].pack("n") # data size
    data << [0x8000].pack("n") # embedded peak tuple flag

    # Peak tuple (assuming 1 axis for simplicity)
    data << [(0.5 * 16384).to_i].pack("s>") # F2DOT14

    # Variation data (placeholder)
    data << [0, 0, 0, 0].pack("C4")

    data
  end

  describe ".read" do
    context "with valid cvar table data" do
      let(:data) { build_cvar_table }
      let(:cvar) { described_class.read(data) }

      it "parses major version" do
        expect(cvar.major_version).to eq(1)
      end

      it "parses minor version" do
        expect(cvar.minor_version).to eq(0)
      end

      it "calculates version correctly" do
        expect(cvar.version).to eq(1.0)
      end

      it "parses tuple variation count field" do
        expect(cvar.tuple_variation_count).to eq(1)
      end

      it "extracts tuple count" do
        expect(cvar.tuple_count).to eq(1)
      end

      it "parses data offset" do
        expect(cvar.data_offset).to eq(12)
      end
    end

    context "with shared point numbers flag" do
      it "detects shared point numbers" do
        # Set bit 15 for shared points
        data = build_cvar_table(tuple_variation_count: 0x8001)
        cvar = described_class.read(data)
        expect(cvar.shared_point_numbers?).to be true
        expect(cvar.tuple_count).to eq(1) # Lower 12 bits
      end

      it "handles no shared point numbers" do
        data = build_cvar_table(tuple_variation_count: 0x0001)
        cvar = described_class.read(data)
        expect(cvar.shared_point_numbers?).to be false
      end
    end

    context "with different versions" do
      it "handles version 1.0" do
        data = build_cvar_table(major_version: 1, minor_version: 0)
        cvar = described_class.read(data)
        expect(cvar.version).to eq(1.0)
      end

      it "handles version 1.1" do
        data = build_cvar_table(major_version: 1, minor_version: 1)
        cvar = described_class.read(data)
        expect(cvar.version).to eq(1.1)
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid version" do
      data = build_cvar_table(major_version: 1, minor_version: 0)
      cvar = described_class.read(data)
      expect(cvar).to be_valid
    end

    it "returns false for invalid major version" do
      data = build_cvar_table(major_version: 2, minor_version: 0)
      cvar = described_class.read(data)
      expect(cvar).not_to be_valid
    end
  end

  describe "#tuple_variations" do
    let(:data) { build_cvar_table }
    let(:cvar) do
      c = described_class.read(data)
      c.axis_count = 1 # Set axis count for parsing
      c
    end

    it "returns array of tuple variations" do
      tuples = cvar.tuple_variations
      expect(tuples).to be_an(Array)
    end

    it "parses tuple information" do
      tuples = cvar.tuple_variations
      expect(tuples.length).to eq(1)
      expect(tuples[0]).to be_a(Hash)
    end

    it "includes tuple flags" do
      tuples = cvar.tuple_variations
      tuple = tuples[0]
      expect(tuple[:embedded_peak]).to be true
      expect(tuple[:data_size]).to eq(8)
    end

    it "parses embedded peak tuple" do
      tuples = cvar.tuple_variations
      tuple = tuples[0]
      expect(tuple[:peak]).to be_an(Array)
      expect(tuple[:peak][0]).to be_within(0.001).of(0.5)
    end
  end

  describe "#variation_data" do
    let(:data) { build_cvar_table }
    let(:cvar) { described_class.read(data) }

    it "returns variation data section" do
      var_data = cvar.variation_data
      expect(var_data).not_to be_nil
      expect(var_data).to be_a(String)
    end
  end

  describe "#tuple_variation_data" do
    let(:data) { build_cvar_table }
    let(:cvar) do
      c = described_class.read(data)
      c.axis_count = 1
      c
    end

    it "returns tuple data for valid index" do
      tuple_data = cvar.tuple_variation_data(0)
      expect(tuple_data).not_to be_nil
      expect(tuple_data).to be_a(Hash)
    end

    it "includes tuple information" do
      tuple_data = cvar.tuple_variation_data(0)
      expect(tuple_data[:tuple]).to be_a(Hash)
      expect(tuple_data[:data_size]).to eq(8)
    end

    it "returns nil for invalid index" do
      tuple_data = cvar.tuple_variation_data(999)
      expect(tuple_data).to be_nil
    end
  end

  describe "#summary" do
    let(:data) { build_cvar_table }
    let(:cvar) do
      c = described_class.read(data)
      c.axis_count = 1
      c
    end

    it "returns summary hash" do
      summary = cvar.summary
      expect(summary).to be_a(Hash)
    end

    it "includes version information" do
      summary = cvar.summary
      expect(summary[:version]).to eq(1.0)
    end

    it "includes tuple count" do
      summary = cvar.summary
      expect(summary[:tuple_count]).to eq(1)
    end

    it "includes shared points flag" do
      summary = cvar.summary
      expect(summary[:shared_points]).to be false
    end

    it "includes tuples array" do
      summary = cvar.summary
      expect(summary[:tuples]).to be_an(Array)
      expect(summary[:tuples].length).to eq(1)
    end
  end

  describe "Cvar::TupleVariationHeader" do
    def build_tuple_header(
      data_size: 10,
      embedded_peak: true,
      intermediate: false,
      private_points: false
    )
      data = (+"").b
      data << [data_size].pack("n")

      tuple_index = 0
      tuple_index |= 0x8000 if embedded_peak
      tuple_index |= 0x4000 if intermediate
      tuple_index |= 0x2000 if private_points

      data << [tuple_index].pack("n")
      data
    end

    it "parses data size" do
      data = build_tuple_header(data_size: 20)
      header = Fontisan::Variation::TupleVariationHeader.read(data)
      expect(header.variation_data_size).to eq(20)
    end

    it "detects embedded peak tuple flag" do
      data = build_tuple_header(embedded_peak: true)
      header = Fontisan::Variation::TupleVariationHeader.read(data)
      expect(header.embedded_peak_tuple?).to be true
    end

    it "detects intermediate region flag" do
      data = build_tuple_header(intermediate: true)
      header = Fontisan::Variation::TupleVariationHeader.read(data)
      expect(header.intermediate_region?).to be true
    end

    it "detects private point numbers flag" do
      data = build_tuple_header(private_points: true)
      header = Fontisan::Variation::TupleVariationHeader.read(data)
      expect(header.private_point_numbers?).to be true
    end

    it "extracts shared tuple index" do
      data = build_tuple_header
      header = Fontisan::Variation::TupleVariationHeader.read(data)
      expect(header.shared_tuple_index).to eq(0)
    end
  end
end
