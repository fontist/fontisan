# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Mvar do
  def build_mvar_table(
    major_version: 1,
    minor_version: 0,
    value_record_size: 12,
    value_record_count: 2,
    item_variation_store_offset: 40
  )
    data = (+"").b
    data << [major_version].pack("n")
    data << [minor_version].pack("n")
    data << [0].pack("n") # reserved
    data << [value_record_size].pack("n")
    data << [value_record_count].pack("n")
    data << [item_variation_store_offset].pack("N")

    # Add value records (2 * 12 bytes = 24 bytes)
    value_record_count.times do |i|
      tag = i == 0 ? "hasc" : "hdsc"
      data << tag # Already 4 bytes, no padding needed
      data << [0].pack("N") # outer index
      data << [i].pack("N") # inner index
    end
    # Total so far: 14 (header) + 24 (records) = 38 bytes
    # Add padding to reach offset 40
    data << "\x00\x00"

    # Add minimal item variation store at offset 40
    data << [1].pack("n") # format
    data << [16].pack("N") # region list offset (relative to ItemVariationStore)
    data << [1].pack("n") # data count
    data << [26].pack("N") # data offset (relative to ItemVariationStore)

    # Add padding to reach offset 16 relative to ItemVariationStore (currently at 12)
    data << "\x00\x00\x00\x00"

    # Region list at relative offset 16
    data << [1].pack("n") # axis count
    data << [1].pack("n") # region count
    data << [0].pack("s>") # start
    data << [(1.0 * 16384).to_i].pack("s>") # peak
    data << [(1.0 * 16384).to_i].pack("s>") # end

    # Item variation data at relative offset 26
    data << [2].pack("n") # item count
    data << [1].pack("n") # short delta count
    data << [1].pack("n") # region index count
    data << [0].pack("n") # region index
    data << [20].pack("s>") # delta value for item 0
    data << [25].pack("s>") # delta value for item 1

    data
  end

  describe ".read" do
    context "with valid MVAR table data" do
      let(:data) { build_mvar_table }
      let(:mvar) { described_class.read(data) }

      it "parses major version" do
        expect(mvar.major_version).to eq(1)
      end

      it "parses minor version" do
        expect(mvar.minor_version).to eq(0)
      end

      it "calculates version correctly" do
        expect(mvar.version).to eq(1.0)
      end

      it "parses value record size" do
        expect(mvar.value_record_size).to eq(12)
      end

      it "parses value record count" do
        expect(mvar.value_record_count).to eq(2)
      end

      it "parses item variation store offset" do
        expect(mvar.item_variation_store_offset).to eq(40)
      end
    end

    context "with item variation store" do
      let(:data) { build_mvar_table }
      let(:mvar) { described_class.read(data) }

      it "parses item variation store" do
        store = mvar.item_variation_store
        expect(store).not_to be_nil
        expect(store.format).to eq(1)
      end
    end

    context "with value records" do
      let(:data) { build_mvar_table }
      let(:mvar) { described_class.read(data) }

      it "parses value records" do
        records = mvar.value_records
        expect(records.length).to eq(2)
      end

      it "parses value tags" do
        records = mvar.value_records
        expect(records[0].value_tag).to eq("hasc")
        expect(records[1].value_tag).to eq("hdsc")
      end

      it "parses delta set indices" do
        records = mvar.value_records
        expect(records[0].delta_set_outer_index).to eq(0)
        expect(records[0].delta_set_inner_index).to eq(0)
        expect(records[1].delta_set_inner_index).to eq(1)
      end
    end

    context "with different versions" do
      it "handles version 1.0" do
        data = build_mvar_table(major_version: 1, minor_version: 0)
        mvar = described_class.read(data)
        expect(mvar.version).to eq(1.0)
      end

      it "handles version 1.1" do
        data = build_mvar_table(major_version: 1, minor_version: 1)
        mvar = described_class.read(data)
        expect(mvar.version).to eq(1.1)
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid version" do
      data = build_mvar_table(major_version: 1, minor_version: 0)
      mvar = described_class.read(data)
      expect(mvar).to be_valid
    end

    it "returns false for invalid major version" do
      data = build_mvar_table(major_version: 2, minor_version: 0)
      mvar = described_class.read(data)
      expect(mvar).not_to be_valid
    end

    it "returns false for invalid minor version" do
      data = build_mvar_table(major_version: 1, minor_version: 1)
      mvar = described_class.read(data)
      expect(mvar).not_to be_valid
    end
  end

  describe "#value_record" do
    let(:data) { build_mvar_table }
    let(:mvar) { described_class.read(data) }

    it "finds value record by tag" do
      record = mvar.value_record("hasc")
      expect(record).not_to be_nil
      expect(record.value_tag).to eq("hasc")
    end

    it "returns nil for non-existent tag" do
      record = mvar.value_record("xxxx")
      expect(record).to be_nil
    end
  end

  describe "#metric_delta_set" do
    let(:data) { build_mvar_table }
    let(:mvar) { described_class.read(data) }

    it "returns delta set for valid metric tag" do
      delta_set = mvar.metric_delta_set("hasc")
      expect(delta_set).not_to be_nil
      expect(delta_set).to eq([20])
    end

    it "returns different delta for different metric" do
      delta_set = mvar.metric_delta_set("hdsc")
      expect(delta_set).not_to be_nil
      expect(delta_set).to eq([25])
    end

    it "returns nil for non-existent metric" do
      delta_set = mvar.metric_delta_set("xxxx")
      expect(delta_set).to be_nil
    end
  end

  describe "#metric_tags" do
    let(:data) { build_mvar_table }
    let(:mvar) { described_class.read(data) }

    it "returns all metric tags" do
      tags = mvar.metric_tags
      expect(tags).to include("hasc", "hdsc")
      expect(tags.length).to eq(2)
    end
  end

  describe "#metrics" do
    let(:data) { build_mvar_table }
    let(:mvar) { described_class.read(data) }

    it "returns metrics hash" do
      metrics = mvar.metrics
      expect(metrics).to be_a(Hash)
      expect(metrics.keys).to include("hasc", "hdsc")
    end

    it "includes metric info" do
      metrics = mvar.metrics
      hasc = metrics["hasc"]
      expect(hasc).not_to be_nil,
                          "Expected 'hasc' key in metrics. Available keys: #{metrics.keys.inspect}"
      expect(hasc[:name]).to eq(:horizontal_ascender)
      expect(hasc[:outer_index]).to eq(0)
      expect(hasc[:inner_index]).to eq(0)
    end
  end

  describe "#has_metric?" do
    let(:data) { build_mvar_table }
    let(:mvar) { described_class.read(data) }

    it "returns true for present metric" do
      expect(mvar.has_metric?("hasc")).to be true
    end

    it "returns false for absent metric" do
      expect(mvar.has_metric?("xxxx")).to be false
    end
  end

  describe "Mvar::ValueRecord" do
    it "recognizes standard metric tags" do
      expect(described_class::METRIC_TAGS["hasc"]).to eq(:horizontal_ascender)
      expect(described_class::METRIC_TAGS["hdsc"]).to eq(:horizontal_descender)
      expect(described_class::METRIC_TAGS["hlgp"]).to eq(:horizontal_line_gap)
    end
  end
end
