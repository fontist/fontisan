# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/coverage"

RSpec.describe Fontisan::Audit::Extractors::Coverage do
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:font) { Fontisan::FontLoader.load(ttf_path, mode: :full) }

  let(:default_context) do
    Fontisan::Audit::Context.new(
      font: font, font_path: ttf_path, font_index: 0,
      num_fonts_in_source: 1, options: {}
    )
  end

  let(:no_cps_context) do
    Fontisan::Audit::Context.new(
      font: font, font_path: ttf_path, font_index: 0,
      num_fonts_in_source: 1, options: { no_codepoints: true }
    )
  end

  it "returns coverage fields keyed by AuditReport attribute names" do
    fields = described_class.new.extract(default_context)
    expect(fields.keys).to contain_exactly(
      :total_codepoints, :total_glyphs, :cmap_subtables, :codepoints
    )
  end

  it "reports a positive total_codepoints count" do
    fields = described_class.new.extract(default_context)
    expect(fields[:total_codepoints]).to be > 0
  end

  it "reports a positive total_glyphs count" do
    fields = described_class.new.extract(default_context)
    expect(fields[:total_glyphs]).to be > 0
  end

  it "exposes cmap_subtables as a non-empty array" do
    fields = described_class.new.extract(default_context)
    expect(fields[:cmap_subtables]).to be_an(Array)
    expect(fields[:cmap_subtables]).not_to be_empty
  end

  it "formats each codepoint as U+XXXX by default" do
    fields = described_class.new.extract(default_context)
    expect(fields[:codepoints].first).to match(/\AU\+[0-9A-F]{4,6}\z/)
    expect(fields[:codepoints].length).to eq(fields[:total_codepoints])
  end

  it "returns an empty codepoints list when :no_codepoints is set" do
    fields = described_class.new.extract(no_cps_context)
    expect(fields[:codepoints]).to eq([])
    expect(fields[:total_codepoints]).to be > 0
  end
end
