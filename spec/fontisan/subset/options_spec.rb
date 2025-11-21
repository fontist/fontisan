# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Subset::Options do
  describe "initialization" do
    it "creates options with default values" do
      options = described_class.new

      expect(options.profile).to eq("pdf")
      expect(options.drop_hints).to be(false)
      expect(options.drop_names).to be(false)
      expect(options.unicode_ranges).to be(true)
      expect(options.retain_gids).to be(false)
      expect(options.include_notdef).to be(true)
      expect(options.include_null).to be(false)
      expect(options.features).to eq([])
      expect(options.scripts).to eq(["*"])
    end

    it "accepts custom values" do
      options = described_class.new(
        profile: "web",
        drop_hints: true,
        drop_names: true,
        unicode_ranges: false,
        retain_gids: true,
        include_notdef: false,
        include_null: true,
        features: ["liga", "kern"],
        scripts: ["latn", "arab"],
      )

      expect(options.profile).to eq("web")
      expect(options.drop_hints).to be(true)
      expect(options.drop_names).to be(true)
      expect(options.unicode_ranges).to be(false)
      expect(options.retain_gids).to be(true)
      expect(options.include_notdef).to be(false)
      expect(options.include_null).to be(true)
      expect(options.features).to eq(["liga", "kern"])
      expect(options.scripts).to eq(["latn", "arab"])
    end

    it "supports partial customization" do
      options = described_class.new(profile: "minimal", drop_hints: true)

      expect(options.profile).to eq("minimal")
      expect(options.drop_hints).to be(true)
      expect(options.drop_names).to be(false)
      expect(options.unicode_ranges).to be(true)
    end
  end

  describe "#all_features?" do
    it "returns true when features array is empty" do
      options = described_class.new
      expect(options.all_features?).to be(true)
    end

    it "returns false when features are specified" do
      options = described_class.new(features: ["liga"])
      expect(options.all_features?).to be(false)
    end
  end

  describe "#all_scripts?" do
    it "returns true when scripts contains wildcard" do
      options = described_class.new
      expect(options.all_scripts?).to be(true)
    end

    it "returns true when scripts explicitly contains wildcard" do
      options = described_class.new(scripts: ["latn", "*"])
      expect(options.all_scripts?).to be(true)
    end

    it "returns false when specific scripts are specified" do
      options = described_class.new(scripts: ["latn", "arab"])
      expect(options.all_scripts?).to be(false)
    end
  end

  describe "#validate!" do
    it "validates pdf profile" do
      options = described_class.new(profile: "pdf")
      expect { options.validate! }.not_to raise_error
    end

    it "validates web profile" do
      options = described_class.new(profile: "web")
      expect { options.validate! }.not_to raise_error
    end

    it "validates minimal profile" do
      options = described_class.new(profile: "minimal")
      expect { options.validate! }.not_to raise_error
    end

    it "validates custom profile" do
      options = described_class.new(profile: "custom")
      expect { options.validate! }.not_to raise_error
    end

    it "raises error for invalid profile" do
      options = described_class.new(profile: "invalid")
      expect do
        options.validate!
      end.to raise_error(ArgumentError, /Invalid profile 'invalid'/)
    end

    it "returns true when valid" do
      options = described_class.new
      expect(options.validate!).to be(true)
    end
  end

  describe "serialization" do
    it "can be serialized using Lutaml::Model" do
      options = described_class.new(
        profile: "web",
        drop_hints: true,
        features: ["liga", "kern"],
      )

      # Test that it's a Lutaml::Model::Serializable
      expect(options).to be_a(Lutaml::Model::Serializable)
    end
  end

  describe "attribute types" do
    it "handles boolean attributes correctly" do
      options = described_class.new(drop_hints: true)
      expect(options.drop_hints).to be_a(TrueClass).or be_a(FalseClass)
    end

    it "handles string attributes correctly" do
      options = described_class.new(profile: "pdf")
      expect(options.profile).to be_a(String)
    end

    it "handles collection attributes correctly" do
      options = described_class.new(features: ["liga"])
      expect(options.features).to be_a(Array)
      expect(options.features.first).to be_a(String)
    end
  end

  describe "use cases" do
    context "PDF subsetting" do
      it "uses appropriate defaults" do
        options = described_class.new(profile: "pdf")

        expect(options.profile).to eq("pdf")
        expect(options.drop_hints).to be(false)
        expect(options.include_notdef).to be(true)
      end
    end

    context "web subsetting" do
      it "can be configured for web usage" do
        options = described_class.new(
          profile: "web",
          drop_hints: true,
          drop_names: true,
        )

        expect(options.profile).to eq("web")
        expect(options.drop_hints).to be(true)
        expect(options.drop_names).to be(true)
      end
    end

    context "minimal subsetting" do
      it "can be configured for minimal size" do
        options = described_class.new(
          profile: "minimal",
          drop_hints: true,
          drop_names: true,
          unicode_ranges: true,
        )

        expect(options.profile).to eq("minimal")
        expect(options.drop_hints).to be(true)
        expect(options.drop_names).to be(true)
      end
    end

    context "custom subsetting" do
      it "can specify custom features and scripts" do
        options = described_class.new(
          profile: "custom",
          features: ["liga", "kern", "calt"],
          scripts: ["latn"],
        )

        expect(options.profile).to eq("custom")
        expect(options.features).to eq(["liga", "kern", "calt"])
        expect(options.scripts).to eq(["latn"])
        expect(options.all_features?).to be(false)
        expect(options.all_scripts?).to be(false)
      end
    end

    context "GID retention" do
      it "can preserve original glyph IDs" do
        options = described_class.new(retain_gids: true)

        expect(options.retain_gids).to be(true)
      end
    end
  end
end
