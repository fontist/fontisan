# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Gpos do
  let(:ttf_font_path) do
    font_fixture_path("Libertinus", "static/TTF/LibertinusSerif-Regular.ttf")
  end
  let(:otf_font_path) do
    font_fixture_path("Libertinus", "static/OTF/LibertinusSerif-Regular.otf")
  end

  describe "#scripts" do
    context "with TrueType font" do
      it "extracts script tags from GPOS table" do
        font = Fontisan::TrueTypeFont.from_file(ttf_font_path)
        gpos = font.table("GPOS")

        expect(gpos).not_to be_nil
        scripts = gpos.scripts

        expect(scripts).to be_an(Array)
        expect(scripts).to include("latn")
        scripts.each do |script|
          expect(script.to_s.length).to eq(4)
        end
      end
    end

    context "with OpenType font" do
      it "extracts script tags from GPOS table" do
        font = Fontisan::OpenTypeFont.from_file(otf_font_path)
        gpos = font.table("GPOS")

        expect(gpos).not_to be_nil
        scripts = gpos.scripts

        expect(scripts).to be_an(Array)
        expect(scripts).to include("latn")
        expect(scripts.length).to be > 0
      end
    end

    context "when GPOS table has no scripts" do
      it "returns empty array" do
        # Create minimal GPOS with zero script_list_offset
        data = [1, 0, 0, 0, 0].pack("n*") + ("\x00" * 10)
        gpos = described_class.read(data)

        expect(gpos.scripts).to eq([])
      end
    end
  end

  describe "#features" do
    context "with TrueType font" do
      it "extracts feature tags for Latin script" do
        font = Fontisan::TrueTypeFont.from_file(ttf_font_path)
        gpos = font.table("GPOS")

        features = gpos.features(script_tag: "latn")

        expect(features).to be_an(Array)
        features.each do |feature|
          expect(feature.to_s.length).to eq(4)
        end
        expect(features).to include("kern") # kern is common in GPOS
      end

      it "returns empty array for non-existent script" do
        font = Fontisan::TrueTypeFont.from_file(ttf_font_path)
        gpos = font.table("GPOS")

        features = gpos.features(script_tag: "XXXX")

        expect(features).to eq([])
      end
    end

    context "with OpenType font" do
      it "extracts feature tags for Latin script" do
        font = Fontisan::OpenTypeFont.from_file(otf_font_path)
        gpos = font.table("GPOS")

        features = gpos.features(script_tag: "latn")

        expect(features).to be_an(Array)
        expect(features.length).to be > 0
      end
    end
  end

  describe "table structure" do
    it "parses major and minor version" do
      font = Fontisan::TrueTypeFont.from_file(ttf_font_path)
      gpos = font.table("GPOS")

      expect(gpos.major_version.to_i).to be >= 1
      expect(gpos.minor_version.to_i).to be >= 0
    end

    it "has valid offsets" do
      font = Fontisan::TrueTypeFont.from_file(ttf_font_path)
      gpos = font.table("GPOS")

      expect(gpos.script_list_offset.to_i).to be >= 0
      expect(gpos.feature_list_offset.to_i).to be >= 0
      expect(gpos.lookup_list_offset.to_i).to be >= 0
    end
  end
end
