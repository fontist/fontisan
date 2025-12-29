# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Basic format conversions", :integration do
  let(:fixtures_dir) { File.expand_path("../fixtures/fonts", __dir__) }
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:variable_ttf) do
    font_fixture_path("MonaSans",
                      "fonts/variable/MonaSansVF[wdth,wght,opsz,ital].ttf")
  end
  let(:output_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(output_dir) if File.exist?(output_dir)
  end

  describe "TTF to OTF conversion" do
    it "produces valid OTF with CFF table" do
      output_path = File.join(output_dir, "output.otf")
      pipeline = Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        output_path,
        validate: false,
      )

      result = pipeline.transform

      expect(result[:success]).to be(true)
      expect(File.exist?(output_path)).to be(true)

      # Verify OTF structure
      font = Fontisan::FontLoader.load(output_path)
      expect(font).to be_a(Fontisan::OpenTypeFont)
      expect(font.has_table?("CFF ")).to be(true)
      expect(font.has_table?("glyf")).to be(false)
    end

    it "preserves glyph count" do
      output_path = File.join(output_dir, "output.otf")

      original = Fontisan::FontLoader.load(ttf_path)
      original_glyph_count = original.table("maxp").num_glyphs

      pipeline = Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        output_path,
        validate: false,
      )
      pipeline.transform

      converted = Fontisan::FontLoader.load(output_path)
      converted_glyph_count = converted.table("maxp").num_glyphs

      expect(converted_glyph_count).to eq(original_glyph_count)
    end

    it "preserves font metadata" do
      output_path = File.join(output_dir, "output.otf")

      original = Fontisan::FontLoader.load(ttf_path)
      original_name = original.table("name")

      pipeline = Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        output_path,
        validate: false,
      )
      pipeline.transform

      converted = Fontisan::FontLoader.load(output_path)
      converted_name = converted.table("name")

      expect(converted_name.english_name(1)).to eq(original_name.english_name(1))
      expect(converted_name.english_name(2)).to eq(original_name.english_name(2))
    end
  end

  describe "OTF to TTF conversion" do
    let(:otf_path) do
      font_fixture_path("MonaSans",
                        "fonts/static/otf/MonaSansCondensed-ExtraBoldItalic.otf")
    end

    it "produces valid TTF with glyf table" do
      output_path = File.join(output_dir, "output.ttf")
      pipeline = Fontisan::Pipeline::TransformationPipeline.new(
        otf_path,
        output_path,
        validate: false,
      )

      result = pipeline.transform

      expect(result[:success]).to be(true)
      expect(File.exist?(output_path)).to be(true)

      # Verify TTF structure
      font = Fontisan::FontLoader.load(output_path)
      expect(font).to be_a(Fontisan::TrueTypeFont)
      expect(font.has_table?("glyf")).to be(true)
      expect(font.has_table?("CFF ")).to be(false)
    end

    it "preserves glyph count" do
      output_path = File.join(output_dir, "output.ttf")

      original = Fontisan::FontLoader.load(otf_path)
      original_glyph_count = original.table("maxp").num_glyphs

      pipeline = Fontisan::Pipeline::TransformationPipeline.new(
        otf_path,
        output_path,
        validate: false,
      )
      pipeline.transform

      converted = Fontisan::FontLoader.load(output_path)
      converted_glyph_count = converted.table("maxp").num_glyphs

      expect(converted_glyph_count).to eq(original_glyph_count)
    end
  end

  describe "Same format conversion (copy)" do
    it "copies TTF to TTF successfully" do
      output_path = File.join(output_dir, "copy.ttf")
      pipeline = Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        output_path,
        validate: false,
      )

      result = pipeline.transform

      expect(result[:success]).to be(true)
      expect(File.exist?(output_path)).to be(true)

      # Verify it's still TTF
      font = Fontisan::FontLoader.load(output_path)
      expect(font).to be_a(Fontisan::TrueTypeFont)
    end

    it "preserves all tables in TTF copy" do
      output_path = File.join(output_dir, "copy.ttf")

      original = Fontisan::FontLoader.load(ttf_path)
      original_tables = original.table_names.sort

      pipeline = Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        output_path,
        validate: false,
      )
      pipeline.transform

      copy = Fontisan::FontLoader.load(output_path)
      copy_tables = copy.table_names.sort

      expect(copy_tables).to eq(original_tables)
    end
  end

  describe "Format detection" do
    it "auto-detects target format from extension" do
      output_path = File.join(output_dir, "output.otf")
      pipeline = Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        output_path,
        validate: false,
      )

      result = pipeline.transform

      expect(result[:details][:target_format]).to eq(:otf)
    end

    it "uses explicit target_format option when provided" do
      output_path = File.join(output_dir, "output.font") # Unusual extension
      pipeline = Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        output_path,
        target_format: :otf,
        validate: false,
      )

      result = pipeline.transform

      expect(result[:details][:target_format]).to eq(:otf)

      # Verify it's actually OTF despite extension
      font = Fontisan::FontLoader.load(output_path)
      expect(font).to be_a(Fontisan::OpenTypeFont)
    end
  end

  describe "Verbose mode" do
    it "outputs progress information", :slow do
      output_path = File.join(output_dir, "output.otf")
      pipeline = Fontisan::Pipeline::TransformationPipeline.new(
        ttf_path,
        output_path,
        verbose: true,
        validate: false,
      )

      expect do
        pipeline.transform
      end.to output(/Starting transformation/).to_stdout
    end
  end
end
