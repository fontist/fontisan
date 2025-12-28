# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::FeaturesCommand do
  let(:ttf_font_path) do
    font_fixture_path("Libertinus", "static/TTF/LibertinusSerif-Regular.ttf")
  end
  let(:otf_font_path) do
    font_fixture_path("Libertinus", "static/OTF/LibertinusSerif-Regular.otf")
  end

  describe "#run" do
    context "with specific script" do
      it "returns FeaturesInfo for the specified script" do
        command = described_class.new(ttf_font_path, { script: "latn" })
        result = command.run

        expect(result).to be_a(Fontisan::Models::FeaturesInfo)
        expect(result.script).to eq("latn")
        expect(result.feature_count).to be > 0
        expect(result.features).to be_an(Array)
        expect(result.features).to all(be_a(Fontisan::Models::FeatureRecord))
      end

      it "includes feature descriptions" do
        command = described_class.new(ttf_font_path, { script: "latn" })
        result = command.run

        # Common features in most fonts
        common_features = %w[kern mark]
        matching_features = result.features.select do |f|
          common_features.include?(f.tag)
        end

        expect(matching_features).not_to be_empty
        matching_features.each do |feature|
          expect(feature.description).not_to be_nil
          expect(feature.description).not_to eq("Unknown feature")
        end
      end

      it "sorts features alphabetically" do
        command = described_class.new(ttf_font_path, { script: "latn" })
        result = command.run

        tags = result.features.map(&:tag)
        expect(tags).to eq(tags.sort)
      end
    end

    context "without script specified" do
      it "returns AllScriptsFeaturesInfo with all scripts" do
        command = described_class.new(ttf_font_path, {})
        result = command.run

        expect(result).to be_a(Fontisan::Models::AllScriptsFeaturesInfo)
        expect(result.scripts_features).to be_an(Array)
        expect(result.scripts_features).to all(be_a(Fontisan::Models::FeaturesInfo))
      end

      it "includes features for multiple scripts" do
        command = described_class.new(ttf_font_path, {})
        result = command.run

        expect(result.scripts_features.length).to be > 0

        # Each script should have its features
        result.scripts_features.each do |script_features|
          expect(script_features.script).to be_a(String)
          expect(script_features.script.length).to eq(4)
          expect(script_features.features).to be_an(Array)
        end
      end

      it "sorts scripts alphabetically" do
        command = described_class.new(ttf_font_path, {})
        result = command.run

        script_tags = result.scripts_features.map(&:script)
        expect(script_tags).to eq(script_tags.sort)
      end
    end

    context "with OpenType font" do
      it "returns features for specified script" do
        command = described_class.new(otf_font_path, { script: "latn" })
        result = command.run

        expect(result).to be_a(Fontisan::Models::FeaturesInfo)
        expect(result.feature_count).to be > 0
      end

      it "returns all scripts features when not specified" do
        command = described_class.new(otf_font_path, {})
        result = command.run

        expect(result).to be_a(Fontisan::Models::AllScriptsFeaturesInfo)
        expect(result.scripts_features.length).to be > 0
      end
    end

    context "with non-existent script" do
      it "returns empty features list" do
        command = described_class.new(ttf_font_path, { script: "XXXX" })
        result = command.run

        expect(result).to be_a(Fontisan::Models::FeaturesInfo)
        expect(result.script).to eq("XXXX")
        expect(result.feature_count).to eq(0)
        expect(result.features).to eq([])
      end
    end
  end
end
