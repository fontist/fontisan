# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Gsub do
  let(:ttf_font_path) do
    font_fixture_path("NotoSans", "NotoSans-Regular.ttf")
  end
  let(:otf_font_path) do
    font_fixture_path("Libertinus", "static/OTF/LibertinusSerif-Regular.otf")
  end

  describe "#scripts" do
    context "with TrueType font" do
      it "extracts script tags from GSUB table" do
        font = Fontisan::TrueTypeFont.from_file(ttf_font_path)

        # Skip if font doesn't have GSUB table
        skip "Font has no GSUB table" unless font.has_table?("GSUB")

        gsub = font.table("GSUB")
        scripts = gsub.scripts

        expect(scripts).to be_an(Array)
        expect(scripts).to include("latn")
        expect(scripts).to all(be_a(String).or(be_a(BinData::String)))
        expect(scripts.map(&:to_s)).to all(have_attributes(length: 4))
      end
    end

    context "with OpenType font" do
      it "extracts script tags from GSUB table" do
        font = Fontisan::OpenTypeFont.from_file(otf_font_path)

        # Check if font has GSUB table
        if font.has_table?("GSUB")
          gsub = font.table("GSUB")
          scripts = gsub.scripts

          expect(scripts).to be_an(Array)
          expect(scripts.length).to be > 0
        else
          skip "OpenType font has no GSUB table"
        end
      end
    end

    context "when GSUB table has no scripts" do
      it "returns empty array" do
        # Create minimal GSUB with zero script_list_offset
        data = [1, 0, 0, 0, 0].pack("n*") + ("\x00" * 10)
        gsub = described_class.read(data)

        expect(gsub.scripts).to eq([])
      end
    end
  end

  describe "#features" do
    context "with TrueType font" do
      it "extracts feature tags for Latin script" do
        font = Fontisan::TrueTypeFont.from_file(ttf_font_path)

        # Skip if font doesn't have GSUB table
        skip "Font has no GSUB table" unless font.has_table?("GSUB")

        gsub = font.table("GSUB")
        features = gsub.features(script_tag: "latn")

        expect(features).to be_an(Array)
        expect(features).to all(be_a(String).or(be_a(BinData::String)))
        expect(features.map(&:to_s)).to all(have_attributes(length: 4))
      end

      it "returns empty array for non-existent script" do
        font = Fontisan::TrueTypeFont.from_file(ttf_font_path)

        # Skip if font doesn't have GSUB table
        skip "Font has no GSUB table" unless font.has_table?("GSUB")

        gsub = font.table("GSUB")
        features = gsub.features(script_tag: "XXXX")

        expect(features).to eq([])
      end
    end

    context "with OpenType font" do
      it "extracts feature tags for Latin script" do
        font = Fontisan::OpenTypeFont.from_file(otf_font_path)

        # Check if font has GSUB table
        if font.has_table?("GSUB")
          gsub = font.table("GSUB")
          features = gsub.features(script_tag: "latn")

          expect(features).to be_an(Array)
          expect(features.length).to be > 0
        else
          skip "OpenType font has no GSUB table"
        end
      end
    end
  end

  describe "table structure" do
    it "parses major and minor version" do
      font = Fontisan::OpenTypeFont.from_file(otf_font_path)
      gsub = font.table("GSUB")

      expect(gsub.major_version.to_i).to be >= 1
      expect(gsub.minor_version.to_i).to be >= 0
    end

    it "has valid offsets" do
      font = Fontisan::OpenTypeFont.from_file(otf_font_path)
      gsub = font.table("GSUB")

      expect(gsub.script_list_offset.to_i).to be >= 0
      expect(gsub.feature_list_offset.to_i).to be >= 0
      expect(gsub.lookup_list_offset.to_i).to be >= 0
    end
  end
end
