# frozen_string_literal: true

require_relative "support/corpus_paths"

RSpec.describe Fontisan::SfntFont do
  %w[fonttools-test-ttf fonttools-test-otf].each do |id|
    it "returns one table's bytes from table_data(tag) for #{id}" do
      font = Fontisan::FontLoader.load(CorpusPaths.path(id))

      expect(font.table_data("head")).to eq(font.table_data["head"])
      expect(font.table_data("head").bytesize).to eq(54)
      expect(font.table_data("ZZZZ")).to be_nil
    end
  end

  it "lets StaticFontBuilder read table bytes by tag" do
    font = Fontisan::FontLoader.load(CorpusPaths.path("source-sans-3-vf-upright-ttf"), mode: :full, lazy: false)

    expect { font.table_data("fvar") }.not_to raise_error
    expect(font.table_data("fvar")).to eq(font.table_data["fvar"])
  end
end
