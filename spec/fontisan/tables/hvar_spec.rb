# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Hvar do
  def build_hvar_table(
    major_version: 1,
    minor_version: 0,
    item_variation_store_offset: 24,
    advance_width_mapping_offset: 0,
    lsb_mapping_offset: 0,
    rsb_mapping_offset: 0
  )
    data = (+"").b
    data << [major_version].pack("n")
    data << [minor_version].pack("n")
    data << [item_variation_store_offset].pack("N")
    data << [advance_width_mapping_offset].pack("N")
    data << [lsb_mapping_offset].pack("N")
    data << [rsb_mapping_offset].pack("N")
    # HVAR header is 20 bytes, add padding to reach offset 24
    data << "\x00\x00\x00\x00"

    # Add minimal item variation store at offset 24
    if item_variation_store_offset > 0
      # ItemVariationStore header
      data << [1].pack("n") # format
      data << [16].pack("N") # region list offset (relative to ItemVariationStore start)
      data << [1].pack("n") # data count
      data << [26].pack("N") # data offset array entry (relative to ItemVariationStore start)

      # Add padding to reach offset 16 relative to ItemVariationStore start (currently at 12)
      data << "\x00\x00\x00\x00"

      # Region list at relative offset 16
      data << [1].pack("n") # axis count
      data << [1].pack("n") # region count
      data << [0].pack("s>") # start
      data << [(1.0 * 16384).to_i].pack("s>") # peak
      data << [(1.0 * 16384).to_i].pack("s>") # end

      # Item variation data at relative offset 26
      data << [1].pack("n") # item count
      data << [1].pack("n") # short delta count
      data << [1].pack("n") # region index count
      data << [0].pack("n") # region index
      data << [10].pack("s>") # delta value
    end

    data
  end

  describe ".read" do
    context "with valid HVAR table data" do
      let(:data) { build_hvar_table }
      let(:hvar) { described_class.read(data) }

      it "parses major version" do
        expect(hvar.major_version).to eq(1)
      end

      it "parses minor version" do
        expect(hvar.minor_version).to eq(0)
      end

      it "calculates version correctly" do
        expect(hvar.version).to eq(1.0)
      end

      it "parses item variation store offset" do
        expect(hvar.item_variation_store_offset).to eq(24)
      end

      it "parses advance width mapping offset" do
        expect(hvar.advance_width_mapping_offset).to eq(0)
      end

      it "parses LSB mapping offset" do
        expect(hvar.lsb_mapping_offset).to eq(0)
      end

      it "parses RSB mapping offset" do
        expect(hvar.rsb_mapping_offset).to eq(0)
      end
    end

    context "with item variation store" do
      let(:data) { build_hvar_table }
      let(:hvar) { described_class.read(data) }

      it "parses item variation store" do
        store = hvar.item_variation_store
        expect(store).not_to be_nil
        expect(store.format).to eq(1)
      end

      it "retrieves delta set for glyph" do
        delta_set = hvar.advance_width_delta_set(0)
        expect(delta_set).to eq([10])
      end
    end

    context "without item variation store" do
      let(:data) do
        build_hvar_table(item_variation_store_offset: 0)
      end
      let(:hvar) { described_class.read(data) }

      it "returns nil for item variation store" do
        expect(hvar.item_variation_store).to be_nil
      end

      it "returns nil for delta sets" do
        expect(hvar.advance_width_delta_set(0)).to be_nil
      end
    end

    context "with different versions" do
      it "handles version 1.0" do
        data = build_hvar_table(major_version: 1, minor_version: 0)
        hvar = described_class.read(data)
        expect(hvar.version).to eq(1.0)
      end

      it "handles version 1.1" do
        data = build_hvar_table(major_version: 1, minor_version: 1)
        hvar = described_class.read(data)
        expect(hvar.version).to eq(1.1)
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid version" do
      data = build_hvar_table(major_version: 1, minor_version: 0)
      hvar = described_class.read(data)
      expect(hvar).to be_valid
    end

    it "returns false for invalid major version" do
      data = build_hvar_table(major_version: 2, minor_version: 0)
      hvar = described_class.read(data)
      expect(hvar).not_to be_valid
    end

    it "returns false for invalid minor version" do
      data = build_hvar_table(major_version: 1, minor_version: 1)
      hvar = described_class.read(data)
      expect(hvar).not_to be_valid
    end
  end

  describe "#advance_width_delta_set" do
    let(:data) { build_hvar_table }
    let(:hvar) { described_class.read(data) }

    it "returns delta set for valid glyph ID" do
      delta_set = hvar.advance_width_delta_set(0)
      expect(delta_set).not_to be_nil
      expect(delta_set).to be_an(Array)
    end

    it "returns nil without item variation store" do
      no_store_data = build_hvar_table(item_variation_store_offset: 0)
      no_store_hvar = described_class.read(no_store_data)
      expect(no_store_hvar.advance_width_delta_set(0)).to be_nil
    end
  end

  describe "#lsb_delta_set" do
    let(:data) { build_hvar_table }
    let(:hvar) { described_class.read(data) }

    it "returns delta set for valid glyph ID" do
      delta_set = hvar.lsb_delta_set(0)
      expect(delta_set).not_to be_nil
    end
  end

  describe "#rsb_delta_set" do
    let(:data) { build_hvar_table }
    let(:hvar) { described_class.read(data) }

    it "returns delta set for valid glyph ID" do
      delta_set = hvar.rsb_delta_set(0)
      expect(delta_set).not_to be_nil
    end
  end
end
