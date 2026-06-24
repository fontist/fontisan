# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cmap"

RSpec.describe Fontisan::Tables::Cmap do
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:otf_path) { font_fixture_path("SourceSans3", "SourceSans3-Regular.otf") }

  describe "#subtable_formats" do
    it "returns an array of format numbers from the TTF cmap" do
      font = Fontisan::FontLoader.load(ttf_path, mode: :full)
      cmap = font.table("cmap")
      formats = cmap.subtable_formats

      expect(formats).to be_an(Array)
      expect(formats).not_to be_empty
      expect(formats).to all(be_an(Integer))
      expect(formats).to eq(formats.sort.uniq)
    end

    it "includes format 4 for BMP coverage" do
      font = Fontisan::FontLoader.load(ttf_path, mode: :full)
      formats = font.table("cmap").subtable_formats
      expect(formats).to include(4)
    end

    it "works on OTF/CFF fonts" do
      font = Fontisan::FontLoader.load(otf_path, mode: :full)
      formats = font.table("cmap").subtable_formats
      expect(formats).to include(4)
    end
  end

  describe "subtable_formats and has_format_4_subtable? consistency" do
    it "agrees with has_format_4_subtable?" do
      font = Fontisan::FontLoader.load(ttf_path, mode: :full)
      cmap = font.table("cmap")
      expect(cmap.has_format_4_subtable?).to eq(cmap.subtable_formats.include?(4))
    end
  end
end
