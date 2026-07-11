# frozen_string_literal: true

require "spec_helper"
require "digest"
require "tmpdir"

RSpec.describe Fontisan::Commands::AuditCommand do
  let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }
  let(:otf_path) { "spec/fixtures/fonttools/TestOTF.otf" }

  describe "#run for a single font" do
    subject(:report) { described_class.new(font_path).run }

    it "is an AuditReport" do
      expect(report).to be_a(Fontisan::Models::AuditReport)
    end

    it "records the source file basename" do
      expect(report.source_file).to eq("TestTTF.ttf")
    end

    it "records the source format" do
      expect(report.source_format).to eq("ttf")
    end

    it "computes the SHA256 of the source file" do
      expected = Digest::SHA256.file(font_path).hexdigest
      expect(report.source_sha256).to eq(expected)
    end

    it "includes the fontisan version" do
      expect(report.fontisan_version).to eq(Fontisan::VERSION)
    end

    it "includes a generated_at timestamp" do
      expect(report.generated_at).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "has no font_index (single font)" do
      expect(report.font_index).to be_nil
    end

    it "reports num_fonts_in_source = 1" do
      expect(report.num_fonts_in_source).to eq(1)
    end

    it "extracts name-table identity fields" do
      expect(report.family_name).to be_a(String)
      expect(report.postscript_name).to be_a(String)
    end

    it "extracts OS/2 weight and width class" do
      expect(report.weight_class).to be_between(1, 1000)
      expect(report.width_class).to be_between(1, 9).or be_nil
    end

    it "has boolean italic and bold flags" do
      expect(report.italic).to satisfy("be boolean") { |v| [true, false].include?(v) }
      expect(report.bold).to satisfy("be boolean") { |v| [true, false].include?(v) }
    end

    it "is_variable is boolean" do
      expect(report.is_variable).to satisfy("be boolean") { |v| [true, false].include?(v) }
    end

    it "reports total glyphs and codepoints" do
      expect(report.total_glyphs).to be_positive
      expect(report.total_codepoints).to be_an(Integer)
    end

    it "includes the codepoint list by default" do
      expect(report.codepoints).to be_an(Array)
      expect(report.codepoints.first).to match(/^U\+[0-9A-F]+$/) if report.codepoints.any?
    end
  end

  describe "with include_codepoints: false" do
    subject(:report) do
      described_class.new(font_path, include_codepoints: false).run
    end

    it "omits the codepoint list" do
      expect(report.codepoints).to be_empty.or be_nil
    end
  end

  describe "OTF (CFF-based) font" do
    subject(:report) { described_class.new(otf_path).run }

    it "reports source_format = otf" do
      expect(report.source_format).to eq("otf")
    end

    it "extracts identity fields" do
      expect(report.family_name).to be_a(String)
      expect(report.total_glyphs).to be_positive
    end
  end

  describe "serialization" do
    subject(:report) { described_class.new(font_path).run }

    it "round-trips through YAML" do
      yaml = report.to_yaml
      restored = Fontisan::Models::AuditReport.from_yaml(yaml)
      expect(restored.family_name).to eq(report.family_name)
      expect(restored.source_sha256).to eq(report.source_sha256)
    end

    it "round-trips through JSON" do
      json = report.to_json
      restored = Fontisan::Models::AuditReport.from_json(json)
      expect(restored.family_name).to eq(report.family_name)
      expect(restored.total_glyphs).to eq(report.total_glyphs)
    end
  end
end
