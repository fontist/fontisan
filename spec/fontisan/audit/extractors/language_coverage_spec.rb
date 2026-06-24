# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/language_coverage"
require "fontisan/audit/context"
require "fontisan/cldr/index"
require "tmpdir"

RSpec.describe Fontisan::Audit::Extractors::LanguageCoverage do
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:font) { Fontisan::FontLoader.load(ttf_path, mode: :full) }

  let(:en_characters) do
    {
      "main" => { "en" => { "characters" => { "exemplarCharacters" => "[a-c]" } } },
    }
  end

  let(:fr_characters) do
    {
      "main" => { "fr" => { "characters" => { "exemplarCharacters" => "[a-zé]" } } },
    }
  end

  let(:version) { Fontisan::Cldr::Config.default_version }

  def populate_cldr_cache(ver)
    main = Fontisan::Cldr::CacheManager.characters_main_dir(ver)
    main.join("en").mkpath
    File.write(main.join("en", "characters.json"), JSON.dump(en_characters))
    main.join("fr").mkpath
    File.write(main.join("fr", "characters.json"), JSON.dump(fr_characters))
    Fontisan::Cldr::IndexBuilder.build(ver)
  end

  around do |example|
    Dir.mktmpdir do |dir|
      original_xdg = ENV["XDG_CONFIG_HOME"]
      ENV["XDG_CONFIG_HOME"] = dir
      populate_cldr_cache(version)
      example.run
    ensure
      ENV["XDG_CONFIG_HOME"] = original_xdg
    end
  end

  describe "when --with-language-coverage is not set" do
    let(:context) do
      Fontisan::Audit::Context.new(
        font: font, font_path: ttf_path, font_index: 0,
        num_fonts_in_source: 1, options: {}
      )
    end

    it "returns empty language_coverage and nil cldr_version" do
      fields = described_class.new.extract(context)
      expect(fields[:language_coverage]).to eq([])
      expect(fields[:cldr_version]).to be_nil
    end

    it "does not touch the CLDR cache" do
      # cldr is memoized but never requested — accessing it returns nil.
      expect(context.cldr).to be_nil
    end
  end

  describe "when --with-language-coverage is set" do
    let(:context) do
      Fontisan::Audit::Context.new(
        font: font, font_path: ttf_path, font_index: 0,
        num_fonts_in_source: 1,
        options: { with_language_coverage: true, cldr_version: version }
      )
    end

    it "returns the resolved CLDR version" do
      fields = described_class.new.extract(context)
      expect(fields[:cldr_version]).to eq(version)
    end

    it "returns one LanguageCoverage model per language in the index" do
      fields = described_class.new.extract(context)
      expect(fields[:language_coverage]).to be_an(Array)
      expect(fields[:language_coverage]).to all(
        be_a(Fontisan::Models::Cldr::LanguageCoverage),
      )
      langs = fields[:language_coverage].map(&:language)
      expect(langs).to contain_exactly("en", "fr")
    end

    it "reports coverage % consistent with the font's cmap" do
      fields = described_class.new.extract(context)
      en = fields[:language_coverage].find { |lc| lc.language == "en" }
      # English exemplar set is [a-c]; NotoSans-Regular contains all three.
      expect(en.total).to eq(3)
      expect(en.covered).to eq(3)
      expect(en.coverage_ratio).to eq(1.0)
      expect(en.fully_supported).to be true
    end
  end

  describe "when CLDR version is unknown" do
    let(:context) do
      Fontisan::Audit::Context.new(
        font: font, font_path: ttf_path, font_index: 0,
        num_fonts_in_source: 1,
        options: { with_language_coverage: true, cldr_version: "0.0.0-never" }
      )
    end

    it "emits an empty array and the version resolves to nil" do
      fields = described_class.new.extract(context)
      expect(fields[:language_coverage]).to eq([])
      expect(fields[:cldr_version]).to be_nil
    end

    it "surfaces a warning on the cldr context" do
      expect(context.cldr[:warning]).to match(/CLDR version rejected/)
    end
  end

  describe "when the font has no cmap codepoints" do
    let(:empty_context) do
      Struct.new(:codepoints, :cldr).new(
        [],
        { version: version,
          index: Fontisan::Cldr::Index.new("en" => Set.new([97, 98, 99])),
          warning: nil },
      )
    end

    it "still emits one LanguageCoverage per language with zero coverage" do
      fields = described_class.new.extract(empty_context)
      en = fields[:language_coverage].find { |lc| lc.language == "en" }
      expect(en.covered).to eq(0)
      expect(en.coverage_ratio).to eq(0.0)
      expect(en.fully_supported).to be false
    end
  end
end
