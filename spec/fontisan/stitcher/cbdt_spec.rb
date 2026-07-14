# frozen_string_literal: true

require "spec_helper"
require "fontisan"
require "fontisan/stitcher"

RSpec.describe Fontisan::Stitcher::Source, "#bitmap_mode" do
  # FakeFont includes SfntSource so Stitcher::Source's is_a?(SfntSource)
  # check accepts it.
  let(:fake_ttf) do
    Fontisan::SpecHelpers::FakeFont.new({})
  end

  it "returns :cbdt when both CBDT and CBLC are present" do
    fake_ttf.tables_hash["CBDT"] = ""
    fake_ttf.tables_hash["CBLC"] = ""

    source = described_class.new(fake_ttf)
    expect(source.bitmap_mode).to eq(:cbdt)
  end

  it "returns :glyf when only glyf is present" do
    fake_ttf.tables_hash["glyf"] = ""

    source = described_class.new(fake_ttf)
    expect(source.bitmap_mode).to eq(:glyf)
  end

  it "returns :glyf when only CFF is present (OTF)" do
    fake_ttf.tables_hash["CFF "] = ""

    source = described_class.new(fake_ttf)
    expect(source.bitmap_mode).to eq(:glyf)
  end

  it "returns :mixed when both glyf and CBDT are present" do
    fake_ttf.tables_hash["CBDT"] = ""
    fake_ttf.tables_hash["CBLC"] = ""
    fake_ttf.tables_hash["glyf"] = ""

    source = described_class.new(fake_ttf)
    expect(source.bitmap_mode).to eq(:mixed)
  end

  it "returns :none for a UFO source" do
    source = described_class.new(Fontisan::Ufo::Font.new)
    expect(source.bitmap_mode).to eq(:none)
  end
end
