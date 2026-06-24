# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/library_aggregator"
require "fontisan/models/audit"

RSpec.describe Fontisan::Audit::LibraryAggregator do
  let(:aggregator) { described_class.new }

  def report(overrides = {})
    Fontisan::Models::Audit::AuditReport.new(
      font_index: 0, num_fonts_in_source: 1,
      family_name: "NotoSans", postscript_name: "NotoSans-Regular",
      total_codepoints: 0, total_glyphs: 0,
      **overrides
    )
  end

  describe "#aggregate with empty input" do
    it "returns zeroed aggregate metrics" do
      result = aggregator.aggregate([])
      expect(result[:aggregate_metrics][:total_codepoints]).to eq(0)
      expect(result[:aggregate_metrics][:total_glyphs]).to eq(0)
    end

    it "returns empty rollup collections" do
      result = aggregator.aggregate([])
      expect(result[:script_coverage]).to eq([])
      expect(result[:duplicate_groups]).to eq([])
      expect(result[:license_distribution]).to eq({})
    end
  end

  describe "#aggregate with multiple reports" do
    let(:reports) do
      [
        report(
          source_file: "/lib/a.ttf", source_sha256: "sha-a",
          postscript_name: "A-Regular",
          total_codepoints: 100, total_glyphs: 110,
          unicode_scripts: %w[Latin Greek],
          licensing: Fontisan::Models::Audit::Licensing.new(
            license_url: "https://ofl.org",
          )
        ),
        report(
          source_file: "/lib/b.ttf", source_sha256: "sha-a",
          postscript_name: "B-Regular",
          total_codepoints: 50, total_glyphs: 60,
          unicode_scripts: %w[Latin Cyrillic],
          licensing: Fontisan::Models::Audit::Licensing.new(
            license_url: "https://ofl.org",
          )
        ),
        report(
          source_file: "/lib/c.ttf", source_sha256: "sha-c",
          postscript_name: "C-Bold",
          total_codepoints: 25, total_glyphs: 30,
          unicode_scripts: %w[LATIN] # case-insensitive grouping not required
        ),
      ]
    end

    it "sums codepoints and glyphs across reports" do
      metrics = aggregator.aggregate(reports)[:aggregate_metrics]
      expect(metrics[:total_codepoints]).to eq(175)
      expect(metrics[:total_glyphs]).to eq(200)
    end

    it "builds one ScriptCoverageRow per distinct script" do
      rows = aggregator.aggregate(reports)[:script_coverage]
      scripts = rows.map(&:script)
      expect(scripts).to eq(%w[Latin Cyrillic Greek LATIN]) # sorted by -count, then name
    end

    it "lists the faces covering each script, sorted and de-duplicated" do
      rows = aggregator.aggregate(reports)[:script_coverage]
      latin = rows.find { |r| r.script == "Latin" }
      expect(latin.face_count).to eq(2)
      expect(latin.faces).to eq(%w[A-Regular B-Regular])
    end

    it "groups files by sha256, keeping only size > 1 groups" do
      groups = aggregator.aggregate(reports)[:duplicate_groups]
      expect(groups.length).to eq(1)
      expect(groups.first.source_sha256).to eq("sha-a")
      expect(groups.first.files).to eq(["/lib/a.ttf", "/lib/b.ttf"])
    end

    it "counts faces per license_url, bucketing nil as (none)" do
      dist = aggregator.aggregate(reports)[:license_distribution]
      expect(dist["https://ofl.org"]).to eq(2)
      expect(dist["(none)"]).to eq(1)
    end
  end
end
