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
    it "returns TRANSFORM_NONE for this milestone" do
      expect(transformer.transformation_version("glyf")).to eq(Fontisan::Woff2::Directory::TRANSFORM_NONE)
      expect(transformer.transformation_version("loca")).to eq(Fontisan::Woff2::Directory::TRANSFORM_NONE)
      expect(transformer.transformation_version("hmtx")).to eq(Fontisan::Woff2::Directory::TRANSFORM_NONE)
    end

    it "returns TRANSFORM_NONE for non-transformable tables" do
      expect(transformer.transformation_version("head")).to eq(Fontisan::Woff2::Directory::TRANSFORM_NONE)
    end
  end

  describe "#transform_table" do
    context "with glyf table" do
      it "returns original table data" do
        table_data = "glyf table data"
        allow(font).to receive(:table_data).with("glyf").and_return(table_data)

        result = transformer.transform_table("glyf")
        expect(result).to eq(table_data)
      end

      it "handles missing table" do
        allow(font).to receive(:table_data).with("glyf").and_return(nil)

        result = transformer.transform_table("glyf")
        expect(result).to be_nil
      end
    end

    context "with loca table" do
      it "returns original table data" do
        table_data = "loca table data"
        allow(font).to receive(:table_data).with("loca").and_return(table_data)

        result = transformer.transform_table("loca")
        expect(result).to eq(table_data)
      end
    end

    context "with hmtx table" do
      it "returns original table data" do
        table_data = "hmtx table data"
        allow(font).to receive(:table_data).with("hmtx").and_return(table_data)

        result = transformer.transform_table("hmtx")
        expect(result).to eq(table_data)
      end
    end

    context "with non-transformable table" do
      it "returns original table data" do
        table_data = "head table data"
        allow(font).to receive(:table_data).with("head").and_return(table_data)

        result = transformer.transform_table("head")
        expect(result).to eq(table_data)
      end
    end

    context "when font doesn't respond to table_data" do
      let(:font) { double("Font") }

      it "returns nil" do
        result = transformer.transform_table("glyf")
        expect(result).to be_nil
      end
    end
  end

  describe "integration with real font object" do
    let(:font) do
      double("Font",
             table_data: nil)
    end

    before do
      allow(font).to receive(:table_data).with("head").and_return("head data")
      allow(font).to receive(:table_data).with("glyf").and_return("glyf data")
      allow(font).to receive(:table_data).with("loca").and_return("loca data")
      allow(font).to receive(:table_data).with("hmtx").and_return("hmtx data")
    end

    it "transforms all tables consistently" do
      tables = %w[head glyf loca hmtx]

      tables.each do |tag|
        result = transformer.transform_table(tag)
        expect(result).to eq(font.table_data(tag))
      end
    end

    it "identifies transformable tables" do
      expect(transformer.transformable?("glyf")).to be true
      expect(transformer.transformable?("loca")).to be true
      expect(transformer.transformable?("hmtx")).to be true
      expect(transformer.transformable?("head")).to be false
    end
  end

  describe "future transformation preparation" do
    it "has architecture for glyf transformation" do
      # Verify method exists (even if not yet implemented)
      expect(transformer).to respond_to(:transform_table)
    end

    it "returns consistent transformation versions" do
      %w[glyf loca hmtx head name].each do |tag|
        version = transformer.transformation_version(tag)
        expect(version).to be_a(Integer)
        expect(version).to eq(0) # All TRANSFORM_NONE for this milestone
      end
    end
  end
end
