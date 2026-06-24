# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/provenance"

RSpec.describe Fontisan::Audit::Extractors::Provenance do
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:font) { Fontisan::FontLoader.load(ttf_path, mode: :full) }

  let(:context) do
    Fontisan::Audit::Context.new(
      font: font,
      font_path: ttf_path,
      font_index: 0,
      num_fonts_in_source: 1,
      options: {},
    )
  end

  let(:fields) { described_class.new.extract(context) }

  it "includes generated_at as an ISO 8601 timestamp" do
    expect(fields[:generated_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
  end

  it "includes the current fontisan version" do
    expect(fields[:fontisan_version]).to eq(Fontisan::VERSION)
  end

  it "expands source_file to an absolute path" do
    expect(fields[:source_file]).to eq(File.expand_path(ttf_path))
  end

  it "computes a 64-character sha256 of the source file" do
    expect(fields[:source_sha256]).to match(/\A[0-9a-f]{64}\z/)
  end

  it "records source_format detected from magic bytes" do
    expect(fields[:source_format]).to eq("ttf")
  end

  it "passes through font_index and num_fonts_in_source" do
    expect(fields[:font_index]).to eq(0)
    expect(fields[:num_fonts_in_source]).to eq(1)
  end
end
