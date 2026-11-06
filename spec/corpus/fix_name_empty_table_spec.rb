# frozen_string_literal: true

require_relative "support/corpus_paths"

RSpec.describe Fontisan::Tables::Name do
  let(:path) { CorpusPaths.path("quirk-empty-name-table") }

  it "audits a font whose name table has no records" do
    reports = Fontisan::Reference.audit(path)

    expect(reports.size).to eq(1)
    expect(reports.first["family_name"]).to be_nil
  end

  it "answers nil for an English name instead of raising" do
    font = Fontisan::FontLoader.load(path, mode: :full, lazy: false)

    expect(font.table("name").english_name(1)).to be_nil
  end
end
