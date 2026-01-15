# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe "Dfont Pack Integration", :integration do
  let(:ttf_path) do
    font_fixture_path("MonaSans", "fonts/static/ttf/MonaSans-Regular.ttf")
  end
  let(:ttf_bold_path) do
    font_fixture_path("MonaSans", "fonts/static/ttf/MonaSans-Bold.ttf")
  end
  let(:temp_dir) { Dir.mktmpdir }
  let(:dfont_path) { File.join(temp_dir, "test.dfont") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "DfontBuilder" do
    it "creates dfont from single TTF font" do
      font = Fontisan::FontLoader.load(ttf_path)

      builder = Fontisan::Collection::DfontBuilder.new([font])
      result = builder.build_to_file(dfont_path)

      expect(File.exist?(dfont_path)).to be true
      expect(result[:num_fonts]).to eq(1)
      expect(result[:format]).to eq(:dfont)
      expect(result[:total_size]).to be > 0
    end

    it "creates dfont from multiple TTF fonts" do
      font1 = Fontisan::FontLoader.load(ttf_path)
      font2 = Fontisan::FontLoader.load(ttf_bold_path)

      builder = Fontisan::Collection::DfontBuilder.new([font1, font2])
      result = builder.build_to_file(dfont_path)

      expect(File.exist?(dfont_path)).to be true
      expect(result[:num_fonts]).to eq(2)
      expect(result[:format]).to eq(:dfont)
    end

    it "creates valid dfont resource fork structure" do
      font = Fontisan::FontLoader.load(ttf_path)

      builder = Fontisan::Collection::DfontBuilder.new([font])
      builder.build_to_file(dfont_path)

      # Verify resource fork header
      File.open(dfont_path, "rb") do |io|
        # Read header (16 bytes)
        data_offset = io.read(4).unpack1("N")
        map_offset = io.read(4).unpack1("N")
        data_length = io.read(4).unpack1("N")
        map_length = io.read(4).unpack1("N")

        expect(data_offset).to eq(256) # Standard dfont offset
        expect(map_offset).to be > data_offset
        expect(data_length).to be > 0
        expect(map_length).to be > 0
      end
    end

    it "creates readable dfont with extractable SFNT" do
      font = Fontisan::FontLoader.load(ttf_path)

      builder = Fontisan::Collection::DfontBuilder.new([font])
      builder.build_to_file(dfont_path)

      # Verify we can extract SFNT from created dfont
      File.open(dfont_path, "rb") do |io|
        expect(Fontisan::Parsers::DfontParser.dfont?(io)).to be true
        count = Fontisan::Parsers::DfontParser.sfnt_count(io)
        expect(count).to eq(1)

        sfnt_data = Fontisan::Parsers::DfontParser.extract_sfnt(io, index: 0)
        expect(sfnt_data).not_to be_empty
      end
    end

    it "rejects web fonts (WOFF/WOFF2)" do
      # This test assumes we have a WOFF font fixture
      # For now, we'll test the validation logic
      font = Fontisan::FontLoader.load(ttf_path)

      # Mock a WOFF font by changing the class name check
      allow(font.class).to receive(:name).and_return("Fontisan::WoffFont")

      expect do
        Fontisan::Collection::DfontBuilder.new([font])
      end.to raise_error(Fontisan::Error, /Web fonts cannot be packed/)
    end
  end

  describe "PackCommand with dfont format" do
    it "packs fonts into dfont using PackCommand" do
      command = Fontisan::Commands::PackCommand.new(
        [ttf_path, ttf_bold_path],
        output: dfont_path,
        format: :dfont,
      )
      result = command.run

      expect(File.exist?(dfont_path)).to be true
      expect(result[:num_fonts]).to eq(2)
      expect(result[:format]).to eq(:dfont)
      expect(result[:output_path]).to eq(dfont_path)
    end

    it "auto-detects dfont format from .dfont extension" do
      command = Fontisan::Commands::PackCommand.new(
        [ttf_path, ttf_bold_path],
        output: dfont_path,
      )
      result = command.run

      expect(result[:format]).to eq(:dfont)
    end

    it "validates minimum font requirement" do
      expect do
        Fontisan::Commands::PackCommand.new(
          [],
          output: dfont_path,
          format: :dfont,
        )
      end.to raise_error(ArgumentError, /Must specify at least 2 font files/)
    end
  end

  describe "Round-trip: dfont pack and unpack" do
    it "preserves font data through dfont pack/unpack cycle" do
      # Step 1: Pack into dfont
      font1 = Fontisan::FontLoader.load(ttf_path)
      font2 = Fontisan::FontLoader.load(ttf_bold_path)

      builder = Fontisan::Collection::DfontBuilder.new([font1, font2])
      builder.build_to_file(dfont_path)

      # Step 2: Verify dfont is valid
      File.open(dfont_path, "rb") do |io|
        expect(Fontisan::Parsers::DfontParser.dfont?(io)).to be true
        expect(Fontisan::Parsers::DfontParser.sfnt_count(io)).to eq(2)
      end

      # Step 3: Extract SFNT and verify it loads correctly
      File.open(dfont_path, "rb") do |io|
        sfnt_data0 = Fontisan::Parsers::DfontParser.extract_sfnt(io, index: 0)
        sfnt_data1 = Fontisan::Parsers::DfontParser.extract_sfnt(io, index: 1)

        # Write to temp files and load
        temp_ttf0 = File.join(temp_dir, "extracted0.ttf")
        temp_ttf1 = File.join(temp_dir, "extracted1.ttf")

        File.binwrite(temp_ttf0, sfnt_data0)
        File.binwrite(temp_ttf1, sfnt_data1)

        # Verify extracted fonts are valid
        extracted0 = Fontisan::FontLoader.load(temp_ttf0)
        extracted1 = Fontisan::FontLoader.load(temp_ttf1)

        expect(extracted0.valid?).to be true
        expect(extracted1.valid?).to be true
      end
    end

    it "preserves essential table data in round-trip" do
      # Pack
      font1 = Fontisan::FontLoader.load(ttf_path)
      original_head = font1.table("head")
      original_name = font1.table("name")

      font2 = Fontisan::FontLoader.load(ttf_bold_path)
      builder = Fontisan::Collection::DfontBuilder.new([font1, font2])
      builder.build_to_file(dfont_path)

      # Unpack first font
      File.open(dfont_path, "rb") do |io|
        sfnt_data = Fontisan::Parsers::DfontParser.extract_sfnt(io, index: 0)

        temp_ttf = File.join(temp_dir, "extracted.ttf")
        File.binwrite(temp_ttf, sfnt_data)

        extracted = Fontisan::FontLoader.load(temp_ttf)
        extracted_head = extracted.table("head")
        extracted_name = extracted.table("name")

        # Verify key values preserved
        expect(extracted_head.units_per_em).to eq(original_head.units_per_em)
        expect(extracted_name.english_name(1)).to eq(original_name.english_name(1))
      end
    end
  end

  describe "Mixed format support" do
    let(:otf_path) do
      font_fixture_path("MonaSans", "fonts/static/otf/MonaSans-Regular.otf")
    end

    it "creates dfont from mixed TTF and OTF fonts" do
      ttf_font = Fontisan::FontLoader.load(ttf_path)
      otf_font = Fontisan::FontLoader.load(otf_path)

      builder = Fontisan::Collection::DfontBuilder.new([ttf_font, otf_font])
      result = builder.build_to_file(dfont_path)

      expect(File.exist?(dfont_path)).to be true
      expect(result[:num_fonts]).to eq(2)
      expect(result[:format]).to eq(:dfont)
    end

    it "extracts both TTF and OTF from mixed dfont" do
      ttf_font = Fontisan::FontLoader.load(ttf_path)
      otf_font = Fontisan::FontLoader.load(otf_path)

      builder = Fontisan::Collection::DfontBuilder.new([ttf_font, otf_font])
      builder.build_to_file(dfont_path)

      File.open(dfont_path, "rb") do |io|
        expect(Fontisan::Parsers::DfontParser.sfnt_count(io)).to eq(2)

        # Extract both fonts
        sfnt0 = Fontisan::Parsers::DfontParser.extract_sfnt(io, index: 0)
        sfnt1 = Fontisan::Parsers::DfontParser.extract_sfnt(io, index: 1)

        expect(sfnt0).not_to be_empty
        expect(sfnt1).not_to be_empty
      end
    end
  end

  describe "Error handling" do
    it "rejects empty font array" do
      expect do
        Fontisan::Collection::DfontBuilder.new([])
      end.to raise_error(ArgumentError, /cannot be nil or empty/)
    end

    it "rejects nil fonts" do
      expect do
        Fontisan::Collection::DfontBuilder.new(nil)
      end.to raise_error(ArgumentError, /cannot be nil or empty/)
    end

    it "rejects non-array input" do
      expect do
        Fontisan::Collection::DfontBuilder.new("not an array")
      end.to raise_error(ArgumentError, /must be an array/)
    end

    it "rejects fonts without table_data method" do
      invalid_font = double("invalid font")

      expect do
        Fontisan::Collection::DfontBuilder.new([invalid_font])
      end.to raise_error(ArgumentError, /must respond to table_data/)
    end
  end
end
