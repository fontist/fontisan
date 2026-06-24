# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit/embedding_type"

RSpec.describe Fontisan::Models::Audit::EmbeddingType do
  describe ".decode" do
    it "returns nil when fs_type is nil" do
      expect(described_class.decode(nil)).to be_nil
    end

    it "returns 'installable' for fs_type = 0" do
      expect(described_class.decode(0)).to eq("installable")
    end

    it "returns 'restricted_license' when bit 0 is set" do
      expect(described_class.decode(0x0001)).to eq("restricted_license")
    end

    it "returns 'preview_print' when bit 1 is set" do
      expect(described_class.decode(0x0002)).to eq("preview_print")
    end

    it "returns 'editable' when bit 2 is set" do
      expect(described_class.decode(0x0004)).to eq("editable")
    end

    it "returns 'installable' when bit 3 is set alone" do
      expect(described_class.decode(0x0008)).to eq("installable")
    end

    it "returns 'installable_no_subsetting' when bit 3 + 8 set" do
      expect(described_class.decode(0x0108)).to eq("installable_no_subsetting")
    end

    it "returns 'installable_bitmap_only' when bit 3 + 9 set" do
      expect(described_class.decode(0x0208)).to eq("installable_bitmap_only")
    end

    it "returns 'installable_no_subsetting_bitmap_only' when bits 3 + 8 + 9 set" do
      expect(described_class.decode(0x0308)).to eq("installable_no_subsetting_bitmap_only")
    end

    it "treats only modifier bits (no base) as 'unknown'" do
      expect(described_class.decode(0x0100)).to eq("unknown")
    end

    it "prioritizes restricted_license over other base flags" do
      expect(described_class.decode(0x000F)).to eq("restricted_license")
    end
  end

  describe ".from_fs_type" do
    it "constructs an instance with decoded value" do
      obj = described_class.from_fs_type(0x0004)
      expect(obj.value).to eq("editable")
    end

    it "constructs an instance with nil value when input is nil" do
      obj = described_class.from_fs_type(nil)
      expect(obj.value).to be_nil
    end
  end

  describe "#to_s" do
    it "returns the decoded value" do
      obj = described_class.from_fs_type(0x0004)
      expect(obj.to_s).to eq("editable")
    end
  end
end
