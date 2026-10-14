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
      Fontisan::SpecHelpers::FakeFont.new({
                                            "head" => Struct.new(:tag).new("HeadTable"),
                                            "hhea" => Struct.new(:tag).new("HheaTable"),
                                            "maxp" => Struct.new(:tag).new("MaxpTable"),
                                            "glyf" => Struct.new(:tag).new("GlyfTable"),
                                          })
    end

    before do
      allow(font).to receive(:has_table?).with("glyf").and_return(true)
      allow(font).to receive(:has_table?).with("CFF ").and_return(false)
      allow(font).to receive(:has_table?).with("CFF2").and_return(false)
      allow(font).to receive(:table).with("head").and_return(Struct.new(:tag).new("HeadTable"))
      allow(font).to receive(:table).with("hhea").and_return(Struct.new(:tag).new("HheaTable"))
      allow(font).to receive(:table).with("maxp").and_return(Struct.new(:tag).new("MaxpTable"))
      allow(font).to receive(:table).with("glyf").and_return(Struct.new(:tag).new("GlyfTable"))
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
      allow(font).to receive(:table).with("CFF ").and_return(Struct.new(:tag).new("CFFTable"))

      expect { encoder.validate(font, :woff2) }.not_to raise_error
    end
  end

  describe "#convert" do
    let(:ttf_path) { fixture_path("fonttools/TestTTF.ttf") }
    let(:font) { Fontisan::FontLoader.load(ttf_path) }

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

      input_size = font.table_data.values.sum(&:bytesize)

      # WOFF2 should be smaller (compressed) than the raw SFNT input.
      expect(binary.bytesize).to be < input_size
    end
  end

  describe "#convert font flavor" do
    it "writes TrueType flavor to the WOFF2 header" do
      font = Fontisan::FontLoader.load(fixture_path("fonttools/TestTTF.ttf"))
      binary = encoder.convert(font)[:woff2_binary]

      expect(Fontisan::Woff2::Woff2Header.read(binary).flavor).to eq(0x00010000)
    end

    it "writes CFF flavor to the WOFF2 header" do
      font = Fontisan::FontLoader.load(fixture_path("fonttools/TestOTF.otf"))
      binary = encoder.convert(font)[:woff2_binary]

      expect(Fontisan::Woff2::Woff2Header.read(binary).flavor).to eq(0x4F54544F)
    end

    it "rejects a font with neither glyf nor CFF outlines" do
      source = Fontisan::FontLoader.load(fixture_path("fonttools/TestTTF.ttf"))
      tables = source.table_data.except("glyf", "loca")
      font = Fontisan::SpecHelpers::FakeFont.new(tables)

      expect do
        encoder.convert(font)
      end.to raise_error(Fontisan::Error, "Font must have either glyf or CFF/CFF2 table")
    end
  end

  describe "#convert total SFNT size" do
    let(:source) { Fontisan::FontLoader.load(fixture_path("fonttools/TestOTF.otf")) }
    let(:tables) { source.table_data.except("DSIG") }
    let(:font) { Fontisan::SpecHelpers::FakeFont.new(tables) }
    let(:binary) { encoder.convert(font)[:woff2_binary] }
    let(:header) { Fontisan::Woff2::Woff2Header.read(binary) }

    it "includes the SFNT header, full directory, and aligned tables" do
      expected_size = 12 + tables.size * 16 + tables.values.sum { |data| (data.bytesize + 3) / 4 * 4 }

      expect(header.num_tables).to eq(tables.size)
      expect(header.total_sfnt_size).to eq(expected_size)
    end

    it "includes padding for a 55-byte table" do
      original_size = header.total_sfnt_size.to_i
      tables["test"] = "X" * 55
      padded_header = Fontisan::Woff2::Woff2Header.read(encoder.convert(font)[:woff2_binary])

      expect(padded_header.num_tables).to eq(header.num_tables + 1)
      expect(padded_header.total_sfnt_size).to eq(original_size + 16 + 56)
    end

    it "includes reconstructed loca bytes and its synthetic directory entry" do
      source = Fontisan::FontLoader.load(fixture_path("fonttools/TestTTF.ttf"))
      binary = encoder.convert(source)[:woff2_binary]
      Tempfile.create(["encoded", ".woff2"]) do |file|
        File.binwrite(file.path, binary)
        decoded = Fontisan::FontLoader.load(file.path)
        entries = decoded.table_entries
        header = decoded.header
        loca_entry = decoded.table_entries.find { |entry| entry.tag == "loca" }
        without_loca = entries.reject { |entry| entry.tag == "loca" }
        size_without_loca = 12 + without_loca.size * 16 + without_loca.sum { |entry| (entry.orig_length.to_i + 3) / 4 * 4 }
        loca_size = (loca_entry.orig_length.to_i + 3) / 4 * 4

        expect(loca_entry.transform_length).to eq(0)
        expect(loca_size).to be > 0
        expect(header.num_tables).to eq(entries.size)
        expect(header.total_sfnt_size).to eq(size_without_loca + 16 + loca_size)
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

  describe "options DSL — convert with real font" do
    let(:ttf_path) do
      File.join(__dir__, "../../fixtures/fonts/NotoSans/NotoSans-Regular.ttf")
    end
    let(:font) { Fontisan::FontLoader.load(ttf_path) }

    it "accepts brotli_quality: 11 and produces valid WOFF2" do
      result = encoder.convert(font, brotli_quality: 11)
      binary = result[:woff2_binary]

      signature = binary[0, 4].unpack1("N")
      expect(signature).to eq(0x774F4632) # 'wOF2'
    end

    it "produces larger output at brotli_quality 0 than at quality 11" do
      result_max = encoder.convert(font, brotli_quality: 11)
      result_min = encoder.convert(font, brotli_quality: 0)

      # Lower quality = less compression = larger output
      expect(result_min[:woff2_binary].bytesize).to be > result_max[:woff2_binary].bytesize
    end

    it "rejects out-of-range brotli_quality" do
      expect do
        encoder.convert(font, brotli_quality: 99)
      end.to raise_error(ArgumentError, /brotli_quality/)
    end

    it "honors legacy :quality alias as brotli_quality" do
      result = encoder.convert(font, quality: 5)
      expect(result[:woff2_binary].bytesize).to be > 0
    end

    it "transform_tables: false produces a valid WOFF2" do
      result = encoder.convert(font, transform_tables: false)
      signature = result[:woff2_binary][0, 4].unpack1("N")
      expect(signature).to eq(0x774F4632)
    end
  end
end
