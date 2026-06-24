# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/context"

RSpec.describe Fontisan::Audit::Context do
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:font) { Fontisan::FontLoader.load(ttf_path, mode: :full) }
  let(:options) { { ucd_version: "17.0.0" } }

  let(:context) do
    described_class.new(
      font: font,
      font_path: ttf_path,
      font_index: 0,
      num_fonts_in_source: 1,
      options: options,
    )
  end

  describe "accessors" do
    it "exposes constructor values" do
      expect(context.font).to eq(font)
      expect(context.font_path).to eq(ttf_path)
      expect(context.font_index).to eq(0)
      expect(context.num_fonts_in_source).to eq(1)
      expect(context.options).to eq(options)
    end
  end

  describe "#source_format" do
    it "returns the detected format string" do
      expect(context.source_format).to eq("ttf")
    end

    it "is memoized" do
      first = context.source_format
      expect(context.source_format).to equal(first)
    end
  end

  describe "#codepoints" do
    it "returns an array of integer codepoints" do
      expect(context.codepoints).to be_an(Array)
      expect(context.codepoints).to include(0x41) # U+0041 LATIN CAPITAL LETTER A
    end

    it "is memoized" do
      first = context.codepoints
      expect(context.codepoints).to equal(first)
    end
  end

  describe "#no_codepoints?" do
    it "returns false by default" do
      expect(context.no_codepoints?).to be false
    end

    it "returns true when :no_codepoints is set" do
      ctx = described_class.new(
        font: font, font_path: ttf_path, font_index: 0,
        num_fonts_in_source: 1, options: { no_codepoints: true }
      )
      expect(ctx.no_codepoints?).to be true
    end
  end

  describe "#ucd" do
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

    it "returns a hash with version and indices" do
      ucd = context.ucd
      expect(ucd[:version]).to eq("17.0.0")
      expect(ucd[:blocks_index]).not_to be_nil
      expect(ucd[:scripts_index]).not_to be_nil
      expect(ucd[:warning]).to be_nil
    end

    it "records a warning for an unknown version" do
      ctx = described_class.new(
        font: font, font_path: ttf_path, font_index: 0,
        num_fonts_in_source: 1, options: { ucd_version: "0.0.0-never" }
      )
      ucd = ctx.ucd
      expect(ucd[:version]).to be_nil
      expect(ucd[:blocks_index]).to be_nil
      expect(ucd[:warning]).to match(/UCD version rejected/)
    end
  end
end
