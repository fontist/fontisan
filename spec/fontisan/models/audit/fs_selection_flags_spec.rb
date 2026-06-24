# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit/fs_selection_flags"

RSpec.describe Fontisan::Models::Audit::FsSelectionFlags do
  describe ".decode" do
    it "returns nil when fs_selection is nil" do
      expect(described_class.decode(nil)).to be_nil
    end

    it "returns empty array for fs_selection = 0" do
      expect(described_class.decode(0)).to eq([])
    end

    it "decodes bit 0 as 'italic'" do
      expect(described_class.decode(0x001)).to eq(["italic"])
    end

    it "decodes bit 5 as 'bold'" do
      expect(described_class.decode(0x020)).to eq(["bold"])
    end

    it "decodes bit 6 as 'regular'" do
      expect(described_class.decode(0x040)).to eq(["regular"])
    end

    it "decodes bit 9 as 'oblique'" do
      expect(described_class.decode(0x200)).to eq(["oblique"])
    end

    it "decodes multiple bits in spec bit order" do
      # italic + bold + regular (bits 0, 5, 6)
      flags = described_class.decode(0x001 | 0x020 | 0x040)
      expect(flags).to eq(%w[italic bold regular])
    end

    it "decodes all known bits" do
      all = 0x001 | 0x002 | 0x004 | 0x008 | 0x010 | 0x020 | 0x040 | 0x080 | 0x100 | 0x200
      flags = described_class.decode(all)
      expect(flags).to eq(%w[italic underscore negative outlined strikeout
                             bold regular use_typo_metrics wws oblique])
    end
  end

  describe ".from_fs_selection" do
    it "constructs an instance with decoded flags" do
      obj = described_class.from_fs_selection(0x021)
      expect(obj.flags).to eq(%w[italic bold])
    end

    it "constructs an instance with nil flags when input is nil" do
      obj = described_class.from_fs_selection(nil)
      expect(obj.flags).to be_nil
    end
  end
end
