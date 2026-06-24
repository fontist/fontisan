# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/style_extractor"

RSpec.describe Fontisan::Audit::StyleExtractor do
  # Use real font fixtures (no doubles per project rules).
  let(:ttf_path) do
    font_fixture_path("NotoSans", "NotoSans-Regular.ttf")
  end
  let(:otf_path) do
    font_fixture_path("SourceSans3", "SourceSans3-Regular.otf")
  end

  describe "with a TrueType font" do
    let(:font) { Fontisan::FontLoader.load(ttf_path, mode: :full) }
    let(:extractor) { described_class.new(font) }

    it "returns a numeric weight class" do
      expect(extractor.weight_class).to be_an(Integer)
      expect(extractor.weight_class).to be > 0
    end

    it "returns a numeric width class" do
      expect(extractor.width_class).to be_an(Integer)
      expect(extractor.width_class).to be_between(1, 9)
    end

    it "italic returns truthy/falsy, not raising" do
      expect { extractor.italic }.not_to raise_error
    end

    it "bold returns truthy/falsy, not raising" do
      expect { extractor.bold }.not_to raise_error
    end

    it "panose is a 10-digit space-joined string" do
      expect(extractor.panose).to match(/\A(\d+ ){9}\d+\z/)
    end
  end

  describe "with an OpenType/CFF font" do
    let(:font) { Fontisan::FontLoader.load(otf_path, mode: :full) }
    let(:extractor) { described_class.new(font) }

    it "returns a numeric weight class" do
      expect(extractor.weight_class).to be_an(Integer)
    end

    it "returns a panose string" do
      expect(extractor.panose).to match(/\A(\d+ ){9}\d+\z/)
    end
  end
end
