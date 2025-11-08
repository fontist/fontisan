# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::LayoutCommon do
  describe "ScriptRecord" do
    it "parses script tag and offset" do
      data = "latn".b + [100].pack("n")
      record = described_class::ScriptRecord.read(data)

      expect(record.script_tag).to eq("latn")
      expect(record.script_offset).to eq(100)
    end
  end

  describe "ScriptList" do
    it "parses script list with multiple records" do
      # script_count: 2
      # script_records: latn at 10, cyrl at 20
      data = [2].pack("n") +
        "latn".b + [10].pack("n") +
        "cyrl".b + [20].pack("n")

      script_list = described_class::ScriptList.read(data)

      expect(script_list.script_count).to eq(2)
      expect(script_list.script_records.length).to eq(2)
      expect(script_list.script_tags).to eq(%w[latn cyrl])
    end

    it "handles single script" do
      data = [1].pack("n") + "latn".b + [10].pack("n")
      script_list = described_class::ScriptList.read(data)

      expect(script_list.script_count).to eq(1)
      expect(script_list.script_tags).to eq(["latn"])
    end
  end

  describe "LangSysRecord" do
    it "parses language system tag and offset" do
      data = "ENG ".b + [50].pack("n")
      record = described_class::LangSysRecord.read(data)

      expect(record.lang_sys_tag).to eq("ENG ")
      expect(record.lang_sys_offset).to eq(50)
    end
  end

  describe "Script" do
    it "parses script with default LangSys" do
      # default_lang_sys_offset: 10
      # lang_sys_count: 0
      data = [10, 0].pack("n*")

      script = described_class::Script.read(data)

      expect(script.default_lang_sys_offset).to eq(10)
      expect(script.lang_sys_count).to eq(0)
    end

    it "parses script with LangSys records" do
      # default_lang_sys_offset: 0 (no default)
      # lang_sys_count: 1
      # lang_sys_record: ENG  at 20
      data = [0, 1].pack("n*") + "ENG ".b + [20].pack("n")

      script = described_class::Script.read(data)

      expect(script.default_lang_sys_offset).to eq(0)
      expect(script.lang_sys_count).to eq(1)
      expect(script.lang_sys_records.length).to eq(1)
    end
  end

  describe "LangSys" do
    it "parses LangSys with feature indices" do
      # lookup_order_offset: 0 (NULL)
      # required_feature_index: 0xFFFF (none required)
      # feature_index_count: 3
      # feature_indices: 0, 1, 2
      data = [0, 0xFFFF, 3, 0, 1, 2].pack("n*")

      lang_sys = described_class::LangSys.read(data)

      expect(lang_sys.lookup_order_offset).to eq(0)
      expect(lang_sys.required_feature_index).to eq(0xFFFF)
      expect(lang_sys.feature_index_count).to eq(3)
      expect(lang_sys.feature_indices).to eq([0, 1, 2])
    end
  end

  describe "FeatureRecord" do
    it "parses feature tag and offset" do
      data = "kern".b + [100].pack("n")
      record = described_class::FeatureRecord.read(data)

      expect(record.feature_tag).to eq("kern")
      expect(record.feature_offset).to eq(100)
    end
  end

  describe "FeatureList" do
    it "parses feature list with multiple records" do
      # feature_count: 2
      # feature_records: kern at 10, liga at 20
      data = [2].pack("n") +
        "kern".b + [10].pack("n") +
        "liga".b + [20].pack("n")

      feature_list = described_class::FeatureList.read(data)

      expect(feature_list.feature_count).to eq(2)
      expect(feature_list.feature_records.length).to eq(2)
      expect(feature_list.feature_tags).to eq(%w[kern liga])
    end
  end

  describe "Feature" do
    it "parses feature with lookup indices" do
      # feature_params_offset: 0 (NULL)
      # lookup_index_count: 2
      # lookup_list_indices: 0, 1
      data = [0, 2, 0, 1].pack("n*")

      feature = described_class::Feature.read(data)

      expect(feature.feature_params_offset).to eq(0)
      expect(feature.lookup_index_count).to eq(2)
      expect(feature.lookup_list_indices).to eq([0, 1])
    end
  end
end
