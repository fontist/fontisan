# frozen_string_literal: true

require "spec_helper"
require "fontisan/woff2/table_transformer"

RSpec.describe Fontisan::Woff2::TableTransformer do
  let(:font) { double("Font") }
  let(:transformer) { described_class.new(font) }

  describe "#initialize" do
    it "creates a transformer with font" do
      expect(transformer.font).to eq(font)
    end
  end

  describe "#transformable?" do
    it "returns true for glyf table" do
      expect(transformer.transformable?("glyf")).to be true
    end

    it "returns true for loca table" do
      expect(transformer.transformable?("loca")).to be true
    end

    it "returns true for hmtx table" do
      expect(transformer.transformable?("hmtx")).to be true
    end

    it "returns false for other tables" do
      expect(transformer.transformable?("head")).to be false
      expect(transformer.transformable?("name")).to be false
      expect(transformer.transformable?("cmap")).to be false
    end
  end

  describe "#transformation_version" do
    it "returns TRANSFORM_GLYF_LOCA for glyf" do
      expect(transformer.transformation_version("glyf")).to eq(Fontisan::Woff2::Directory::TRANSFORM_GLYF_LOCA)
    end

    it "returns TRANSFORM_GLYF_LOCA for loca" do
      expect(transformer.transformation_version("loca")).to eq(Fontisan::Woff2::Directory::TRANSFORM_GLYF_LOCA)
    end

    it "returns TRANSFORM_HMTX for hmtx" do
      expect(transformer.transformation_version("hmtx")).to eq(Fontisan::Woff2::Directory::TRANSFORM_HMTX)
    end

    it "returns TRANSFORM_NONE for non-transformable tables" do
      expect(transformer.transformation_version("head")).to eq(Fontisan::Woff2::Directory::TRANSFORM_NONE)
    end
  end

  describe "#transform_table" do
    context "with loca table" do
      it "returns nil (loca is combined with glyf)" do
        result = transformer.transform_table("loca")
        expect(result).to be_nil
      end
    end

    context "with non-transformable table" do
      it "returns original table data" do
        table_data = "head table data"
        allow(font).to receive(:respond_to?).with(:table_data).and_return(true)
        allow(font).to receive(:table_data).and_return({ "head" => table_data })

        result = transformer.transform_table("head")
        expect(result).to eq(table_data)
      end
    end

    context "when font doesn't respond to table_data" do
      let(:font) { double("Font") }

      it "returns nil" do
        allow(font).to receive(:respond_to?).with(:table_data).and_return(false)
        result = transformer.transform_table("glyf")
        expect(result).to be_nil
      end
    end
  end

  describe "integration with real font" do
    let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
    let(:real_font) { Fontisan::FontLoader.load(font_path) }
    let(:real_transformer) { described_class.new(real_font) }

    it "transforms glyf table to valid WOFF2 format" do
      result = real_transformer.transform_table("glyf")

      expect(result).to be_a(String)
      expect(result.bytesize).to be > 0

      # Check header structure
      io = StringIO.new(result)
      version = io.read(4).unpack1("N")
      num_glyphs = io.read(2).unpack1("n")
      index_format = io.read(2).unpack1("n")

      expect(version).to eq(0)
      expect(num_glyphs).to be > 0
      expect([0, 1]).to include(index_format)
    end

    it "transforms hmtx table to valid WOFF2 format" do
      result = real_transformer.transform_table("hmtx")

      expect(result).to be_a(String)
      expect(result.bytesize).to be > 0

      # Check flags byte
      flags = result.bytes[0]
      expect(flags).to be_a(Integer)
    end

    it "returns nil for loca (combined with glyf)" do
      result = real_transformer.transform_table("loca")
      expect(result).to be_nil
    end

    it "passes through non-transformable tables unchanged" do
      head_data = real_font.table_data["head"]
      result = real_transformer.transform_table("head")

      expect(result).to eq(head_data)
    end
  end

  describe "transformation correctness" do
    let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
    let(:real_font) { Fontisan::FontLoader.load(font_path) }
    let(:real_transformer) { described_class.new(real_font) }

    it "produces valid output for glyf transformation" do
      original_size = real_font.table_data["glyf"].bytesize
      transformed = real_transformer.transform_table("glyf")

      # Transformed should have overhead from stream headers
      # but still be valid format
      expect(transformed.bytesize).to be > 100 # Has header + streams
      expect(original_size).to be > 0
    end

    it "produces valid output for hmtx transformation" do
      transformed = real_transformer.transform_table("hmtx")

      # Should have at least flags byte + some data
      expect(transformed.bytesize).to be > 1
    end
  end
end
