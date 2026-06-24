# frozen_string_literal: true

require "spec_helper"
require "fontisan/commands/audit_library_command"
require "fontisan/models/audit"
require "fileutils"
require "tmpdir"

RSpec.describe Fontisan::Commands::AuditLibraryCommand do
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

  describe "#run with a valid directory" do
    it "returns a LibrarySummary" do
      Dir.mktmpdir do |dir|
        FileUtils.cp(ttf_path, File.join(dir, "a.ttf"))
        cmd = described_class.new(dir, recursive: false,
                                       options: { ucd_version: "17.0.0" })
        summary = cmd.run
        expect(summary).to be_a(Fontisan::Models::Audit::LibrarySummary)
        expect(summary.total_files).to eq(1)
      end
    end

    it "walks subdirectories when recursive: true" do
      Dir.mktmpdir do |dir|
        FileUtils.cp(ttf_path, File.join(dir, "a.ttf"))
        sub = File.join(dir, "deep")
        FileUtils.mkdir_p(sub)
        FileUtils.cp(ttf_path, File.join(sub, "b.ttf"))

        cmd = described_class.new(dir, recursive: true,
                                       options: { ucd_version: "17.0.0" })
        summary = cmd.run
        expect(summary.total_files).to eq(2)
      end
    end

    it "exposes the skipped list from the underlying auditor" do
      Dir.mktmpdir do |dir|
        FileUtils.cp(ttf_path, File.join(dir, "good.ttf"))
        File.write(File.join(dir, "bad.ttf"), "not a font")
        cmd = described_class.new(dir, recursive: false,
                                       options: { ucd_version: "17.0.0" })
        cmd.run
        expect(cmd.skipped.length).to eq(1)
      end
    end
  end

  describe "#run with a missing directory" do
    it "raises Fontisan::Error" do
      cmd = described_class.new("/does/not/exist", recursive: false, options: {})
      expect { cmd.run }.to raise_error(Fontisan::Error, /existing directory/)
    end
  end

  describe "#run with a file path instead of a directory" do
    it "raises Fontisan::Error" do
      cmd = described_class.new(ttf_path, recursive: false, options: {})
      expect { cmd.run }.to raise_error(Fontisan::Error, /existing directory/)
    end
  end
end
