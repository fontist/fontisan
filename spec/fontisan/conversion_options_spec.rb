# frozen_string_literal: true

RSpec.describe Fontisan::ConversionOptions do
  describe ".initialize" do
    it "normalizes format symbols" do
      opts = described_class.new(from: "TTF", to: "OTF")
      expect(opts.from).to eq(:ttf)
      expect(opts.to).to eq(:otf)
    end

    it "accepts symbol formats" do
      opts = described_class.new(from: :ttf, to: :otf)
      expect(opts.from).to eq(:ttf)
      expect(opts.to).to eq(:otf)
    end

    it "applies default opening options" do
      opts = described_class.new(from: :ttf, to: :otf)
      expect(opts.opening[:convert_curves]).to be true
      expect(opts.opening[:scale_to_1000]).to be true
    end

    it "applies default generating options" do
      opts = described_class.new(from: :ttf, to: :otf)
      expect(opts.generating[:hinting_mode]).to eq("auto")
    end

    it "merges user options with defaults" do
      opts = described_class.new(
        from: :ttf,
        to: :otf,
        opening: { autohint: false },
        generating: { hinting_mode: "none" },
      )
      expect(opts.opening[:convert_curves]).to be true # default
      expect(opts.opening[:autohint]).to be false # user override
      expect(opts.generating[:hinting_mode]).to eq("none") # user override
    end
  end

  describe ".normalize_format" do
    it "normalizes TTF variants" do
      expect(described_class.send(:normalize_format, "TTF")).to eq(:ttf)
      expect(described_class.send(:normalize_format, "truetype")).to eq(:ttf)
      expect(described_class.send(:normalize_format, :ttf)).to eq(:ttf)
    end

    it "normalizes OTF variants" do
      expect(described_class.send(:normalize_format, "OTF")).to eq(:otf)
      expect(described_class.send(:normalize_format, "cff")).to eq(:otf)
      expect(described_class.send(:normalize_format, "opentype")).to eq(:otf)
    end

    it "normalizes Type 1 variants" do
      expect(described_class.send(:normalize_format, "type1")).to eq(:type1)
      expect(described_class.send(:normalize_format, "pfb")).to eq(:type1)
      expect(described_class.send(:normalize_format, "pfa")).to eq(:type1)
    end

    it "raises error for unknown format" do
      expect do
        described_class.send(:normalize_format, "unknown")
      end.to raise_error(ArgumentError, /Unknown format/)
    end
  end

  describe ".recommended" do
    it "returns recommended options for TTF → OTF" do
      opts = described_class.recommended(from: :ttf, to: :otf)
      expect(opts.from).to eq(:ttf)
      expect(opts.to).to eq(:otf)
      expect(opts.opening[:convert_curves]).to be true
      expect(opts.opening[:scale_to_1000]).to be true
      expect(opts.opening[:autohint]).to be true
    end

    it "returns recommended options for Type 1 → OTF" do
      opts = described_class.recommended(from: :type1, to: :otf)
      expect(opts.from).to eq(:type1)
      expect(opts.to).to eq(:otf)
      expect(opts.opening[:generate_unicode]).to be true
      expect(opts.generating[:hinting_mode]).to eq("none")
    end

    it "returns recommended options for OTF → Type 1" do
      opts = described_class.recommended(from: :otf, to: :type1)
      expect(opts.from).to eq(:otf)
      expect(opts.to).to eq(:type1)
      expect(opts.generating[:write_pfm]).to be true
      expect(opts.generating[:write_afm]).to be true
    end
  end

  describe ".from_preset" do
    it "loads type1_to_modern preset" do
      opts = described_class.from_preset(:type1_to_modern)
      expect(opts.from).to eq(:type1)
      expect(opts.to).to eq(:otf)
      expect(opts.opening[:generate_unicode]).to be true
      expect(opts.generating[:hinting_mode]).to eq("preserve")
    end

    it "loads modern_to_type1 preset" do
      opts = described_class.from_preset(:modern_to_type1)
      expect(opts.from).to eq(:otf)
      expect(opts.to).to eq(:type1)
      expect(opts.opening[:scale_to_1000]).to be true
      expect(opts.generating[:write_pfm]).to be true
    end

    it "loads web_optimized preset" do
      opts = described_class.from_preset(:web_optimized)
      expect(opts.from).to eq(:otf)
      expect(opts.to).to eq(:woff2)
      expect(opts.generating[:compression]).to eq("brotli")
    end

    it "raises error for unknown preset" do
      expect do
        described_class.from_preset(:unknown_preset)
      end.to raise_error(ArgumentError, /Unknown preset/)
    end
  end

  describe ".available_presets" do
    it "returns list of available presets" do
      presets = described_class.available_presets
      expect(presets).to include(:type1_to_modern)
      expect(presets).to include(:modern_to_type1)
      expect(presets).to include(:web_optimized)
      expect(presets).to include(:archive_to_modern)
    end
  end

  describe "#opening_option?" do
    it "returns true for truthy options" do
      opts = described_class.new(
        from: :ttf,
        to: :otf,
        opening: { convert_curves: true },
      )
      expect(opts.opening_option?(:convert_curves)).to be true
    end

    it "returns false for falsy options" do
      opts = described_class.new(
        from: :ttf,
        to: :otf,
        opening: { convert_curves: false },
      )
      expect(opts.opening_option?(:convert_curves)).to be false
    end
  end

  describe "#generating_option?" do
    it "returns true for matching value" do
      opts = described_class.new(
        from: :ttf,
        to: :otf,
        generating: { hinting_mode: "auto" },
      )
      expect(opts.generating_option?(:hinting_mode, "auto")).to be true
    end

    it "returns false for non-matching value" do
      opts = described_class.new(
        from: :ttf,
        to: :otf,
        generating: { hinting_mode: "none" },
      )
      expect(opts.generating_option?(:hinting_mode, "auto")).to be false
    end

    it "defaults to checking for true" do
      opts = described_class.new(
        from: :ttf,
        to: :otf,
        generating: { optimize_tables: true },
      )
      expect(opts.generating_option?(:optimize_tables)).to be true
    end
  end

  describe "validation" do
    it "raises error for unknown opening option" do
      expect do
        described_class.new(
          from: :ttf,
          to: :otf,
          opening: { unknown_option: true },
        )
      end.to raise_error(ArgumentError, /Unknown opening option/)
    end

    it "raises error for unknown generating option" do
      expect do
        described_class.new(
          from: :ttf,
          to: :otf,
          generating: { unknown_option: true },
        )
      end.to raise_error(ArgumentError, /Unknown generating option/)
    end

    it "raises error for invalid hinting_mode" do
      expect do
        described_class.new(
          from: :ttf,
          to: :otf,
          generating: { hinting_mode: "invalid" },
        )
      end.to raise_error(ArgumentError, /Invalid hinting_mode/)
    end

    it "raises error for invalid compression mode" do
      expect do
        described_class.new(
          from: :ttf,
          to: :woff2,
          generating: { compression: "invalid" },
        )
      end.to raise_error(ArgumentError, /Invalid compression/)
    end

    it "accepts valid hinting modes" do
      %w[preserve auto none full].each do |mode|
        opts = described_class.new(
          from: :ttf,
          to: :otf,
          generating: { hinting_mode: mode },
        )
        expect(opts.generating[:hinting_mode]).to eq(mode)
      end
    end

    it "accepts valid compression modes" do
      %w[zlib brotli none].each do |comp|
        opts = described_class.new(
          from: :ttf,
          to: :woff2,
          generating: { compression: comp },
        )
        expect(opts.generating[:compression]).to eq(comp)
      end
    end
  end

  describe "option defaults" do
    context "TTF → OTF" do
      it "applies correct defaults" do
        opts = described_class.new(from: :ttf, to: :otf)
        expect(opts.opening[:convert_curves]).to be true
        expect(opts.opening[:scale_to_1000]).to be true
        expect(opts.opening[:autohint]).to be true
        expect(opts.generating[:hinting_mode]).to eq("auto")
      end
    end

    context "OTF → TTF" do
      it "applies correct defaults" do
        opts = described_class.new(from: :otf, to: :ttf)
        expect(opts.opening[:convert_curves]).to be true
        expect(opts.opening[:decompose_composites]).to be false
        expect(opts.generating[:hinting_mode]).to eq("auto")
      end
    end

    context "Type 1 → OTF" do
      it "applies correct defaults" do
        opts = described_class.new(from: :type1, to: :otf)
        expect(opts.opening[:decompose_composites]).to be false
        expect(opts.opening[:generate_unicode]).to be true
        expect(opts.generating[:hinting_mode]).to eq("preserve")
      end
    end

    context "TTF → Type 1" do
      it "applies correct defaults" do
        opts = described_class.new(from: :ttf, to: :type1)
        expect(opts.opening[:convert_curves]).to be true
        expect(opts.opening[:scale_to_1000]).to be true
        expect(opts.generating[:write_pfm]).to be true
        expect(opts.generating[:write_afm]).to be true
      end
    end
  end
end
