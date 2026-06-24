# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/aggregations"
require "tmpdir"

RSpec.describe Fontisan::Audit::Extractors::Aggregations do
  let(:ucd_xml) do
    <<~XML
      <ucd>
        <char cp="0041" name="LATIN CAPITAL LETTER A" general-category="Lu" script="Latin" block="Basic Latin" age="1.1"/>
        <char cp="0042" name="LATIN CAPITAL LETTER B" general-category="Lu" script="Latin" block="Basic Latin" age="1.1"/>
        <char cp="0061" name="LATIN SMALL LETTER A" general-category="Ll" script="Latin" block="Basic Latin" age="1.1"/>
        <char first-cp="0080" last-cp="00FF" name="LATIN-1 SUPPLEMENT RANGE" general-category="So" script="Latin" block="Latin-1 Supplement" age="1.1"/>
        <char cp="0391" name="GREEK CAPITAL LETTER ALPHA" general-category="Lu" script="Greek" block="Greek and Coptic" age="1.1"/>
      </ucd>
    XML
  end
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:font) { Fontisan::FontLoader.load(ttf_path, mode: :full) }

  let(:context) do
    Fontisan::Audit::Context.new(
      font: font, font_path: ttf_path, font_index: 0,
      num_fonts_in_source: 1, options: { ucd_version: "17.0.0" }
    )
  end

  around do |example|
    Dir.mktmpdir do |dir|
      original_xdg = ENV["XDG_CONFIG_HOME"]
      ENV["XDG_CONFIG_HOME"] = dir
      version = "17.0.0"
      Fontisan::Ucd::CacheManager.ensure_version_dir!(version)
      File.write(Fontisan::Ucd::CacheManager.ucdxml_path(version), ucd_xml)
      Fontisan::Ucd::IndexBuilder.build(version)
      example.run
    ensure
      ENV["XDG_CONFIG_HOME"] = original_xdg
    end
  end

  it "returns aggregation fields keyed by AuditReport attribute names" do
    fields = described_class.new.extract(context)
    expect(fields.keys).to contain_exactly(
      :ucd_version, :blocks, :unicode_scripts,
      :opentype_scripts, :features
    )
  end

  it "reports the resolved UCD version" do
    fields = described_class.new.extract(context)
    expect(fields[:ucd_version]).to eq("17.0.0")
  end

  it "aggregates covered blocks" do
    fields = described_class.new.extract(context)
    expect(fields[:blocks]).to be_an(Array)
    expect(fields[:blocks].first).to be_a(Fontisan::Models::Audit::AuditBlock)
  end

  it "aggregates covered Unicode scripts" do
    fields = described_class.new.extract(context)
    expect(fields[:unicode_scripts]).to include("Latin")
  end

  it "exposes OpenType scripts as an array" do
    fields = described_class.new.extract(context)
    expect(fields[:opentype_scripts]).to be_an(Array)
  end

  it "exposes OpenType features as an array" do
    fields = described_class.new.extract(context)
    expect(fields[:features]).to be_an(Array)
  end

  context "when UCD version is unknown" do
    let(:context) do
      Fontisan::Audit::Context.new(
        font: font, font_path: ttf_path, font_index: 0,
        num_fonts_in_source: 1, options: { ucd_version: "0.0.0-never" }
      )
    end

    it "returns empty blocks and a nil ucd_version" do
      fields = described_class.new.extract(context)
      expect(fields[:ucd_version]).to be_nil
      expect(fields[:blocks]).to eq([])
    end
  end
end
