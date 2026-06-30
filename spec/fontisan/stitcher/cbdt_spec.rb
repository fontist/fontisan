# frozen_string_literal: true

require "spec_helper"
require "fontisan"
require "fontisan/stitcher"

RSpec.describe Fontisan::Stitcher::Source, "#bitmap_mode" do
  # Minimal double that responds to has_table? like SfntFont.
  let(:fake_ttf) do
    instance_double(Fontisan::SfntFont, has_table?: false)
  end

  it "returns :cbdt when both CBDT and CBLC are present" do
    allow(fake_ttf).to receive(:has_table?).with("CBDT").and_return(true)
    allow(fake_ttf).to receive(:has_table?).with("CBLC").and_return(true)
    allow(fake_ttf).to receive(:has_table?).with("glyf").and_return(false)
    allow(fake_ttf).to receive(:has_table?).with("CFF ").and_return(false)

    source = described_class.new(fake_ttf)
    expect(source.bitmap_mode).to eq(:cbdt)
  end

  it "returns :glyf when only glyf is present" do
    allow(fake_ttf).to receive(:has_table?).with("glyf").and_return(true)
    allow(fake_ttf).to receive(:has_table?).with("CFF ").and_return(false)
    allow(fake_ttf).to receive(:has_table?).with("CBDT").and_return(false)
    allow(fake_ttf).to receive(:has_table?).with("CBLC").and_return(false)

    source = described_class.new(fake_ttf)
    expect(source.bitmap_mode).to eq(:glyf)
  end

  it "returns :glyf when only CFF is present (OTF)" do
    allow(fake_ttf).to receive(:has_table?).with("CFF ").and_return(true)
    allow(fake_ttf).to receive(:has_table?).with("glyf").and_return(false)
    allow(fake_ttf).to receive(:has_table?).with("CBDT").and_return(false)
    allow(fake_ttf).to receive(:has_table?).with("CBLC").and_return(false)

    source = described_class.new(fake_ttf)
    expect(source.bitmap_mode).to eq(:glyf)
  end

  it "returns :mixed when both glyf and CBDT are present" do
    allow(fake_ttf).to receive(:has_table?).with("CBDT").and_return(true)
    allow(fake_ttf).to receive(:has_table?).with("CBLC").and_return(true)
    allow(fake_ttf).to receive(:has_table?).with("glyf").and_return(true)
    allow(fake_ttf).to receive(:has_table?).with("CFF ").and_return(false)

    source = described_class.new(fake_ttf)
    expect(source.bitmap_mode).to eq(:mixed)
  end

  it "returns :none for a UFO source" do
    source = described_class.new(Fontisan::Ufo::Font.new)
    expect(source.bitmap_mode).to eq(:none)
  end
end
