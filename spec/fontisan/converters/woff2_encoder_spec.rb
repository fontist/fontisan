# frozen_string_literal: true

require "spec_helper"
require "fontisan/converters/woff2_encoder"

RSpec.describe Fontisan::Converters::Woff2Encoder do
  let(:encoder) { described_class.new }

  describe "#initialize" do
    it "creates encoder with config" do
      expect(encoder.config).to be_a(Hash)
    end

    it "loads brotli configuration" do
      expect(encoder.config["brotli"]).to be_a(Hash)
      expect(encoder.config["brotli"]["quality"]).to be_a(Integer)
    end

    it "loads transformation configuration" do
      expect(encoder.config["transformations"]).to be_a(Hash)
    end
  end

  describe "#supported_conversions" do
    it "returns array of conversion pairs" do
      conversions = encoder.supported_conversions
      expect(conversions).to be_an(Array)
      expect(conversions).not_to be_empty
    end

    it "includes TTF to WOFF2 conversion" do
      conversions = encoder.supported_conversions
      expect(conversions).to include(%i[ttf woff2])
    end

    it "includes OTF to WOFF2 conversion" do
      conversions = encoder.supported_conversions
      expect(conversions).to include(%i[otf woff2])
    end
  end

  describe "#supports?" do
    it "returns true for TTF to WOFF2" do
      expect(encoder.supports?(:ttf, :woff2)).to be true
    end

    it "returns true for OTF to WOFF2" do
      expect(encoder.supports?(:otf, :woff2)).to be true
    end

    it "returns false for unsupported conversions" do
      expect(encoder.supports?(:ttf, :otf)).to be false
      expect(encoder.supports?(:woff2, :ttf)).to be false
    end
  end

  describe "#validate" do
    let(:font) do
      double("Font",
             table: nil)
    end

    before do
      allow(font).to receive(:has_table?).with("glyf").and_return(true)
      allow(font).to receive(:has_table?).with("CFF ").and_return(false)
      allow(font).to receive(:has_table?).with("CFF2").and_return(false)
      allow(font).to receive(:table).with("head").and_return(double("HeadTable"))
      allow(font).to receive(:table).with("hhea").and_return(double("HheaTable"))
      allow(font).to receive(:table).with("maxp").and_return(double("MaxpTable"))
      allow(font).to receive(:table).with("glyf").and_return(double("GlyfTable"))
    end

    it "validates successfully for valid TTF font" do
      expect { encoder.validate(font, :woff2) }.not_to raise_error
    end

    it "raises error for wrong target format" do
      expect do
        encoder.validate(font, :ttf)
      end.to raise_error(Fontisan::Error, /only supports conversion to woff2/)
    end

    it "raises error when missing required tables" do
      allow(font).to receive(:table).with("head").and_return(nil)

      expect do
        encoder.validate(font, :woff2)
      end.to raise_error(Fontisan::Error, /missing required table: head/)
    end

    it "raises error when missing glyph tables" do
      allow(font).to receive(:has_table?).with("glyf").and_return(false)
      allow(font).to receive(:has_table?).with("CFF ").and_return(false)
      allow(font).to receive(:has_table?).with("CFF2").and_return(false)
      allow(font).to receive(:table).with("glyf").and_return(nil)
      allow(font).to receive(:table).with("CFF ").and_return(nil)
      allow(font).to receive(:table).with("CFF2").and_return(nil)

      expect do
        encoder.validate(font, :woff2)
      end.to raise_error(Fontisan::Error, /must have either glyf or CFF/)
    end

    it "accepts CFF font" do
      allow(font).to receive(:has_table?).with("glyf").and_return(false)
      allow(font).to receive(:has_table?).with("CFF ").and_return(true)
      allow(font).to receive(:has_table?).with("CFF2").and_return(false)
      allow(font).to receive(:table).with("glyf").and_return(nil)
      allow(font).to receive(:table).with("CFF ").and_return(double("CFFTable"))

      expect { encoder.validate(font, :woff2) }.not_to raise_error
    end
  end

  describe "#convert" do
    let(:font) do
      double("Font",
             table: nil,
             table_names: %w[head hhea maxp hmtx cmap glyf loca])
    end

    let(:table_data_hash) do
      {
        "head" => "H" * 54,
        "hhea" => "H" * 36,
        "maxp" => "M" * 32,
        "hmtx" => "H" * 100,
        "cmap" => "C" * 200,
        "glyf" => "G" * 1000,
        "loca" => "L" * 100,
      }
    end

    before do
      # Mock has_table? calls
      allow(font).to receive(:has_table?).with("glyf").and_return(true)
      allow(font).to receive(:has_table?).with("CFF ").and_return(false)
      allow(font).to receive(:has_table?).with("CFF2").and_return(false)

      # Mock required tables
      allow(font).to receive(:table).with("head").and_return(double("HeadTable"))
      allow(font).to receive(:table).with("hhea").and_return(double("HheaTable"))
      allow(font).to receive(:table).with("maxp").and_return(double("MaxpTable"))
      allow(font).to receive(:table).with("glyf").and_return(double("GlyfTable"))
      allow(font).to receive(:table).with("CFF ").and_return(nil)
      allow(font).to receive(:table).with("CFF2").and_return(nil)

      # Mock table_data to return hash
      allow(font).to receive(:table_data).and_return(table_data_hash)
      # Also handle table_data(tag) calls with argument
      allow(font).to receive(:table_data) do |tag|
        tag ? table_data_hash[tag] : table_data_hash
      end
    end

    it "returns hash with woff2_binary key" do
      result = encoder.convert(font)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:woff2_binary)
    end

    it "produces binary data" do
      result = encoder.convert(font)
      binary = result[:woff2_binary]

      expect(binary).to be_a(String)
      expect(binary.encoding).to eq(Encoding::BINARY)
      expect(binary.bytesize).to be > 0
    end

    it "starts with WOFF2 signature" do
      result = encoder.convert(font)
      binary = result[:woff2_binary]

      signature = binary[0, 4].unpack1("N")
      expect(signature).to eq(0x774F4632) # 'wOF2'
    end

    it "accepts quality option" do
      result = encoder.convert(font, quality: 9)
      expect(result[:woff2_binary]).to be_a(String)
    end

    it "respects transform_tables option" do
      result = encoder.convert(font, transform_tables: false)
      expect(result[:woff2_binary]).to be_a(String)
    end

    it "produces compressed output" do
      result = encoder.convert(font)
      binary = result[:woff2_binary]

      # Calculate total input size
      input_size = 0
      font.table_names.each do |tag|
        data = font.table_data(tag)
        input_size += data.bytesize if data
      end

      # WOFF2 should be smaller (compressed)
      # Account for header overhead but should still be smaller overall
      expect(binary.bytesize).to be < input_size + 200
    end
  end

  describe "private methods" do
    describe "#detect_flavor" do
      it "detects TrueType flavor" do
        font = double("Font")
        allow(font).to receive(:has_table?).with("glyf").and_return(true)
        allow(font).to receive(:has_table?).with("CFF ").and_return(false)
        allow(font).to receive(:has_table?).with("CFF2").and_return(false)
        allow(font).to receive(:table).with("CFF ").and_return(nil)
        allow(font).to receive(:table).with("CFF2").and_return(nil)
        allow(font).to receive(:table).with("glyf").and_return(double("GlyfTable"))

        flavor = encoder.send(:detect_flavor, font)
        expect(flavor).to eq(0x00010000)
      end

      it "detects CFF flavor" do
        font = double("Font")
        allow(font).to receive(:has_table?).with("glyf").and_return(false)
        allow(font).to receive(:has_table?).with("CFF ").and_return(true)
        allow(font).to receive(:has_table?).with("CFF2").and_return(false)
        allow(font).to receive(:table).with("CFF ").and_return(double("CFFTable"))
        allow(font).to receive(:table).with("glyf").and_return(nil)

        flavor = encoder.send(:detect_flavor, font)
        expect(flavor).to eq(0x4F54544F)
      end

      it "raises error when neither glyf nor CFF present" do
        font = double("Font")
        allow(font).to receive(:has_table?).with("glyf").and_return(false)
        allow(font).to receive(:has_table?).with("CFF ").and_return(false)
        allow(font).to receive(:has_table?).with("CFF2").and_return(false)
        allow(font).to receive(:table).with("CFF ").and_return(nil)
        allow(font).to receive(:table).with("CFF2").and_return(nil)
        allow(font).to receive(:table).with("glyf").and_return(nil)

        expect do
          encoder.send(:detect_flavor, font)
        end.to raise_error(Fontisan::Error, /Cannot determine font flavor/)
      end
    end

    describe "#calculate_sfnt_size" do
      it "calculates size correctly" do
        tables = {
          "head" => "H" * 54,
          "hhea" => "H" * 36,
          "maxp" => "M" * 32,
        }

        size = encoder.send(:calculate_sfnt_size, tables)

        # Should include header, directory, and padded tables
        expect(size).to be > 0
        expect(size).to be >= 12 + (tables.size * 16) + 122
      end

      it "includes padding" do
        # Table with size not divisible by 4
        tables = { "test" => "X" * 55 }

        size = encoder.send(:calculate_sfnt_size, tables)

        # Should include 1 byte of padding for 55-byte table
        expect(size).to be >= 12 + 16 + 56
      end
    end
  end

  describe "configuration" do
    it "uses default quality when not in config" do
      encoder_no_config = described_class.new(config_path: "/nonexistent/path")
      expect(encoder_no_config.config["brotli"]["quality"]).to be_a(Integer)
    end

    it "loads configuration from file if exists" do
      expect(encoder.config).to be_a(Hash)
      expect(encoder.config["brotli"]).to be_a(Hash)
    end
  end
end
