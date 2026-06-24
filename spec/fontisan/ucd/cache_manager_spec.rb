# frozen_string_literal: true

require "spec_helper"
require "fontisan/ucd/cache_manager"
require "tmpdir"

RSpec.describe Fontisan::Ucd::CacheManager do
  describe "path computation" do
    around do |example|
      Dir.mktmpdir do |dir|
        original_xdg = ENV["XDG_CONFIG_HOME"]
        ENV["XDG_CONFIG_HOME"] = dir
        example.run
      ensure
        ENV["XDG_CONFIG_HOME"] = original_xdg
      end
    end

    let(:root) { described_class.root }
    let(:version) { "17.0.0" }

    it "root honors XDG_CONFIG_HOME" do
      expected_xdg = ENV["XDG_CONFIG_HOME"]
      expect(described_class.root.to_s).to start_with(expected_xdg)
      expect(described_class.root.to_s).to include("fontisan", "unicode")
    end

    it "version_dir nests under root" do
      expect(described_class.version_dir(version).to_s)
        .to eq(File.join(root.to_s, version))
    end

    it "ucdxml_path nests under ucdxml/" do
      expect(described_class.ucdxml_path(version).to_s)
        .to end_with(File.join(version, "ucdxml", "ucd.all.flat.xml"))
    end

    it "index_dir nests under index/" do
      expect(described_class.index_dir(version).to_s)
        .to end_with(File.join(version, "index"))
    end

    it "blocks/scripts index paths are in index_dir" do
      blocks = described_class.blocks_index_path(version)
      scripts = described_class.scripts_index_path(version)
      expect(blocks.basename.to_s).to eq("blocks.yml")
      expect(scripts.basename.to_s).to eq("scripts.yml")
      expect(blocks.dirname).to eq(described_class.index_dir(version))
    end
  end

  describe ".cached?" do
    around do |example|
      Dir.mktmpdir do |dir|
        original_xdg = ENV["XDG_CONFIG_HOME"]
        ENV["XDG_CONFIG_HOME"] = dir
        example.run
      ensure
        ENV["XDG_CONFIG_HOME"] = original_xdg
      end
    end

    it "returns false when ucdxml is absent" do
      expect(described_class.cached?("17.0.0")).to be false
    end

    it "returns true once ucdxml file is present" do
      version = "17.0.0"
      described_class.ensure_version_dir!(version)
      FileUtils.touch(described_class.ucdxml_path(version))
      expect(described_class.cached?(version)).to be true
    end
  end

  describe ".cached_versions" do
    around do |example|
      Dir.mktmpdir do |dir|
        original_xdg = ENV["XDG_CONFIG_HOME"]
        ENV["XDG_CONFIG_HOME"] = dir
        example.run
      ensure
        ENV["XDG_CONFIG_HOME"] = original_xdg
      end
    end

    it "returns empty array for fresh cache" do
      expect(described_class.cached_versions).to eq([])
    end

    it "lists version directories sorted ascending" do
      described_class.ensure_version_dir!("16.0.0")
      described_class.ensure_version_dir!("17.0.0")

      expect(described_class.cached_versions).to eq(["16.0.0", "17.0.0"])
    end
  end

  describe ".ensure_version_dir! and .remove_version" do
    around do |example|
      Dir.mktmpdir do |dir|
        original_xdg = ENV["XDG_CONFIG_HOME"]
        ENV["XDG_CONFIG_HOME"] = dir
        example.run
      ensure
        ENV["XDG_CONFIG_HOME"] = original_xdg
      end
    end

    it "creates ucdxml/ and index/ subdirs" do
      described_class.ensure_version_dir!("17.0.0")
      expect(described_class.ucdxml_path("17.0.0").dirname).to exist
      expect(described_class.index_dir("17.0.0")).to exist
    end

    it "remove_version wipes the version dir" do
      described_class.ensure_version_dir!("17.0.0")
      expect(described_class.version_dir("17.0.0")).to exist

      described_class.remove_version("17.0.0")
      expect(described_class.version_dir("17.0.0")).not_to exist
    end
  end
end
