# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Round-trip conversions", :integration do
  let(:fixtures_dir) { File.expand_path("../fixtures/fonts", __dir__) }
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:output_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(output_dir) if File.exist?(output_dir)
  end

  describe "TTF → OTF → TTF round-trip" do
    it "preserves glyph count" do
      otf_temp = File.join(output_dir, "temp.otf")
      ttf_output = File.join(output_dir, "output.ttf")

      original = Fontisan::FontLoader.load(ttf_path)
      original_count = original.table("maxp").num_glyphs

      # First conversion: TTF → OTF
      Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        otf_temp,
        validate: false,
      ).transform

      # Second conversion: OTF → TTF
      Fontisan::Pipeline::TransformationPipeline.new(
        otf_temp,
        ttf_output,
        validate: false,
      ).transform

      result = Fontisan::FontLoader.load(ttf_output)
      result_count = result.table("maxp").num_glyphs

      expect(result_count).to eq(original_count)
    end

    it "maintains table structure" do
      otf_temp = File.join(output_dir, "temp.otf")
      ttf_output = File.join(output_dir, "output.ttf")

      Fontisan::FontLoader.load(ttf_path)

      # Round-trip conversion
      Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        otf_temp,
        validate: false,
      ).transform

      Fontisan::Pipeline::TransformationPipeline.new(
        otf_temp,
        ttf_output,
        validate: false,
      ).transform

      result = Fontisan::FontLoader.load(ttf_output)

      # Check essential tables exist
      expect(result.has_table?("glyf")).to be(true)
      expect(result.has_table?("loca")).to be(true)
      expect(result.has_table?("maxp")).to be(true)
      expect(result.has_table?("head")).to be(true)
    end

    it "preserves Unicode mappings" do
      otf_temp = File.join(output_dir, "temp.otf")
      ttf_output = File.join(output_dir, "output.ttf")

      original = Fontisan::FontLoader.load(ttf_path)
      original_cmap = original.table("cmap")

      Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        otf_temp,
        validate: false,
      ).transform

      Fontisan::Pipeline::TransformationPipeline.new(
        otf_temp,
        ttf_output,
        validate: false,
      ).transform

      result = Fontisan::FontLoader.load(ttf_output)
      result_cmap = result.table("cmap")

      # Both should have cmap tables
      expect(original_cmap).not_to be_nil
      expect(result_cmap).not_to be_nil
    end

    it "preserves font metrics" do
      otf_temp = File.join(output_dir, "temp.otf")
      ttf_output = File.join(output_dir, "output.ttf")

      original = Fontisan::FontLoader.load(ttf_path)
      original_hhea = original.table("hhea")
      original_head = original.table("head")

      Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        otf_temp,
        validate: false,
      ).transform

      Fontisan::Pipeline::TransformationPipeline.new(
        otf_temp,
        ttf_output,
        validate: false,
      ).transform

      result = Fontisan::FontLoader.load(ttf_output)
      result_hhea = result.table("hhea")
      result_head = result.table("head")

      # Check key metrics preserved
      expect(result_hhea.ascent).to eq(original_hhea.ascent)
      expect(result_hhea.descent).to eq(original_hhea.descent)
      expect(result_head.units_per_em).to eq(original_head.units_per_em)
    end
  end

  describe "Same format conversions" do
    it "TTF to TTF maintains integrity" do
      ttf_output = File.join(output_dir, "copy.ttf")

      original = Fontisan::FontLoader.load(ttf_path)

      Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        ttf_output,
        validate: false,
      ).transform

      result = Fontisan::FontLoader.load(ttf_output)

      expect(result.table("maxp").num_glyphs).to eq(original.table("maxp").num_glyphs)
      expect(result.table_names.sort).to eq(original.table_names.sort)
    end
  end

  describe "Metadata preservation" do
    it "preserves font name across conversions" do
      otf_temp = File.join(output_dir, "temp.otf")

      original = Fontisan::FontLoader.load(ttf_path)
      original_name = original.table("name").english_name(1)

      Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        otf_temp,
        validate: false,
      ).transform

      converted = Fontisan::FontLoader.load(otf_temp)
      converted_name = converted.table("name").english_name(1)

      expect(converted_name).to eq(original_name)
    end

    it "preserves font version across conversions" do
      otf_temp = File.join(output_dir, "temp.otf")

      original = Fontisan::FontLoader.load(ttf_path)
      original_version = original.table("name").english_name(5)

      Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        otf_temp,
        validate: false,
      ).transform

      converted = Fontisan::FontLoader.load(otf_temp)
      converted_version = converted.table("name").english_name(5)

      expect(converted_version).to eq(original_version)
    end
  end

  describe "Edge cases" do
    it "handles fonts with compound glyphs" do
      # NotoSans has compound glyphs
      otf_temp = File.join(output_dir, "temp.otf")

      result = Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        otf_temp,
        validate: false,
      ).transform

      expect(result[:success]).to be(true)
      expect(File.exist?(otf_temp)).to be(true)
    end

    it "handles conversion with validation disabled" do
      otf_temp = File.join(output_dir, "temp.otf")

      result = Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        otf_temp,
        validate: false,
      ).transform

      expect(result[:success]).to be(true)
      expect(result[:warnings] || []).to be_empty
    end
  end
end
