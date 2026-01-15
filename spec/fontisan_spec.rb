# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan do
  describe ".info with brief mode" do
    let(:ttf_path) do
      fixture_path("fonts/MonaSans/mona-sans-2.0.8/googlefonts/variable/MonaSans[wdth,wght].ttf")
    end

    it "returns FontInfo model" do
      info = described_class.info(ttf_path, brief: true)
      expect(info).to be_a(Fontisan::Models::FontInfo)
    end

    it "populates essential fields" do
      info = described_class.info(ttf_path, brief: true)

      expect(info.font_format).to eq("truetype")
      expect(info.is_variable).to be true
      expect(info.family_name).not_to be_nil
      expect(info.subfamily_name).not_to be_nil
      expect(info.full_name).not_to be_nil
      expect(info.postscript_name).not_to be_nil
      expect(info.version).not_to be_nil
      expect(info.units_per_em).to be > 0
    end

    it "does not populate non-essential fields" do
      info = described_class.info(ttf_path, brief: true)

      expect(info.copyright).to be_nil
      expect(info.trademark).to be_nil
      expect(info.designer).to be_nil
      expect(info.license_description).to be_nil
    end

    it "supports font_index parameter for collections" do
      expect do
        described_class.info(ttf_path, brief: true, font_index: 0)
      end.not_to raise_error
    end

    it "serializes to JSON" do
      info = described_class.info(ttf_path, brief: true)
      json = JSON.parse(info.to_json)

      expect(json).to have_key("family_name")
      expect(json).to have_key("font_format")
    end

    it "serializes to YAML" do
      info = described_class.info(ttf_path, brief: true)
      yaml = info.to_yaml

      expect(yaml).to include("family_name:")
      expect(yaml).to include("font_format:")
    end
  end
end
