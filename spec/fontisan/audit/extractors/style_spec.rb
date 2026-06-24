# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/style"

RSpec.describe Fontisan::Audit::Extractors::Style do
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:otf_path) { font_fixture_path("SourceSans3", "SourceSans3-Regular.otf") }

  let(:ttf_context) do
    font = Fontisan::FontLoader.load(ttf_path, mode: :full)
    Fontisan::Audit::Context.new(
      font: font, font_path: ttf_path, font_index: 0,
      num_fonts_in_source: 1, options: {}
    )
  end

  let(:otf_context) do
    font = Fontisan::FontLoader.load(otf_path, mode: :full)
    Fontisan::Audit::Context.new(
      font: font, font_path: otf_path, font_index: 0,
      num_fonts_in_source: 1, options: {}
    )
  end

  it "returns style fields keyed by AuditReport attribute names" do
    fields = described_class.new.extract(ttf_context)
    expect(fields.keys).to contain_exactly(
      :weight_class, :width_class, :italic, :bold, :panose
    )
  end

  it "exposes weight_class as a positive integer" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:weight_class]).to be_an(Integer)
    expect(fields[:weight_class]).to be > 0
  end

  it "exposes panose as a 10-digit space-joined string" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:panose]).to match(/\A(\d+ ){9}\d+\z/)
  end

  it "works for OTF/CFF fonts" do
    fields = described_class.new.extract(otf_context)
    expect(fields[:weight_class]).to be_an(Integer)
    expect(fields[:panose]).to match(/\A(\d+ ){9}\d+\z/)
  end
end
