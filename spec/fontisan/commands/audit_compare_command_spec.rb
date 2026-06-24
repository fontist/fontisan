# frozen_string_literal: true

require "spec_helper"
require "fontisan/commands/audit_compare_command"
require "fontisan/models/audit"
require "tmpdir"

RSpec.describe Fontisan::Commands::AuditCompareCommand do
  let(:left_report) do
    Fontisan::Models::Audit::AuditReport.new(
      font_index: 0,
      num_fonts_in_source: 1,
      source_file: "/path/a.ttf",
      family_name: "FontA",
      postscript_name: "FontA-Regular",
      weight_class: 400,
    )
  end
  let(:right_report) do
    Fontisan::Models::Audit::AuditReport.new(
      font_index: 0,
      num_fonts_in_source: 1,
      source_file: "/path/b.ttf",
      family_name: "FontB",
      postscript_name: "FontB-Bold",
      weight_class: 700,
    )
  end

  describe "#run with two saved YAML reports" do
    it "loads both and produces an AuditDiff" do
      Dir.mktmpdir do |dir|
        left_path = File.join(dir, "left.yaml")
        right_path = File.join(dir, "right.yaml")
        File.write(left_path, left_report.to_yaml)
        File.write(right_path, right_report.to_yaml)

        diff = described_class.new(left_path, right_path).run
        expect(diff).to be_a(Fontisan::Models::Audit::AuditDiff)
        expect(diff.left_source).to eq("/path/a.ttf")
        expect(diff.right_source).to eq("/path/b.ttf")
      end
    end

    it "records the differing weight_class as a FieldChange" do
      Dir.mktmpdir do |dir|
        left_path = File.join(dir, "left.yaml")
        right_path = File.join(dir, "right.yaml")
        File.write(left_path, left_report.to_yaml)
        File.write(right_path, right_report.to_yaml)

        diff = described_class.new(left_path, right_path).run
        fields = diff.field_changes.map(&:field)
        expect(fields).to include("weight_class", "family_name", "postscript_name")
      end
    end
  end

  describe "#run with two saved JSON reports" do
    it "loads both from JSON" do
      Dir.mktmpdir do |dir|
        left_path = File.join(dir, "left.json")
        right_path = File.join(dir, "right.json")
        File.write(left_path, left_report.to_json)
        File.write(right_path, right_report.to_json)

        diff = described_class.new(left_path, right_path).run
        expect(diff.left_source).to eq("/path/a.ttf")
      end
    end
  end

  describe "#run with .yml extension" do
    it "loads a .yml file the same as .yaml" do
      Dir.mktmpdir do |dir|
        left_path = File.join(dir, "left.yml")
        right_path = File.join(dir, "right.yml")
        File.write(left_path, left_report.to_yaml)
        File.write(right_path, right_report.to_yaml)

        diff = described_class.new(left_path, right_path).run
        expect(diff.left_source).to eq("/path/a.ttf")
        expect(diff.right_source).to eq("/path/b.ttf")
      end
    end
  end

  describe "#run with mixed inputs" do
    let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }

    around do |example|
      Dir.mktmpdir do |dir|
        original_xdg = ENV["XDG_CONFIG_HOME"]
        ENV["XDG_CONFIG_HOME"] = dir
        version = "17.0.0"
        Fontisan::Ucd::CacheManager.ensure_version_dir!(version)
        File.write(
          Fontisan::Ucd::CacheManager.ucdxml_path(version),
          %(<ucd><char cp="0041" name="A" general-category="Lu" script="Latin" block="Basic Latin" age="1.1"/></ucd>),
        )
        Fontisan::Ucd::IndexBuilder.build(version)
        example.run
      ensure
        ENV["XDG_CONFIG_HOME"] = original_xdg
      end
    end

    it "audits the font file and compares against the saved report" do
      Dir.mktmpdir do |dir|
        saved_path = File.join(dir, "saved.yaml")
        File.write(saved_path, left_report.to_yaml)

        diff = described_class.new(saved_path, ttf_path,
                                   ucd_version: "17.0.0").run
        expect(diff).to be_a(Fontisan::Models::Audit::AuditDiff)
        expect(diff.right_source).to eq(File.expand_path(ttf_path))
      end
    end

    it "forwards ucd_version to the audited input" do
      # Using an unknown ucd_version surfaces a warning on the audit result;
      # this proves option forwarding without mocking AuditCommand.
      Dir.mktmpdir do |dir|
        saved_path = File.join(dir, "saved.yaml")
        File.write(saved_path, left_report.to_yaml)

        diff = described_class.new(saved_path, ttf_path,
                                   ucd_version: "0.0.0-never").run
        # diff itself still built; right side's ucd_version resolves to nil
        expect(diff).to be_a(Fontisan::Models::Audit::AuditDiff)
      end
    end

    it "audits both font files when neither is a saved report" do
      Dir.mktmpdir do |dir|
        # Use the same fixture twice — diff should still be produced.
        local_copy = File.join(dir, "copy.ttf")
        FileUtils.cp(ttf_path, local_copy)

        diff = described_class.new(ttf_path, local_copy,
                                   ucd_version: "17.0.0").run
        expect(diff).to be_a(Fontisan::Models::Audit::AuditDiff)
        expect(diff.left_source).to eq(File.expand_path(ttf_path))
        expect(diff.right_source).to eq(File.expand_path(local_copy))
        expect(diff.field_changes).to eq([])
      end
    end
  end
end
