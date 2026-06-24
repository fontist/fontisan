# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/library_auditor"
require "fontisan/models/audit"
require "fileutils"
require "tmpdir"

RSpec.describe Fontisan::Audit::LibraryAuditor do
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:ttc_path) { font_fixture_path("DinaRemasterII", "DinaRemasterII.ttc") }

  # Minimal UCD stub: just enough for AuditCommand to resolve a ucd_version
  # and populate unicode_scripts on each face. Without this the aggregator
  # would see empty script lists.
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

  def stage_fonts(dir, layout:)
    case layout
    when :flat
      FileUtils.cp(ttf_path, File.join(dir, "a.ttf"))
      FileUtils.cp(ttc_path, File.join(dir, "b.ttc"))
    when :nested
      FileUtils.cp(ttf_path, File.join(dir, "a.ttf"))
      sub = File.join(dir, "sub")
      FileUtils.mkdir_p(sub)
      FileUtils.cp(ttf_path, File.join(sub, "c.ttf"))
    when :duplicates
      FileUtils.cp(ttf_path, File.join(dir, "a.ttf"))
      FileUtils.cp(ttf_path, File.join(dir, "b.ttf"))
    end
  end

  describe "#audit with a flat directory" do
    it "discovers all font files non-recursively" do
      Dir.mktmpdir do |dir|
        stage_fonts(dir, layout: :flat)
        summary = described_class.new(dir, recursive: false,
                                           options: { ucd_version: "17.0.0" }).audit
        expect(summary.total_files).to eq(2)
        expect(summary.scanned_extensions).to eq(%w[.ttc .ttf])
      end
    end

    it "counts faces from TTCs as additional faces" do
      Dir.mktmpdir do |dir|
        stage_fonts(dir, layout: :flat)
        summary = described_class.new(dir, recursive: false,
                                           options: { ucd_version: "17.0.0" }).audit
        # 1 face from a.ttf + N faces from b.ttc
        expect(summary.total_faces).to be > summary.total_files
      end
    end

    it "exposes a per-face report for every face in the library" do
      Dir.mktmpdir do |dir|
        stage_fonts(dir, layout: :flat)
        summary = described_class.new(dir, recursive: false,
                                           options: { ucd_version: "17.0.0" }).audit
        expect(summary.per_face_reports.length).to eq(summary.total_faces)
        expect(summary.per_face_reports.first).to be_a(Fontisan::Models::Audit::AuditReport)
      end
    end

    it "records total_size_bytes summed across source files" do
      Dir.mktmpdir do |dir|
        stage_fonts(dir, layout: :flat)
        summary = described_class.new(dir, recursive: false,
                                           options: { ucd_version: "17.0.0" }).audit
        expect(summary.aggregate_metrics[:total_size_bytes]).to eq(
          File.size(ttf_path) + File.size(ttc_path),
        )
      end
    end
  end

  describe "#audit with --recursive" do
    it "walks into subdirectories when recursive: true" do
      Dir.mktmpdir do |dir|
        stage_fonts(dir, layout: :nested)
        recursive = described_class.new(dir, recursive: true,
                                             options: { ucd_version: "17.0.0" }).audit
        flat = described_class.new(dir, recursive: false,
                                        options: { ucd_version: "17.0.0" }).audit
        expect(recursive.total_files).to eq(2)
        expect(flat.total_files).to eq(1)
      end
    end
  end

  describe "#audit with byte-identical duplicates" do
    it "groups same-sha256 files into a DuplicateGroup" do
      Dir.mktmpdir do |dir|
        stage_fonts(dir, layout: :duplicates)
        summary = described_class.new(dir, recursive: false,
                                           options: { ucd_version: "17.0.0" }).audit
        expect(summary.duplicate_groups.length).to eq(1)
        group = summary.duplicate_groups.first
        expect(group.files.length).to eq(2)
      end
    end
  end

  describe "#audit with an empty directory" do
    it "produces a zeroed summary without raising" do
      Dir.mktmpdir do |dir|
        summary = described_class.new(dir, recursive: false,
                                           options: {}).audit
        expect(summary.total_files).to eq(0)
        expect(summary.total_faces).to eq(0)
        expect(summary.duplicate_groups).to eq([])
        expect(summary.script_coverage).to eq([])
        expect(summary.aggregate_metrics[:total_codepoints]).to eq(0)
      end
    end
  end

  describe "#skipped" do
    it "stays empty on a successful pass" do
      Dir.mktmpdir do |dir|
        stage_fonts(dir, layout: :flat)
        auditor = described_class.new(dir, recursive: false,
                                           options: { ucd_version: "17.0.0" })
        auditor.audit
        expect(auditor.skipped).to eq([])
      end
    end

    it "records a message when a font fails to audit" do
      Dir.mktmpdir do |dir|
        FileUtils.cp(ttf_path, File.join(dir, "good.ttf"))
        # Junk file with a font extension — AuditCommand will fail to load.
        File.write(File.join(dir, "bad.ttf"), "not a font")
        auditor = described_class.new(dir, recursive: false,
                                           options: { ucd_version: "17.0.0" })
        summary = auditor.audit
        expect(auditor.skipped.length).to eq(1)
        expect(summary.total_files).to eq(2)
        expect(summary.total_faces).to eq(1) # only good.ttf produced a face
      end
    end
  end
end
