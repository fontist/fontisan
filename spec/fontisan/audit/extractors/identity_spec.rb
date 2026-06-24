# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/identity"

RSpec.describe Fontisan::Audit::Extractors::Identity do
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

  it "returns identity fields keyed by AuditReport attribute names" do
    fields = described_class.new.extract(ttf_context)
    expect(fields.keys).to contain_exactly(
      :family_name, :subfamily_name, :full_name,
      :postscript_name, :version, :font_revision
    )
  end

  it "populates family_name from the name table" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:family_name]).to eq("Noto Sans")
  end

  it "populates postscript_name from the name table" do
    fields = described_class.new.extract(ttf_context)
    expect(fields[:postscript_name]).to match(/NotoSans/)
  end

  it "works for OTF/CFF fonts" do
    fields = described_class.new.extract(otf_context)
    expect(fields[:family_name]).to eq("Source Sans 3")
    expect(fields[:postscript_name]).to match(/SourceSans3/)
  end

  it "exposes font_revision as a float or nil" do
    fields = described_class.new.extract(ttf_context)
    expect([Float, NilClass]).to include(fields[:font_revision].class)
  end
end
