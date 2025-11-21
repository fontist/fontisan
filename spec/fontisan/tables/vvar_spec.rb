# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Vvar do
  def build_vvar_table(
    major_version: 1,
    minor_version: 0,
    item_variation_store_offset: 28,
    advance_height_mapping_offset: 0,
    tsb_mapping_offset: 0,
    bsb_mapping_offset: 0,
    v_org_mapping_offset: 0
  )
    data = (+"").b
    data << [major_version].pack("n")
    data << [minor_version].pack("n")
    data << [item_variation_store_offset].pack("N")
    data << [advance_height_mapping_offset].pack("N")
    data << [tsb_mapping_offset].pack("N")
    data << [bsb_mapping_offset].pack("N")
    data << [v_org_mapping_offset].pack("N")
    # VVAR header is 24 bytes, add padding to reach offset 28
    data << "\x00\x00\x00\x00"

    # Add minimal item variation store at offset 28
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
      data << [15].pack("s>") # delta value
    end

    data
  end

  describe ".read" do
    context "with valid VVAR table data" do
      let(:data) { build_vvar_table }
      let(:vvar) { described_class.read(data) }

      it "parses major version" do
        expect(vvar.major_version).to eq(1)
      end

      it "parses minor version" do
        expect(vvar.minor_version).to eq(0)
      end

      it "calculates version correctly" do
        expect(vvar.version).to eq(1.0)
      end

      it "parses item variation store offset" do
        expect(vvar.item_variation_store_offset).to eq(28)
      end

      it "parses advance height mapping offset" do
        expect(vvar.advance_height_mapping_offset).to eq(0)
      end

      it "parses TSB mapping offset" do
        expect(vvar.tsb_mapping_offset).to eq(0)
      end

      it "parses BSB mapping offset" do
        expect(vvar.bsb_mapping_offset).to eq(0)
      end

      it "parses vertical origin mapping offset" do
        expect(vvar.v_org_mapping_offset).to eq(0)
      end
    end

    context "with item variation store" do
      let(:data) { build_vvar_table }
      let(:vvar) { described_class.read(data) }

      it "parses item variation store" do
        store = vvar.item_variation_store
        expect(store).not_to be_nil
        expect(store.format).to eq(1)
      end

      it "retrieves delta set for glyph" do
        delta_set = vvar.advance_height_delta_set(0)
        expect(delta_set).to eq([15])
      end
    end

    context "without item variation store" do
      let(:data) do
        build_vvar_table(item_variation_store_offset: 0)
      end
      let(:vvar) { described_class.read(data) }

      it "returns nil for item variation store" do
        expect(vvar.item_variation_store).to be_nil
      end

      it "returns nil for delta sets" do
        expect(vvar.advance_height_delta_set(0)).to be_nil
      end
    end

    context "with different versions" do
      it "handles version 1.0" do
        data = build_vvar_table(major_version: 1, minor_version: 0)
        vvar = described_class.read(data)
        expect(vvar.version).to eq(1.0)
      end

      it "handles version 1.1" do
        data = build_vvar_table(major_version: 1, minor_version: 1)
        vvar = described_class.read(data)
        expect(vvar.version).to eq(1.1)
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid version" do
      data = build_vvar_table(major_version: 1, minor_version: 0)
      vvar = described_class.read(data)
      expect(vvar).to be_valid
    end

    it "returns false for invalid major version" do
      data = build_vvar_table(major_version: 2, minor_version: 0)
      vvar = described_class.read(data)
      expect(vvar).not_to be_valid
    end

    it "returns false for invalid minor version" do
      data = build_vvar_table(major_version: 1, minor_version: 1)
      vvar = described_class.read(data)
      expect(vvar).not_to be_valid
    end
  end

  describe "#advance_height_delta_set" do
    let(:data) { build_vvar_table }
    let(:vvar) { described_class.read(data) }

    it "returns delta set for valid glyph ID" do
      delta_set = vvar.advance_height_delta_set(0)
      expect(delta_set).not_to be_nil
      expect(delta_set).to be_an(Array)
    end

    it "returns nil without item variation store" do
      no_store_data = build_vvar_table(item_variation_store_offset: 0)
      no_store_vvar = described_class.read(no_store_data)
      expect(no_store_vvar.advance_height_delta_set(0)).to be_nil
    end
  end

  describe "#tsb_delta_set" do
    let(:data) { build_vvar_table }
    let(:vvar) { described_class.read(data) }

    it "returns delta set for valid glyph ID" do
      delta_set = vvar.tsb_delta_set(0)
      expect(delta_set).not_to be_nil
    end
  end

  describe "#bsb_delta_set" do
    let(:data) { build_vvar_table }
    let(:vvar) { described_class.read(data) }

    it "returns delta set for valid glyph ID" do
      delta_set = vvar.bsb_delta_set(0)
      expect(delta_set).not_to be_nil
    end
  end

  describe "#v_org_delta_set" do
    let(:data) { build_vvar_table }
    let(:vvar) { described_class.read(data) }

    it "returns delta set for valid glyph ID" do
      delta_set = vvar.v_org_delta_set(0)
      expect(delta_set).not_to be_nil
    end
  end
end
