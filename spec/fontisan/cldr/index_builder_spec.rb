# frozen_string_literal: true

require "spec_helper"
require "fontisan/cldr/index_builder"
require "fontisan/cldr/cache_manager"
require "json"
require "tmpdir"

RSpec.describe Fontisan::Cldr::IndexBuilder do
  describe ".build_from_exemplars" do
    it "returns an Index parsed from exemplar strings" do
      index = described_class.build_from_exemplars(
        "en" => "[a-z]",
        "fr" => "[a-zé]",
      )

      expect(index).to be_a(Fontisan::Cldr::Index)
      expect(index.languages).to eq(%w[en fr])
      expect(index.lookup("en").size).to eq(26)
      expect(index.lookup("fr")).to include(233)
    end

    it "skips nil entries (treats as empty set)" do
      index = described_class.build_from_exemplars(
        "en" => "[abc]",
        "xx" => nil,
      )
      expect(index.lookup("en").size).to eq(3)
      expect(index.lookup("xx")).to eq(Set.new)
    end

    it "deduplicates codepoints across overlapping exemplars" do
      index = described_class.build_from_exemplars("en" => "[a-cb-d]")
      expect(index.lookup("en").sort).to eq([97, 98, 99, 100])
    end
  end

  describe ".build from a cached CLDR JSON tree" do
    let(:en_characters) do
      {
        "main" => {
          "en" => {
            "characters" => {
              "exemplarCharacters" => "[a-b c]",
              "auxiliary" => "[d]",
            },
          },
        },
      }
    end

    let(:fr_characters) do
      {
        "main" => {
          "fr" => {
            "characters" => {
              "exemplarCharacters" => "[a é]",
            },
          },
        },
      }
    end

    let(:version) { "46.0.0" }

    around do |example|
      Dir.mktmpdir do |dir|
        original_xdg = ENV["XDG_CONFIG_HOME"]
        ENV["XDG_CONFIG_HOME"] = dir

        main = Fontisan::Cldr::CacheManager.characters_main_dir(version)
        main.join("en").mkpath
        main.join("fr").mkpath
        File.write(main.join("en", "characters.json"), JSON.dump(en_characters))
        File.write(main.join("fr", "characters.json"), JSON.dump(fr_characters))

        example.run
      ensure
        ENV["XDG_CONFIG_HOME"] = original_xdg
      end
    end

    it "walks every language dir and builds a union of exemplar sets" do
      index = described_class.build(version)

      expect(index.languages).to contain_exactly("en", "fr")
      expect(index.lookup("en")).to include(97, 98, 99, 100)
      expect(index.lookup("fr")).to include(97, 233)
    end

    it "persists the index as languages.yml in the cache" do
      described_class.build(version)
      path = Fontisan::Cldr::CacheManager.languages_index_path(version)
      expect(path).to exist

      loaded = Fontisan::Cldr::Index.load(path)
      expect(loaded.lookup("en")).to include(100)
    end

    it "returns an empty Index when no characters dir exists" do
      Fontisan::Cldr::CacheManager.remove_version(version)
      Fontisan::Cldr::CacheManager.ensure_version_dir!(version)

      index = described_class.build(version)
      expect(index.languages).to eq([])
    end

    it "skips language files whose exemplar sets are unsupported syntax" do
      main = Fontisan::Cldr::CacheManager.characters_main_dir(version)
      main.join("ko").mkpath
      File.write(
        main.join("ko", "characters.json"),
        JSON.dump(
          "main" => {
            "ko" => {
              "characters" => { "exemplarCharacters" => "[:Hangul:]" },
            },
          },
        ),
      )

      index = described_class.build(version)
      expect(index.lookup("ko")).to eq(Set.new)
    end
  end
end
