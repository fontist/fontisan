# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Variation::VariationPreserver do
  # FakeFont provides has_table?/table_data based on tables_hash.
  # We use allow() to override #table for tags where the preserver's
  # VariationContext needs a parsed Fvar-like object (not raw bytes).
  let(:source_font) { Fontisan::SpecHelpers::FakeFont.new({}) }
  let(:target_tables) { {} }
  let(:options) { {} }

  # Mock table data
  let(:fvar_data) { "fvar_data".b }
  let(:avar_data) { "avar_data".b }
  let(:stat_data) { "stat_data".b }
  let(:gvar_data) { "gvar_data".b }
  let(:cvar_data) { "cvar_data".b }
  let(:cff2_data) { "cff2_data".b }
  let(:hvar_data) { "hvar_data".b }
  let(:vvar_data) { "vvar_data".b }
  let(:mvar_data) { "mvar_data".b }

  before do
    # Stub #table to return Fvar-like objects for parsed-table access
    # by VariationContext. table_data still reads from tables_hash.
    allow(source_font).to receive(:table) do |tag|
      source_font.tables_hash[tag] ? double("Table", axes: []) : nil
    end
  end

  describe ".preserve" do
    it "preserves variation data from source to target" do
      source_font.tables_hash["fvar"] = fvar_data

      result = described_class.preserve(source_font, target_tables)

      expect(result).to have_key("fvar")
      expect(result["fvar"]).to eq(fvar_data)
    end
  end

  describe "#initialize" do
    it "initializes with valid parameters" do
      preserver = described_class.new(source_font, target_tables)

      expect(preserver.source_font).to eq(source_font)
      expect(preserver.target_tables).to be_a(Hash)
      expect(preserver.options).to be_a(Hash)
    end

    it "raises error when source font is nil" do
      expect do
        described_class.new(nil, target_tables)
      end.to raise_error(ArgumentError, /Source font cannot be nil/)
    end

    it "raises error when source font isn't an SfntSource" do
      invalid_font = Object.new

      expect do
        described_class.new(invalid_font, target_tables)
      end.to raise_error(ArgumentError, /must be an SfntSource/)
    end

    it "raises error when target tables is nil" do
      expect do
        described_class.new(source_font, nil)
      end.to raise_error(ArgumentError, /Target tables cannot be nil/)
    end

    it "raises error when target tables is not a Hash" do
      expect do
        described_class.new(source_font, "not a hash")
      end.to raise_error(ArgumentError, /must be a Hash/)
    end
  end

  describe "#preserve" do
    context "with common variation tables" do
      it "preserves fvar, avar, STAT" do
        source_font.tables_hash["fvar"] = fvar_data
        source_font.tables_hash["avar"] = avar_data
        source_font.tables_hash["STAT"] = stat_data

        result = described_class.new(source_font, target_tables).preserve

        expect(result["fvar"]).to eq(fvar_data)
        expect(result["avar"]).to eq(avar_data)
        expect(result["STAT"]).to eq(stat_data)
      end
    end

    context "with TrueType-specific variation tables" do
      it "preserves gvar, cvar" do
        source_font.tables_hash["fvar"] = fvar_data
        source_font.tables_hash["gvar"] = gvar_data
        source_font.tables_hash["cvar"] = cvar_data
        target_tables["fvar"] = fvar_data
        target_tables["glyf"] = "glyf_data".b

        result = described_class.new(source_font, target_tables).preserve

        expect(result["gvar"]).to eq(gvar_data)
        expect(result["cvar"]).to eq(cvar_data)
      end
    end

    context "with CFF2-specific variation tables" do
      it "preserves CFF2" do
        source_font.tables_hash["fvar"] = fvar_data
        source_font.tables_hash["CFF2"] = cff2_data

        result = described_class.new(source_font, target_tables).preserve

        expect(result["CFF2"]).to eq(cff2_data)
      end
    end

    context "with metrics variation tables" do
      it "preserves HVAR, VVAR, MVAR" do
        source_font.tables_hash["fvar"] = fvar_data
        source_font.tables_hash["HVAR"] = hvar_data
        source_font.tables_hash["VVAR"] = vvar_data
        source_font.tables_hash["MVAR"] = mvar_data

        result = described_class.new(source_font, target_tables).preserve

        expect(result["HVAR"]).to eq(hvar_data)
        expect(result["VVAR"]).to eq(vvar_data)
        expect(result["MVAR"]).to eq(mvar_data)
      end
    end

    context "with no variation tables" do
      it "raises error when source has no fvar" do
        expect do
          described_class.new(source_font, target_tables).preserve
        end.to raise_error(Fontisan::Error, /fvar table missing/)
      end
    end
  end

  describe "options handling" do
    it "respects :preserve_format_specific option to skip gvar" do
      source_font.tables_hash["fvar"] = fvar_data
      source_font.tables_hash["gvar"] = gvar_data
      target_tables["fvar"] = fvar_data
      target_tables["glyf"] = "glyf_data".b

      result = described_class.new(source_font, target_tables,
                                   preserve_format_specific: false).preserve

      expect(result).to have_key("fvar")
      expect(result).not_to have_key("gvar")
    end
  end
end
