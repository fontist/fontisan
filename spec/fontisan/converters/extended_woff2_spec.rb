# frozen_string_literal: true

require "spec_helper"
require "fontisan/converters/woff2_encoder"
require "tempfile"

RSpec.describe "WOFF2 Extended Testing", :woff2 do
  let(:encoder) { Fontisan::Converters::Woff2Encoder.new }

  describe "MonaSans font collection" do
    let(:base_path) { "spec/fixtures/fonts/MonaSans/mona-sans-2.0.8/fonts" }

    describe "static OTF fonts" do
      [
        "static/otf/MonaSans-Regular.otf",
        "static/otf/MonaSans-Bold.otf",
        "static/otf/MonaSans-Light.otf",
        "static/otf/MonaSans-ExtraBold.otf",
        "static/otf/MonaSansMono-Regular.otf",
      ].each do |font_file|
        it "successfully converts #{File.basename(font_file)} to WOFF2" do
          font_path = File.join(base_path, font_file)

          font = Fontisan::FontLoader.load(font_path)
          result = encoder.convert(font, transform_tables: true)

          expect(result[:woff2_binary]).to be_a(String)
          expect(result[:woff2_binary].bytesize).to be > 0
          expect(result[:woff2_binary][0, 4]).to eq("wOF2")
        end
      end
    end

    describe "variable fonts (TTF)" do
      [
        "variable/MonaSansVF[wght,opsz].ttf",
        "variable/MonaSansMonoVF[wght].ttf",
      ].each do |font_file|
        it "successfully converts #{File.basename(font_file)} to WOFF2" do
          font_path = File.join(base_path, font_file)

          font = Fontisan::FontLoader.load(font_path)
          result = encoder.convert(font, transform_tables: true)

          expect(result[:woff2_binary]).to be_a(String)
          expect(result[:woff2_binary].bytesize).to be > 0
          expect(result[:woff2_binary][0, 4]).to eq("wOF2")
        end
      end
    end
  end

  describe "SourceSans3 font collection" do
    let(:base_path) { "spec/fixtures/fonts/SourceSans3" }

    [
      "OTF/SourceSans3-Bold.otf",
      "OTF/SourceSans3-It.otf",
      "OTF/SourceSans3-Black.otf",
    ].each do |font_file|
      it "successfully converts #{File.basename(font_file)} to WOFF2" do
        font_path = File.join(base_path, font_file)

        font = Fontisan::FontLoader.load(font_path)
        result = encoder.convert(font, transform_tables: true)

        expect(result[:woff2_binary]).to be_a(String)
        expect(result[:woff2_binary].bytesize).to be > 0
        expect(result[:woff2_binary][0, 4]).to eq("wOF2")
      end
    end
  end

  describe "Libertinus font collection" do
    let(:base_path) { "spec/fixtures/fonts/Libertinus/Libertinus-7.051/static" }

    [
      "TTF/LibertinusSans-Bold.ttf",
      "TTF/LibertinusSans-Regular.ttf",
      "TTF/LibertinusSerif-BoldItalic.ttf",
    ].each do |font_file|
      it "successfully converts #{File.basename(font_file)} to WOFF2" do
        font_path = File.join(base_path, font_file)

        font = Fontisan::FontLoader.load(font_path)
        result = encoder.convert(font, transform_tables: true)

        expect(result[:woff2_binary]).to be_a(String)
        expect(result[:woff2_binary].bytesize).to be > 0
        expect(result[:woff2_binary][0, 4]).to eq("wOF2")
      end
    end
  end

  describe "compression efficiency" do
    let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
    let(:font) { Fontisan::FontLoader.load(font_path) }

    it "achieves significant compression with transformations" do
      # Convert with transformations
      with_transform = encoder.convert(font, transform_tables: true)

      # Convert without transformations
      without_transform = encoder.convert(font, transform_tables: false)

      # Calculate original size
      original_size = font.table_data.values.sum(&:bytesize)

      # For small fonts, transformation overhead may slightly increase size
      # But both should still achieve significant overall compression
      expect(with_transform[:woff2_binary].bytesize).to be < original_size
      expect(without_transform[:woff2_binary].bytesize).to be < original_size

      # At least one should achieve >50% compression
      with_ratio = (original_size - with_transform[:woff2_binary].bytesize).to_f / original_size
      without_ratio = (original_size - without_transform[:woff2_binary].bytesize).to_f / original_size

      expect([with_ratio, without_ratio].max).to be > 0.5
    end

    it "reports compression statistics" do
      original_size = font.table_data.values.sum(&:bytesize)
      result = encoder.convert(font, transform_tables: true)
      woff2_size = result[:woff2_binary].bytesize

      compression_ratio = ((original_size - woff2_size).to_f / original_size * 100).round(2)

      puts "\nCompression Statistics:"
      puts "  Original size: #{original_size} bytes"
      puts "  WOFF2 size: #{woff2_size} bytes"
      puts "  Compression: #{compression_ratio}%"
      puts "  Size reduction: #{original_size - woff2_size} bytes"

      expect(compression_ratio).to be > 20.0 # At least 20% compression
    end
  end

  describe "edge cases" do
    let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
    let(:font) { Fontisan::FontLoader.load(font_path) }

    it "handles Brotli quality levels" do
      [0, 5, 11].each do |quality|
        result = encoder.convert(font, transform_tables: true, quality: quality)

        expect(result[:woff2_binary]).to be_a(String)
        expect(result[:woff2_binary].bytesize).to be > 0
      end
    end

    it "produces valid WOFF2 header structure" do
      result = encoder.convert(font, transform_tables: true)
      binary = result[:woff2_binary]

      io = StringIO.new(binary)
      signature = io.read(4)
      flavor = io.read(4).unpack1("N")
      length = io.read(4).unpack1("N")
      num_tables = io.read(2).unpack1("n")
      reserved = io.read(2).unpack1("n")

      expect(signature).to eq("wOF2")
      expect([0x00010000, 0x4F54544F]).to include(flavor)
      expect(length).to eq(binary.bytesize)
      expect(num_tables).to be > 0
      expect(reserved).to eq(0)
    end
  end

  describe "format compatibility" do
    it "works with TTF fonts" do
      font_path = fixture_path("fonttools/TestTTF.ttf")
      font = Fontisan::FontLoader.load(font_path)

      result = encoder.convert(font, transform_tables: true)

      # Check flavor is TrueType
      flavor = result[:woff2_binary][4, 4].unpack1("N")
      expect(flavor).to eq(0x00010000)
    end

    it "works with OTF/CFF fonts when available" do
      # Look for MonaSans OTF
      otf_path = "spec/fixtures/fonts/MonaSans/mona-sans-2.0.8/fonts/static/otf/MonaSans-Regular.otf"

      font = Fontisan::FontLoader.load(otf_path)
      result = encoder.convert(font, transform_tables: true)

      # Check flavor is 'OTTO' for CFF
      flavor = result[:woff2_binary][4, 4].unpack1("N")
      expect(flavor).to eq(0x4F54544F)
    end
  end

  describe "error handling" do
    it "raises error for invalid target format" do
      font = Fontisan::FontLoader.load(fixture_path("fonttools/TestTTF.ttf"))

      expect do
        encoder.convert(font, {})
        encoder.validate(font, :ttf)
      end.to raise_error(Fontisan::Error, /only supports conversion to woff2/)
    end

    it "validates required tables presence" do
      # Create a mock font missing required tables
      incomplete_font = double("Font")
      allow(incomplete_font).to receive(:table).with("head").and_return(nil)
      allow(incomplete_font).to receive(:table).with("hhea").and_return(double)
      allow(incomplete_font).to receive(:table).with("maxp").and_return(double)
      allow(incomplete_font).to receive(:has_table?).and_return(true)

      expect do
        encoder.validate(incomplete_font, :woff2)
      end.to raise_error(Fontisan::Error, /missing required table/)
    end
  end
end
