# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/info"

RSpec.describe Fontisan::Ufo::Info do
  describe "#initialize" do
    it "accepts standard UFO 3 fields" do
      info = described_class.new(
        "familyName" => "Last Resort",
        "unitsPerEm" => 1024,
        "ascender" => 800,
        "italicAngle" => 0.0,
      )

      expect(info.family_name).to eq("Last Resort")
      expect(info.units_per_em).to eq(1024)
      expect(info.ascender).to eq(800)
      expect(info.italic_angle).to eq(0.0)
    end

    it "stores unrecognized fields in extras" do
      info = described_class.new("vendorSpecific" => "anything")
      expect(info.family_name).to be_nil
      expect(info.extras).to eq("vendorSpecific" => "anything")
    end
  end

  describe "#to_plist" do
    it "returns a camelCase hash matching UFO 3" do
      info = described_class.new
      info.family_name = "Essenfont"
      info.units_per_em = 1000
      info.italic_angle = 0.0

      plist = info.to_plist
      expect(plist["familyName"]).to eq("Essenfont")
      expect(plist["unitsPerEm"]).to eq(1000)
      expect(plist["italicAngle"]).to eq(0.0)
    end

    it "omits nil fields" do
      info = described_class.new
      info.family_name = "Only Name"
      plist = info.to_plist
      expect(plist).to eq("familyName" => "Only Name")
    end

    it "round-trips through Plist" do
      info = described_class.new
      info.family_name = "Round Trip"
      info.units_per_em = 2048
      info.ascender = 700

      require "fontisan/ufo/plist"
      xml = Fontisan::Ufo::Plist.emit(info.to_plist)
      back = Fontisan::Ufo::Plist.parse(xml)

      info2 = described_class.new(back)
      expect(info2.family_name).to eq("Round Trip")
      expect(info2.units_per_em).to eq(2048)
      expect(info2.ascender).to eq(700)
    end
  end
end
