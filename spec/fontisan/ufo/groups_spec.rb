# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/groups"

RSpec.describe Fontisan::Ufo::Groups do
  let(:values) do
    {
      "MMK_L_A" => %w[A Agrave Aacute Adieresis Aring],
      "MMK_R_T" => %w[T Tcommaaccent],
    }
  end

  describe ".new" do
    it "accepts a groups hash" do
      groups = described_class.new(values)
      expect(groups.groups).to eq(values)
    end

    it "defaults to an empty hash" do
      groups = described_class.new
      expect(groups.groups).to eq({})
    end
  end

  describe "#names" do
    it "lists all group names" do
      groups = described_class.new(values)
      expect(groups.names).to contain_exactly("MMK_L_A", "MMK_R_T")
    end
  end

  describe "#glyphs" do
    it "returns the glyph list for a known group" do
      groups = described_class.new(values)
      expect(groups.glyphs("MMK_L_A")).to eq(%w[A Agrave Aacute Adieresis Aring])
    end

    it "returns an empty array for an unknown group" do
      groups = described_class.new(values)
      expect(groups.glyphs("DOES_NOT_EXIST")).to eq([])
    end
  end

  describe "#include?" do
    it "is true for known group names" do
      groups = described_class.new(values)
      expect(groups.include?("MMK_L_A")).to be true
    end

    it "is false for unknown names" do
      groups = described_class.new(values)
      expect(groups.include?("DOES_NOT_EXIST")).to be false
    end
  end

  describe "#empty?" do
    it "is true for an empty Groups" do
      expect(described_class.new.empty?).to be true
    end

    it "is false when groups are defined" do
      expect(described_class.new(values).empty?).to be false
    end
  end

  describe "#to_plist" do
    it "returns the underlying groups hash" do
      groups = described_class.new(values)
      expect(groups.to_plist).to eq(values)
    end
  end
end
