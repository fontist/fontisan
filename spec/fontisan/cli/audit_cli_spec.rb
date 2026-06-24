# frozen_string_literal: true

require "spec_helper"
require "fontisan/cli"
require "fileutils"
require "tmpdir"

RSpec.describe "fontisan audit CLI dispatch" do
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }

  # Minimal UCD stub so AuditCommand resolves a ucd_version and doesn't
  # try to download the real UCD bundle.
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

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

  describe "library mode" do
    it "produces a LibrarySummary when --summary is passed against a directory" do
      Dir.mktmpdir do |dir|
        FileUtils.cp(ttf_path, File.join(dir, "a.ttf"))
        output = capture_stdout do
          Fontisan::Cli.start(["audit", dir, "--summary",
                               "--ucd-version", "17.0.0", "--format", "yaml"])
        end
        expect(output).to include("root_path:")
        expect(output).to include("total_files: 1")
      end
    end

    it "walks subdirectories when --recursive is passed" do
      Dir.mktmpdir do |dir|
        FileUtils.cp(ttf_path, File.join(dir, "a.ttf"))
        sub = File.join(dir, "deep")
        FileUtils.mkdir_p(sub)
        FileUtils.cp(ttf_path, File.join(sub, "b.ttf"))
        output = capture_stdout do
          Fontisan::Cli.start(["audit", dir, "--recursive",
                               "--ucd-version", "17.0.0", "--format", "yaml"])
        end
        expect(output).to include("total_files: 2")
      end
    end

    it "stays in single-file mode without --recursive/--summary" do
      # A directory without --recursive/--summary is rejected because
      # AuditCommand expects a font file, not a directory. The CLI
      # surfaces this as SystemExit via handle_error → exit(1).
      expect do
        Fontisan::Cli.start(["audit", "/tmp", "--format", "yaml"])
      end.to raise_error(SystemExit)
    end
  end

  describe "compare mode" do
    it "errors when --compare is given fewer than two paths" do
      expect do
        Fontisan::Cli.start(["audit", "--compare", "--format", "yaml"])
      end.to raise_error(SystemExit)
    end
  end

  describe "argument validation" do
    it "errors when no path is given" do
      expect do
        Fontisan::Cli.start(["audit", "--format", "yaml"])
      end.to raise_error(SystemExit)
    end
  end

  describe "--brief" do
    it "produces a report that omits metrics, hinting, layout, and aggregation" do
      Dir.mktmpdir do |dir|
        FileUtils.cp(ttf_path, File.join(dir, "a.ttf"))
        output = capture_stdout do
          Fontisan::Cli.start(["audit", File.join(dir, "a.ttf"),
                               "--brief", "--format", "yaml"])
        end
        # Brief skips the expensive extractors. Verify the resulting report
        # has no metrics/blocks/etc fields populated.
        expect(output).to include("family_name:")
        expect(output).not_to include("metrics:")
        expect(output).not_to include("hinting:")
        expect(output).not_to include("opentype_layout:")
      end
    end
  end
end
