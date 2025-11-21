# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Converters::TableCopier do
  let(:copier) { described_class.new }
  let(:ttf_font) { double("TrueTypeFont") }
  let(:otf_font) { double("OpenTypeFont") }

  before do
    # Setup TTF font mock
    allow(ttf_font).to receive(:has_table?).with("glyf").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("CFF ").and_return(false)
    allow(ttf_font).to receive(:has_table?).with("CFF2").and_return(false)
    allow(ttf_font).to receive(:table).with("glyf").and_return(double)
    allow(ttf_font).to receive(:table).with("CFF ").and_return(nil)
    allow(ttf_font).to receive(:table).with("CFF2").and_return(nil)
    allow(ttf_font).to receive_messages(tables: {
                                          "head" => double,
                                          "hhea" => double,
                                          "maxp" => double,
                                          "glyf" => double,
                                          "loca" => double,
                                        }, table_data: {
                                          "head" => "head_data",
                                          "hhea" => "hhea_data",
                                          "maxp" => "maxp_data",
                                          "glyf" => "glyf_data",
                                          "loca" => "loca_data",
                                        })
    allow(ttf_font).to receive(:read_table_data) do |tag|
      "#{tag}_data"
    end

    # Setup OTF font mock
    allow(otf_font).to receive(:has_table?).with("glyf").and_return(false)
    allow(otf_font).to receive(:has_table?).with("CFF ").and_return(true)
    allow(otf_font).to receive(:has_table?).with("CFF2").and_return(false)
    allow(otf_font).to receive(:table).with("CFF ").and_return(double)
    allow(otf_font).to receive(:table).with("CFF2").and_return(nil)
    allow(otf_font).to receive(:table).with("glyf").and_return(nil)
    allow(otf_font).to receive_messages(tables: {
                                          "head" => double,
                                          "hhea" => double,
                                          "maxp" => double,
                                          "CFF " => double,
                                        }, table_data: {
                                          "head" => "head_data",
                                          "hhea" => "hhea_data",
                                          "maxp" => "maxp_data",
                                          "CFF " => "CFF _data",
                                        })
    allow(otf_font).to receive(:read_table_data) do |tag|
      "#{tag}_data"
    end
  end

  describe "#convert" do
    context "with TTF font" do
      it "copies all tables" do
        tables = copier.convert(ttf_font)

        expect(tables).to be_a(Hash)
        expect(tables.keys).to include("head", "hhea", "maxp", "glyf", "loca")
      end

      it "preserves table data" do
        tables = copier.convert(ttf_font)

        expect(tables["head"]).to eq("head_data")
        expect(tables["glyf"]).to eq("glyf_data")
      end
    end

    context "with OTF font" do
      it "copies all tables" do
        tables = copier.convert(otf_font)

        expect(tables).to be_a(Hash)
        expect(tables.keys).to include("head", "hhea", "maxp", "CFF ")
      end

      it "preserves table data" do
        tables = copier.convert(otf_font)

        expect(tables["CFF "]).to eq("CFF _data")
      end
    end

    context "with invalid font" do
      it "raises error for nil font" do
        expect do
          copier.convert(nil)
        end.to raise_error(ArgumentError, /Font cannot be nil/)
      end

      it "raises error for font without tables method" do
        invalid_font = double("InvalidFont")
        allow(invalid_font).to receive(:table).and_return(double)

        expect do
          copier.convert(invalid_font)
        end.to raise_error(ArgumentError, /must respond to :tables/)
      end

      it "raises error for font without read_table_data method" do
        invalid_font = double("InvalidFont")
        allow(invalid_font).to receive_messages(table: double, tables: {},
                                                has_table?: false)

        expect do
          copier.convert(invalid_font)
        end.to raise_error(ArgumentError, /must respond to :table_data/)
      end
    end
  end

  describe "#supported_conversions" do
    it "supports TTF to TTF" do
      conversions = copier.supported_conversions
      expect(conversions).to include(%i[ttf ttf])
    end

    it "supports OTF to OTF" do
      conversions = copier.supported_conversions
      expect(conversions).to include(%i[otf otf])
    end

    it "does not support cross-format conversions" do
      conversions = copier.supported_conversions
      expect(conversions).not_to include(%i[ttf otf])
      expect(conversions).not_to include(%i[otf ttf])
    end
  end

  describe "#validate" do
    it "validates TTF to TTF conversion" do
      expect do
        copier.validate(ttf_font, :ttf)
      end.not_to raise_error
    end

    it "validates OTF to OTF conversion" do
      expect do
        copier.validate(otf_font, :otf)
      end.not_to raise_error
    end

    it "rejects mismatched formats" do
      expect do
        copier.validate(ttf_font, :otf)
      end.to raise_error(Fontisan::Error, /source and target formats to match/)
    end

    it "rejects nil font" do
      expect do
        copier.validate(nil, :ttf)
      end.to raise_error(ArgumentError, /Font cannot be nil/)
    end
  end

  describe "#supports?" do
    it "returns true for TTF to TTF" do
      expect(copier.supports?(:ttf, :ttf)).to be true
    end

    it "returns true for OTF to OTF" do
      expect(copier.supports?(:otf, :otf)).to be true
    end

    it "returns false for TTF to OTF" do
      expect(copier.supports?(:ttf, :otf)).to be false
    end

    it "returns false for OTF to TTF" do
      expect(copier.supports?(:otf, :ttf)).to be false
    end
  end

  describe "format detection" do
    it "detects TTF from glyf table" do
      tables = copier.convert(ttf_font)
      expect(tables).to include("glyf")
    end

    it "detects OTF from CFF table" do
      tables = copier.convert(otf_font)
      expect(tables).to include("CFF ")
    end

    it "raises error for ambiguous format" do
      ambiguous_font = double("AmbiguousFont")
      allow(ambiguous_font).to receive(:has_table?).and_return(false)
      allow(ambiguous_font).to receive_messages(table: nil, tables: {},
                                                table_data: {})

      expect do
        copier.convert(ambiguous_font)
      end.to raise_error(Fontisan::Error, /Cannot detect font format/)
    end
  end

  describe "table handling" do
    it "skips tables with nil data" do
      table_data_with_nil = ttf_font.table_data.dup
      table_data_with_nil["head"] = nil
      allow(ttf_font).to receive(:table_data).and_return(table_data_with_nil)
      tables = copier.convert(ttf_font)

      expect(tables).not_to have_key("head")
    end

    it "includes all non-nil tables" do
      tables = copier.convert(ttf_font)

      ttf_font.table_data.each_key do |tag|
        expect(tables).to have_key(tag)
      end
    end
  end
end
