# frozen_string_literal: true

require "spec_helper"
require "fontisan/cldr/cache_manager"
require "tmpdir"

RSpec.describe Fontisan::Cldr::CacheManager do
  let(:version) { "46.0.0" }

  around do |example|
    Dir.mktmpdir do |dir|
      original_xdg = ENV["XDG_CONFIG_HOME"]
      ENV["XDG_CONFIG_HOME"] = dir
      example.run
    ensure
      ENV["XDG_CONFIG_HOME"] = original_xdg
    end
  end

  describe "path computation" do
    let(:root) { described_class.root }

    it "root honors XDG_CONFIG_HOME and nests under fontisan/cldr" do
      expected_xdg = ENV["XDG_CONFIG_HOME"]
      expect(described_class.root.to_s).to start_with(expected_xdg)
      expect(described_class.root.to_s).to include("fontisan", "cldr")
    end

    it "version_dir nests under root" do
      expect(described_class.version_dir(version).to_s)
        .to eq(File.join(root.to_s, version))
    end

    it "json_dir nests under <version>/json" do
      expect(described_class.json_dir(version).to_s)
        .to end_with(File.join(version, "json"))
    end

    it "characters_main_dir nests under the cldr-characters-full/main path" do
      expected_suffix = File.join(version, "json", "cldr-json",
                                  "cldr-characters-full", "main")
      expect(described_class.characters_main_dir(version).to_s)
        .to end_with(expected_suffix)
    end

    it "index_dir nests under <version>/index" do
      expect(described_class.index_dir(version).to_s)
        .to end_with(File.join(version, "index"))
    end

    it "languages_index_path is languages.yml inside index_dir" do
      path = described_class.languages_index_path(version)
      expect(path.basename.to_s).to eq("languages.yml")
      expect(path.dirname).to eq(described_class.index_dir(version))
    end
  end

  describe ".cached?" do
    it "returns false when characters_main_dir is absent" do
      expect(described_class.cached?(version)).to be false
    end

    it "returns true once characters_main_dir exists" do
      described_class.ensure_version_dir!(version)
      described_class.characters_main_dir(version).mkpath
      expect(described_class.cached?(version)).to be true
    end
  end

  describe ".cached_versions" do
    it "returns empty array for fresh cache" do
      expect(described_class.cached_versions).to eq([])
    end

    it "lists version directories sorted ascending" do
      described_class.ensure_version_dir!("45.0.0")
      described_class.ensure_version_dir!("46.0.0")

      expect(described_class.cached_versions).to eq(["45.0.0", "46.0.0"])
    end
  end

  describe ".ensure_version_dir! and .remove_version" do
    it "creates json/ and index/ subdirs" do
      described_class.ensure_version_dir!(version)
      expect(described_class.json_dir(version)).to exist
      expect(described_class.index_dir(version)).to exist
    end

    it "is idempotent" do
      described_class.ensure_version_dir!(version)
      expect { described_class.ensure_version_dir!(version) }.not_to raise_error
    end

    it "remove_version wipes the version dir" do
      described_class.ensure_version_dir!(version)
      expect(described_class.version_dir(version)).to exist

      described_class.remove_version(version)
      expect(described_class.version_dir(version)).not_to exist
    end

    it "remove_version is a no-op for absent versions" do
      expect { described_class.remove_version(version) }.not_to raise_error
    end
  end
end
