# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Cff2Subrs do
  describe ".bias" do
    it "uses bias 107 for counts 0-1240" do
      expect(described_class.bias(0)).to eq(107)
      expect(described_class.bias(1240)).to eq(107)
    end

    it "uses bias 1131 for counts 1241-33800" do
      expect(described_class.bias(1241)).to eq(1131)
      expect(described_class.bias(33_800)).to eq(1131)
    end

    it "uses bias 32768 for counts 33801+" do
      expect(described_class.bias(33_801)).to eq(32_768)
    end
  end

  describe ".build_index" do
    it "builds an INDEX from subroutines" do
      bytes = described_class.build_index(["\x01".b, "\x02".b])
      expect(bytes.unpack1("N")).to eq(2)
    end

    it "builds an empty INDEX" do
      bytes = described_class.build_index([])
      expect(bytes.unpack1("N")).to eq(0)
    end
  end
end
