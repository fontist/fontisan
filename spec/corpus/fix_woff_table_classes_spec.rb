# frozen_string_literal: true

require_relative "support/corpus_paths"

RSpec.describe Fontisan::WoffFont do
  it "parses glyf and loca of a TrueType-flavoured WOFF" do
    font = Fontisan::FontLoader.load(CorpusPaths.path("source-sans-3-regular-ttf-woff"), mode: :full)

    expect(font.table("loca")).not_to be_nil
    expect(font.table("glyf")).not_to be_nil
  end

  it "parses the CFF table of a CFF-flavoured WOFF" do
    font = Fontisan::FontLoader.load(CorpusPaths.path("source-sans-3-regular-otf-woff"), mode: :full)

    expect(font.table("CFF ")).to be_a(Fontisan::Tables::Cff)
  end

  it "reports glyf outlines for the TrueType-flavoured WOFF through the facade" do
    outlines = Fontisan::Reference.read(CorpusPaths.path("source-sans-3-regular-ttf-woff"), mode: :full)
      .first["outlines"]

    expect(outlines).to include("kind" => "glyf")
    expect(outlines["count"]).to eq(2478)
  end
end
