# frozen_string_literal: true

require_relative "support/corpus_paths"

RSpec.describe "hinting check cvt lookup" do
  def issues(id)
    Fontisan::Reference.audit(CorpusPaths.path(id), validate: true).first.fetch("validation_issues")
  end

  it "does not report a missing cvt table for a font that has one" do
    tags = Fontisan::FontLoader.load(CorpusPaths.path("fonttools-test-ttf")).table_names
    expect(tags).to include("cvt ", "fpgm")

    expect(issues("fonttools-test-ttf").map { |i| i["location"] }).not_to include("tables.cvt")
  end

  it "still reports a missing cvt table when the font has fpgm but no cvt" do
    font = Fontisan::FontLoader.load(CorpusPaths.path("fonttools-test-ttf"), mode: :full, lazy: false)
    allow(font).to(receive(:has_table?).and_wrap_original { |m, tag| tag != "cvt " && m.call(tag) })

    found = Fontisan::Audit::Checks::HintingCheck.call(font)
    expect(found.map(&:location)).to include("tables.cvt")
  end
end
