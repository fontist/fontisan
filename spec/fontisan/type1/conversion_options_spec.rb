# frozen_string_literal: true

RSpec.describe Fontisan::Type1::ConversionOptions do
  describe ".new" do
    it "accepts hash of options" do
      options = described_class.new(upm_scale: 1000, format: :pfa)

      expect(options.upm_scale).to eq(1000)
      expect(options.format).to eq(:pfa)
    end

    it "uses default values for unspecified options" do
      options = described_class.new

      expect(options.upm_scale).to eq(1000)
      expect(options.format).to eq(:pfb)
      expect(options.encoding).to eq(Fontisan::Type1::Encodings::AdobeStandard)
      expect(options.decompose_composites).to be false
      expect(options.convert_curves).to be true
      expect(options.autohint).to be false
      expect(options.preserve_hinting).to be false
    end
  end

  describe ".windows_type1" do
    it "creates options for Windows Type 1" do
      options = described_class.windows_type1

      expect(options.upm_scale).to eq(1000)
      expect(options.encoding).to eq(Fontisan::Type1::Encodings::AdobeStandard)
      expect(options.format).to eq(:pfb)
    end
  end

  describe ".unix_type1" do
    it "creates options for Unix Type 1" do
      options = described_class.unix_type1

      expect(options.upm_scale).to eq(1000)
      expect(options.encoding).to eq(Fontisan::Type1::Encodings::AdobeStandard)
      expect(options.format).to eq(:pfa)
    end
  end

  describe ".native_upm" do
    it "creates options with native UPM" do
      options = described_class.native_upm

      expect(options.upm_scale).to eq(:native)
      expect(options.encoding).to eq(Fontisan::Type1::Encodings::Unicode)
    end
  end

  describe ".iso_latin1" do
    it "creates options with ISO Latin-1 encoding" do
      options = described_class.iso_latin1

      expect(options.upm_scale).to eq(1000)
      expect(options.encoding).to eq(Fontisan::Type1::Encodings::ISOLatin1)
    end
  end

  describe ".unicode_encoding" do
    it "creates options with Unicode encoding" do
      options = described_class.unicode_encoding

      expect(options.upm_scale).to eq(1000)
      expect(options.encoding).to eq(Fontisan::Type1::Encodings::Unicode)
    end
  end

  describe ".high_quality" do
    it "creates options optimized for quality" do
      options = described_class.high_quality

      expect(options.convert_curves).to be true
      expect(options.decompose_composites).to be true
    end
  end

  describe ".minimal_size" do
    it "creates options optimized for size" do
      options = described_class.minimal_size

      expect(options.convert_curves).to be false
      expect(options.format).to eq(:pfa) # PFA is more compact
    end
  end

  describe "#needs_scaling?" do
    it "returns true when upm_scale is not :native" do
      options = described_class.new(upm_scale: 1000)

      expect(options.needs_scaling?).to be true
    end

    it "returns false when upm_scale is :native" do
      options = described_class.new(upm_scale: :native)

      expect(options.needs_scaling?).to be false
    end
  end

  describe "#needs_curve_conversion?" do
    it "returns true when convert_curves is true" do
      options = described_class.new(convert_curves: true)

      expect(options.needs_curve_conversion?).to be true
    end

    it "returns false when convert_curves is false" do
      options = described_class.new(convert_curves: false)

      expect(options.needs_curve_conversion?).to be false
    end
  end

  describe "#needs_autohinting?" do
    it "returns true when autohint is true" do
      options = described_class.new(autohint: true)

      expect(options.needs_autohinting?).to be true
    end

    it "returns false when autohint is false" do
      options = described_class.new(autohint: false)

      expect(options.needs_autohinting?).to be false
    end
  end

  describe "#to_hash" do
    it "converts options to hash" do
      options = described_class.new(
        upm_scale: 1000,
        encoding: Fontisan::Type1::Encodings::Unicode,
        format: :pfa,
      )

      hash = options.to_hash

      expect(hash[:upm_scale]).to eq(1000)
      expect(hash[:encoding]).to eq(Fontisan::Type1::Encodings::Unicode)
      expect(hash[:format]).to eq(:pfa)
    end
  end

  describe "validation" do
    it "raises error for invalid upm_scale" do
      expect do
        described_class.new(upm_scale: "invalid")
      end.to raise_error(ArgumentError, /upm_scale must be/)
    end

    it "raises error for negative upm_scale" do
      expect do
        described_class.new(upm_scale: -100)
      end.to raise_error(ArgumentError, /upm_scale must be/)
    end

    it "raises error for invalid encoding" do
      expect do
        described_class.new(encoding: String)
      end.to raise_error(ArgumentError, /encoding must be/)
    end

    it "raises error for invalid format" do
      expect do
        described_class.new(format: :invalid)
      end.to raise_error(ArgumentError, /format must be/)
    end

    it "accepts valid options" do
      expect do
        described_class.new(
          upm_scale: 1000,
          encoding: Fontisan::Type1::Encodings::AdobeStandard,
          format: :pfb,
        )
      end.not_to raise_error
    end

    it "accepts :native as upm_scale" do
      expect do
        described_class.new(upm_scale: :native)
      end.not_to raise_error
    end
  end
end
