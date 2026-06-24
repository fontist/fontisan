# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/color_capabilities"

RSpec.describe Fontisan::Audit::Extractors::ColorCapabilities do
  let(:ttf_path)    { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:emoji_path)  { font_fixture_path("TwemojiMozilla", "Twemoji.Mozilla.ttf") }

  let(:ttf_context) do
    font = Fontisan::FontLoader.load(ttf_path, mode: :full)
    Fontisan::Audit::Context.new(
      font: font, font_path: ttf_path, font_index: 0,
      num_fonts_in_source: 1, options: {}
    )
  end

  let(:emoji_context) do
    font = Fontisan::FontLoader.load(emoji_path, mode: :full)
    Fontisan::Audit::Context.new(
      font: font, font_path: emoji_path, font_index: 0,
      num_fonts_in_source: 1, options: {}
    )
  end

  it "returns a single :color_capabilities field" do
    fields = described_class.new.extract(ttf_context)
    expect(fields.keys).to contain_exactly(:color_capabilities)
  end

  it "returns a Models::Audit::ColorCapabilities instance" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:color_capabilities]).to be_a(Fontisan::Models::Audit::ColorCapabilities)
  end

  describe "non-color font (NotoSans)" do
    it "reports no color formats" do
      cap = described_class.new.extract(ttf_context)[:color_capabilities]
      expect(cap.has_colr).to be false
      expect(cap.has_cpal).to be false
      expect(cap.has_svg).to be false
      expect(cap.has_cbdt).to be false
      expect(cap.has_sbix).to be false
      expect(cap.color_formats).to eq([])
    end
  end

  describe "color font (TwemojiMozilla)" do
    it "reports at least one color format" do
      cap = described_class.new.extract(emoji_context)[:color_capabilities]
      expect(cap.color_formats).not_to eq([])
    end

    it "populates COLR fields when COLR table is present" do
      cap = described_class.new.extract(emoji_context)[:color_capabilities]
      skip "no COLR table on this fixture" unless cap.has_colr

      expect(cap.colr_version).to(satisfy { |v| [0, 1].include?(v) })
      expect(cap.colr_base_glyph_count).to be_an(Integer).and be >= 0
      expect(cap.colr_layer_count).to be_an(Integer).and be >= 0
    end

    it "populates strike count when CBDT/CBLC are present" do
      cap = described_class.new.extract(emoji_context)[:color_capabilities]
      skip "no CBDT/CBLC tables on this fixture" unless cap.has_cbdt && cap.has_cblc

      expect(cap.cbdt_strike_count).to be_an(Integer).and be_positive
    end
  end
end
