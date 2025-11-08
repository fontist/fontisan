# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/font_info"

RSpec.describe Fontisan::Models::FontInfo do
  describe "initialization" do
    it "creates an instance with all attributes" do
      font_info = described_class.new(
        font_format: "truetype",
        is_variable: false,
        family_name: "Arial",
        subfamily_name: "Regular",
        full_name: "Arial Regular",
        postscript_name: "ArialMT",
        version: "Version 1.0",
        units_per_em: 2048,
        font_revision: 1.5,
      )

      expect(font_info.font_format).to eq("truetype")
      expect(font_info.is_variable).to be false
      expect(font_info.family_name).to eq("Arial")
      expect(font_info.subfamily_name).to eq("Regular")
      expect(font_info.full_name).to eq("Arial Regular")
      expect(font_info.postscript_name).to eq("ArialMT")
      expect(font_info.version).to eq("Version 1.0")
      expect(font_info.units_per_em).to eq(2048)
      expect(font_info.font_revision).to eq(1.5)
    end

    it "creates an instance with nil values" do
      font_info = described_class.new

      expect(font_info.family_name).to be_nil
      expect(font_info.subfamily_name).to be_nil
      expect(font_info.full_name).to be_nil
    end

    it "handles Unicode characters in text fields" do
      font_info = described_class.new(
        family_name: "源ノ角ゴシック",
        designer: "小林 剛",
        description: "日本語フォント with émojis 🎨✨",
        sample_text: "The quick brown 🦊 jumps over the lazy 🐶",
      )

      expect(font_info.family_name).to eq("源ノ角ゴシック")
      expect(font_info.designer).to eq("小林 剛")
      expect(font_info.description).to eq("日本語フォント with émojis 🎨✨")
      expect(font_info.sample_text).to eq("The quick brown 🦊 jumps over the lazy 🐶")
    end
  end

  describe "YAML serialization" do
    let(:font_info) do
      described_class.new(
        font_format: "truetype",
        is_variable: false,
        family_name: "Roboto",
        subfamily_name: "Bold",
        full_name: "Roboto Bold",
        postscript_name: "Roboto-Bold",
        version: "Version 2.137",
        designer: "Christian Robertson",
        manufacturer: "Google",
        copyright: "Copyright 2011 Google Inc.",
        license_description: "Apache License 2.0",
        units_per_em: 2048,
        font_revision: 2.137,
      )
    end

    it "serializes to YAML" do
      yaml = font_info.to_yaml

      expect(yaml).to include("font_format: truetype")
      expect(yaml).to include("is_variable: false")
      expect(yaml).to include("family_name: Roboto")
      expect(yaml).to include("subfamily_name: Bold")
      expect(yaml).to include("full_name: Roboto Bold")
      expect(yaml).to include("designer: Christian Robertson")
      expect(yaml).to include("units_per_em: 2048")
      expect(yaml).to include("font_revision: 2.137")
    end

    it "deserializes from YAML" do
      yaml = font_info.to_yaml
      restored = described_class.from_yaml(yaml)

      expect(restored.font_format).to eq("truetype")
      expect(restored.is_variable).to be false
      expect(restored.family_name).to eq("Roboto")
      expect(restored.subfamily_name).to eq("Bold")
      expect(restored.full_name).to eq("Roboto Bold")
      expect(restored.postscript_name).to eq("Roboto-Bold")
      expect(restored.designer).to eq("Christian Robertson")
      expect(restored.units_per_em).to eq(2048)
      expect(restored.font_revision).to eq(2.137)
    end

    it "handles YAML round-trip with Unicode" do
      font_info = described_class.new(
        family_name: "Noto Sans CJK",
        designer: "Adobe Systems & Google",
        description: "多言語対応: 中文, 日本語, 한국어",
        copyright: "© 2014-2021 Adobe Systems Incorporated",
      )

      yaml = font_info.to_yaml
      restored = described_class.from_yaml(yaml)

      expect(restored.family_name).to eq(font_info.family_name)
      expect(restored.designer).to eq(font_info.designer)
      expect(restored.description).to eq(font_info.description)
      expect(restored.copyright).to eq(font_info.copyright)
    end

    it "handles empty values in YAML" do
      font_info = described_class.new(
        family_name: "",
        subfamily_name: "",
        version: "",
      )

      yaml = font_info.to_yaml
      restored = described_class.from_yaml(yaml)

      # lutaml-model converts empty strings to nil during deserialization
      expect(restored.family_name).to be_nil
      expect(restored.subfamily_name).to be_nil
      expect(restored.version).to be_nil
    end
  end

  describe "JSON serialization" do
    let(:font_info) do
      described_class.new(
        font_format: "cff",
        is_variable: false,
        family_name: "Open Sans",
        subfamily_name: "Italic",
        full_name: "Open Sans Italic",
        postscript_name: "OpenSans-Italic",
        version: "Version 1.10",
        designer: "Steve Matteson",
        designer_url: "https://www.google.com/fonts/specimen/Open+Sans",
        vendor_id: "GOOG",
        units_per_em: 2048,
        font_revision: 1.1,
      )
    end

    it "serializes to JSON" do
      json = font_info.to_json

      expect(json).to include('"font_format":"cff"')
      expect(json).to include('"is_variable":false')
      expect(json).to include('"family_name":"Open Sans"')
      expect(json).to include('"subfamily_name":"Italic"')
      expect(json).to include('"designer":"Steve Matteson"')
      expect(json).to include('"vendor_id":"GOOG"')
      expect(json).to include('"units_per_em":2048')
      expect(json).to include('"font_revision":1.1')
    end

    it "deserializes from JSON" do
      json = font_info.to_json
      restored = described_class.from_json(json)

      expect(restored.font_format).to eq("cff")
      expect(restored.is_variable).to be false
      expect(restored.family_name).to eq("Open Sans")
      expect(restored.subfamily_name).to eq("Italic")
      expect(restored.full_name).to eq("Open Sans Italic")
      expect(restored.designer).to eq("Steve Matteson")
      expect(restored.vendor_id).to eq("GOOG")
      expect(restored.units_per_em).to eq(2048)
      expect(restored.font_revision).to eq(1.1)
    end

    it "handles JSON round-trip with all attributes" do
      font_info = described_class.new(
        font_format: "truetype",
        is_variable: true,
        family_name: "Source Code Pro",
        subfamily_name: "Medium",
        full_name: "Source Code Pro Medium",
        postscript_name: "SourceCodePro-Medium",
        postscript_cid_name: "SourceCodePro-Medium-CID",
        preferred_family: "Source Code Pro",
        preferred_subfamily: "Medium",
        mac_font_menu_name: "Source Code Pro",
        version: "Version 2.030",
        unique_id: "1.030;ADBO;SourceCodePro-Medium",
        description: "Monospaced font family for coding",
        designer: "Paul D. Hunt",
        designer_url: "https://adobe-fonts.github.io/source-code-pro/",
        manufacturer: "Adobe Systems Incorporated",
        vendor_url: "https://www.adobe.com/type",
        vendor_id: "ADBE",
        trademark: "Source is a trademark of Adobe",
        copyright: "Copyright 2010-2019 Adobe",
        license_description: "SIL Open Font License 1.1",
        license_url: "https://scripts.sil.org/OFL",
        sample_text: "The quick brown fox jumps over the lazy dog",
        font_revision: 2.03,
        permissions: "Installable",
        units_per_em: 1000,
      )

      json = font_info.to_json
      restored = described_class.from_json(json)

      expect(restored.font_format).to eq(font_info.font_format)
      expect(restored.is_variable).to eq(font_info.is_variable)
      expect(restored.family_name).to eq(font_info.family_name)
      expect(restored.postscript_cid_name).to eq(font_info.postscript_cid_name)
      expect(restored.preferred_family).to eq(font_info.preferred_family)
      expect(restored.mac_font_menu_name).to eq(font_info.mac_font_menu_name)
      expect(restored.unique_id).to eq(font_info.unique_id)
      expect(restored.trademark).to eq(font_info.trademark)
      expect(restored.permissions).to eq(font_info.permissions)
    end

    it "handles JSON round-trip with Unicode" do
      font_info = described_class.new(
        family_name: "思源黑体",
        designer: "Adobe & Google",
        sample_text: "漢字 ひらがな カタカナ 한글",
      )

      json = font_info.to_json
      restored = described_class.from_json(json)

      expect(restored.family_name).to eq(font_info.family_name)
      expect(restored.designer).to eq(font_info.designer)
      expect(restored.sample_text).to eq(font_info.sample_text)
    end

    it "handles nil values in JSON" do
      font_info = described_class.new(
        family_name: "Test Font",
        designer: nil,
        version: nil,
      )

      json = font_info.to_json
      restored = described_class.from_json(json)

      expect(restored.family_name).to eq("Test Font")
      expect(restored.designer).to be_nil
      expect(restored.version).to be_nil
    end
  end

  describe "round-trip serialization" do
    it "preserves all data through YAML round-trip" do
      original = described_class.new(
        family_name: "Liberation Sans",
        subfamily_name: "Bold Italic",
        full_name: "Liberation Sans Bold Italic",
        postscript_name: "LiberationSans-BoldItalic",
        version: "Version 2.1.5",
        designer: "Ascender Corporation",
        manufacturer: "Red Hat",
        copyright: "Copyright (c) 2012 Red Hat, Inc.",
        license_description: "SIL Open Font License",
        license_url: "https://scripts.sil.org/OFL",
        units_per_em: 2048,
        font_revision: 2.15,
      )

      yaml = original.to_yaml
      restored = described_class.from_yaml(yaml)

      expect(restored.family_name).to eq(original.family_name)
      expect(restored.subfamily_name).to eq(original.subfamily_name)
      expect(restored.full_name).to eq(original.full_name)
      expect(restored.postscript_name).to eq(original.postscript_name)
      expect(restored.version).to eq(original.version)
      expect(restored.designer).to eq(original.designer)
      expect(restored.manufacturer).to eq(original.manufacturer)
      expect(restored.copyright).to eq(original.copyright)
      expect(restored.license_description).to eq(original.license_description)
      expect(restored.license_url).to eq(original.license_url)
      expect(restored.units_per_em).to eq(original.units_per_em)
      expect(restored.font_revision).to eq(original.font_revision)
    end

    it "preserves all data through JSON round-trip" do
      original = described_class.new(
        family_name: "DejaVu Sans",
        subfamily_name: "ExtraLight",
        full_name: "DejaVu Sans ExtraLight",
        postscript_name: "DejaVuSans-ExtraLight",
        preferred_family: "DejaVu Sans",
        preferred_subfamily: "ExtraLight",
        version: "Version 2.37",
        vendor_id: "PfEd",
        units_per_em: 2048,
        font_revision: 2.37,
      )

      json = original.to_json
      restored = described_class.from_json(json)

      expect(restored.family_name).to eq(original.family_name)
      expect(restored.subfamily_name).to eq(original.subfamily_name)
      expect(restored.preferred_family).to eq(original.preferred_family)
      expect(restored.preferred_subfamily).to eq(original.preferred_subfamily)
      expect(restored.vendor_id).to eq(original.vendor_id)
      expect(restored.font_revision).to eq(original.font_revision)
    end
  end
end
