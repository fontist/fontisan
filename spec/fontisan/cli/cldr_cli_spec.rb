# frozen_string_literal: true

require "spec_helper"
require "fontisan/cli/cldr_cli"
require "fontisan/cldr/cache_manager"
require "fontisan/cldr/index_builder"
require "fontisan/cldr/config"
require "json"
require "tmpdir"

RSpec.describe Fontisan::CldrCli do
  let(:en_characters) do
    {
      "main" => { "en" => { "characters" => { "exemplarCharacters" => "[a-c]" } } },
    }
  end

  let(:version) { Fontisan::Cldr::Config.default_version }

  around do |example|
    Dir.mktmpdir do |dir|
      original_xdg = ENV["XDG_CONFIG_HOME"]
      ENV["XDG_CONFIG_HOME"] = dir
      example.run
    ensure
      ENV["XDG_CONFIG_HOME"] = original_xdg
    end
  end

  def populate_cache(ver)
    main = Fontisan::Cldr::CacheManager.characters_main_dir(ver)
    main.join("en").mkpath
    File.write(main.join("en", "characters.json"), JSON.dump(en_characters))
  end

  describe "list" do
    it "prints the known_versions from config" do
      known = Regexp.escape(Fontisan::Cldr::Config.default_version)
      expect { described_class.start(%w[list]) }
        .to output(/#{known}/).to_stdout
    end
  end

  describe "status" do
    it "prints the default version and cache root" do
      out = capture_stdout { described_class.start(%w[status]) }
      expect(out).to include("Default version:", "Cache root:",
                             "Cached versions:")
    end

    it "lists cached versions after a download" do
      populate_cache(version)
      out = capture_stdout { described_class.start(%w[status]) }
      expect(out).to include(version)
    end
  end

  describe "path" do
    it "prints the cache path for the default version" do
      out = capture_stdout { described_class.start(%w[path]) }
      expect(out).to include("cldr", version)
    end

    it "accepts an explicit version argument" do
      out = capture_stdout { described_class.start(%w[path 45.0.0]) }
      expect(out).to include("45.0.0")
    end
  end

  describe "download" do
    it "fails when the version is unknown" do
      expect { described_class.start(%w[download 0.0.0-never]) }
        .to raise_error(SystemExit)
    end

    it "builds the index when the JSON archive is already cached" do
      populate_cache(version)

      allow(Fontisan::Cldr::IndexBuilder).to receive(:build).and_call_original
      out = capture_stdout { described_class.start(["download", version]) }
      expect(Fontisan::Cldr::IndexBuilder).to have_received(:build).with(version)
      expect(out).to include("ready at:")
      expect(Fontisan::Cldr::CacheManager.languages_index_path(version)).to exist
    end

    it "does not rebuild the index if it already exists" do
      populate_cache(version)
      described_class.start(["download", version])
      original_mtime = Fontisan::Cldr::CacheManager.languages_index_path(version).mtime

      sleep 0.05
      described_class.start(["download", version])
      current_mtime = Fontisan::Cldr::CacheManager.languages_index_path(version).mtime
      expect(current_mtime).to eq(original_mtime)
    end
  end

  describe "remove" do
    it "removes a cached version" do
      populate_cache(version)
      described_class.start(["download", version])
      expect(Fontisan::Cldr::CacheManager.cached?(version)).to be true

      out = capture_stdout { described_class.start(["remove", version]) }
      expect(out).to include("Removed")
      expect(Fontisan::Cldr::CacheManager.cached?(version)).to be false
    end

    it "prints a no-op message when the version isn't cached" do
      out = capture_stderr { described_class.start(["remove", version]) }
      expect(out).to include("nothing to remove")
    end

    it "fails when the version is unknown" do
      expect { described_class.start(%w[remove 0.0.0-never]) }
        .to raise_error(SystemExit)
    end
  end

  def capture_stdout
    stream = StringIO.new
    original = $stdout
    $stdout = stream
    yield
    stream.string
  ensure
    $stdout = original
  end

  def capture_stderr
    stream = StringIO.new
    original = $stderr
    $stderr = stream
    yield
    stream.string
  ensure
    $stderr = original
  end
end
