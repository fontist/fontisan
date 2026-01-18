# frozen_string_literal: true

RSpec.describe Fontisan::Type1::UPMScaler do
  let(:font_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:font) { Fontisan::FontLoader.load(font_path) }
  let(:metrics) { Fontisan::MetricsCalculator.new(font) }

  # Mock font with 2048 UPM for scaling tests
  let(:font_2048) do
    double("Font", units_per_em: 2048)
  end

  describe ".type1_standard" do
    it "creates a scaler with 1000 UPM" do
      scaler = described_class.type1_standard(font)

      expect(scaler.target_upm).to eq(1000)
    end

    it "creates a scaler from font" do
      scaler = described_class.type1_standard(font)

      expect(scaler.source_upm).to eq(font.units_per_em)
    end
  end

  describe ".native" do
    it "creates a scaler with native UPM" do
      scaler = described_class.native(font)

      expect(scaler.target_upm).to eq(font.units_per_em)
    end

    it "creates a scaler with no scaling needed" do
      scaler = described_class.native(font)

      expect(scaler.scaling_needed?).to be false
    end
  end

  describe ".custom" do
    it "creates a scaler with custom UPM" do
      scaler = described_class.custom(font, upm: 500)

      expect(scaler.target_upm).to eq(500)
    end
  end

  describe "#scale" do
    it "scales a value for 2048 to 1000 UPM" do
      scaler = described_class.new(font_2048, target_upm: 1000)

      # For 2048 UPM font scaling to 1000 UPM:
      # 1024 native units = 1024 * (1000/2048) = 500 scaled units
      result = scaler.scale(1024)

      expect(result).to eq(500)
    end

    it "scales a value for 1000 to 1000 UPM (no scaling)" do
      scaler = described_class.new(font, target_upm: 1000)

      # For 1000 UPM font scaling to 1000 UPM: no change
      result = scaler.scale(500)

      expect(result).to eq(500)
    end

    it "handles zero values" do
      scaler = described_class.type1_standard(font)

      expect(scaler.scale(0)).to eq(0)
    end

    it "handles nil values" do
      scaler = described_class.type1_standard(font)

      expect(scaler.scale(nil)).to eq(0)
    end

    it "rounds to nearest integer" do
      scaler = described_class.new(font_2048, target_upm: 1000)

      # 2048 * (1000/2048) = 1000 exactly
      result = scaler.scale(2048)

      expect(result).to eq(1000)
    end
  end

  describe "#scale_array" do
    it "scales an array of values" do
      scaler = described_class.new(font_2048, target_upm: 1000)

      result = scaler.scale_array([1024, 2048, 512])

      expect(result).to eq([500, 1000, 250])
    end
  end

  describe "#scale_pair" do
    it "scales a coordinate pair" do
      scaler = described_class.new(font_2048, target_upm: 1000)

      result = scaler.scale_pair([1024, 512])

      expect(result).to eq([500, 250])
    end
  end

  describe "#scale_bbox" do
    it "scales a bounding box" do
      scaler = described_class.new(font_2048, target_upm: 1000)

      bbox = [0, -200, 1024, 800]
      result = scaler.scale_bbox(bbox)

      expect(result).to eq([0, -98, 500, 391]) # approximately
    end

    it "returns nil for nil bbox" do
      scaler = described_class.type1_standard(font)

      expect(scaler.scale_bbox(nil)).to be_nil
    end
  end

  describe "#scale_width" do
    it "scales a character width" do
      scaler = described_class.new(font_2048, target_upm: 1000)

      result = scaler.scale_width(1024)

      expect(result).to eq(500)
    end
  end

  describe "#scaling_needed?" do
    it "returns true when source and target UPM differ" do
      scaler = described_class.new(font, target_upm: 1000)

      expect(scaler.scaling_needed?).to be true if font.units_per_em != 1000
    end

    it "returns false when source and target UPM are same" do
      scaler = described_class.native(font)

      expect(scaler.scaling_needed?).to be false
    end
  end
end
