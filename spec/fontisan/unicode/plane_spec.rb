# frozen_string_literal: true

require "spec_helper"
require "fontisan/unicode"

RSpec.describe Fontisan::Unicode::Plane do
  describe ".of" do
    it "returns the high 16 bits of the codepoint" do
      expect(described_class.of(0x41)).to     eq(0)  # BMP
      expect(described_class.of(0x10030)).to  eq(1)  # SMP
      expect(described_class.of(0x20000)).to  eq(2)  # SIP
      expect(described_class.of(0x30000)).to  eq(3)  # TIP
      expect(described_class.of(0xE0000)).to  eq(14) # SSP
    end

    it "treats 0xFFFF and 0x10000 as the BMP/SMP boundary" do
      expect(described_class.of(0xFFFF)).to  eq(0)
      expect(described_class.of(0x10000)).to eq(1)
    end
  end

  describe ".label" do
    it "maps assigned planes to standard Unicode names" do
      expect(described_class.label(0)).to  eq("BMP")
      expect(described_class.label(1)).to  eq("SMP")
      expect(described_class.label(2)).to  eq("SIP")
      expect(described_class.label(3)).to  eq("TIP")
      expect(described_class.label(14)).to eq("SSP")
    end

    it "falls back to Plane_N for unassigned planes" do
      expect(described_class.label(5)).to eq("Plane_5")
      expect(described_class.label(16)).to eq("Plane_16")
    end
  end

  describe ".label_of" do
    it "combines #of and #label" do
      expect(described_class.label_of(0x20000)).to eq("SIP")
    end
  end

  describe "LARGE_CJK_BLOCKS" do
    it "includes the CJK Extension B..F ranges" do
      expect(described_class::LARGE_CJK_BLOCKS).to include(
        "CJK_Ext_B" => 0x2A700..0x2B73F,
        "CJK_Ext_F" => 0x2EBF0..0x2EE5F,
      )
    end
  end
end
