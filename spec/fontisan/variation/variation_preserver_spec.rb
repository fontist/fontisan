# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Variation::VariationPreserver do
  let(:source_font) { instance_double(Fontisan::TrueTypeFont) }
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
    allow(source_font).to receive_messages(has_table?: false, table_data: {},
                                           table: nil)
  end

  describe ".preserve" do
    it "preserves variation data from source to target" do
      allow(source_font).to receive(:has_table?).with("fvar").and_return(true)
      allow(source_font).to receive(:table_data).and_return({ "fvar" => fvar_data })

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

    it "raises error when source font doesn't respond to required methods" do
      invalid_font = Object.new

      expect do
        described_class.new(invalid_font, target_tables)
      end.to raise_error(ArgumentError, /must respond to/)
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
      before do
        allow(source_font).to receive(:has_table?).with("fvar").and_return(true)
        allow(source_font).to receive(:has_table?).with("avar").and_return(true)
        allow(source_font).to receive(:has_table?).with("STAT").and_return(true)
        allow(source_font).to receive(:table_data).and_return({
                                                                "fvar" => fvar_data,
                                                                "avar" => avar_data,
                                                                "STAT" => stat_data,
                                                              })
      end

      it "copies fvar table" do
        result = described_class.preserve(source_font, target_tables,
                                          validate: false)

        expect(result["fvar"]).to eq(fvar_data)
      end

      it "copies avar table" do
        result = described_class.preserve(source_font, target_tables,
                                          validate: false)

        expect(result["avar"]).to eq(avar_data)
      end

      it "copies STAT table" do
        result = described_class.preserve(source_font, target_tables,
                                          validate: false)

        expect(result["STAT"]).to eq(stat_data)
      end

      it "copies all common tables together" do
        result = described_class.preserve(source_font, target_tables,
                                          validate: false)

        expect(result.keys).to include("fvar", "avar", "STAT")
      end

      it "creates independent copies of table data" do
        result = described_class.preserve(source_font, target_tables,
                                          validate: false)

        # Modify result
        result["fvar"] = "modified".b

        # Original should be unchanged
        expect(source_font.table_data["fvar"]).to eq(fvar_data)
      end
    end

    context "with TrueType variation tables" do
      before do
        allow(source_font).to receive(:has_table?) do |tag|
          %w[fvar gvar glyf cvar].include?(tag)
        end
        allow(source_font).to receive(:table_data).and_return({
                                                                "fvar" => fvar_data,
                                                                "gvar" => gvar_data,
                                                                "cvar" => cvar_data,
                                                                "glyf" => "glyf_data".b,
                                                              })
      end

      it "copies gvar table when preserve_format_specific is true" do
        result = described_class.preserve(source_font, { "glyf" => "glyf_data".b },
                                          preserve_format_specific: true)

        expect(result["gvar"]).to eq(gvar_data)
      end

      it "copies cvar table when present" do
        result = described_class.preserve(source_font, { "glyf" => "glyf_data".b },
                                          preserve_format_specific: true)

        expect(result["cvar"]).to eq(cvar_data)
      end

      it "does not copy format-specific tables when disabled" do
        result = described_class.preserve(source_font, target_tables,
                                          preserve_format_specific: false,
                                          validate: false)

        expect(result).not_to have_key("gvar")
        expect(result).not_to have_key("cvar")
      end
    end

    context "with CFF2 variation tables" do
      before do
        allow(source_font).to receive(:has_table?) do |tag|
          %w[fvar CFF2].include?(tag)
        end
        allow(source_font).to receive(:table_data).and_return({
                                                                "fvar" => fvar_data,
                                                                "CFF2" => cff2_data,
                                                              })
      end

      it "copies CFF2 table when preserve_format_specific is true" do
        result = described_class.preserve(source_font, target_tables,
                                          preserve_format_specific: true,
                                          validate: false)

        expect(result["CFF2"]).to eq(cff2_data)
      end

      it "does not copy CFF2 if target already has it" do
        target_with_cff2 = { "CFF2" => "different_cff2".b }

        result = described_class.preserve(source_font, target_with_cff2,
                                          preserve_format_specific: true,
                                          validate: false)

        # Should not overwrite existing CFF2
        expect(result["CFF2"]).to eq("different_cff2".b)
      end
    end

    context "with metrics variation tables" do
      before do
        allow(source_font).to receive(:has_table?) do |tag|
          %w[fvar HVAR VVAR MVAR].include?(tag)
        end
        allow(source_font).to receive(:table_data).and_return({
                                                                "fvar" => fvar_data,
                                                                "HVAR" => hvar_data,
                                                                "VVAR" => vvar_data,
                                                                "MVAR" => mvar_data,
                                                              })
      end

      it "copies HVAR table when preserve_metrics is true" do
        result = described_class.preserve(source_font, target_tables,
                                          preserve_metrics: true)

        expect(result["HVAR"]).to eq(hvar_data)
      end

      it "copies VVAR table when preserve_metrics is true" do
        result = described_class.preserve(source_font, target_tables,
                                          preserve_metrics: true)

        expect(result["VVAR"]).to eq(vvar_data)
      end

      it "copies MVAR table when preserve_metrics is true" do
        result = described_class.preserve(source_font, target_tables,
                                          preserve_metrics: true)

        expect(result["MVAR"]).to eq(mvar_data)
      end

      it "does not copy metrics tables when disabled" do
        result = described_class.preserve(source_font, target_tables,
                                          preserve_metrics: false)

        expect(result).not_to have_key("HVAR")
        expect(result).not_to have_key("VVAR")
        expect(result).not_to have_key("MVAR")
      end
    end

    context "with validation enabled" do
      it "raises error if fvar is missing" do
        allow(source_font).to receive(:has_table?).with("gvar").and_return(true)
        allow(source_font).to receive(:table_data).and_return({
                                                                "gvar" => gvar_data,
                                                              })

        expect do
          described_class.preserve(source_font, target_tables,
                                   validate: true)
        end.to raise_error(Fontisan::Error, /fvar table missing/)
      end

      it "raises error if gvar present without glyf" do
        allow(source_font).to receive(:has_table?) do |tag|
          %w[fvar gvar].include?(tag)
        end
        allow(source_font).to receive(:table_data).and_return({
                                                                "fvar" => fvar_data,
                                                                "gvar" => gvar_data,
                                                              })

        expect do
          described_class.preserve(source_font, target_tables,
                                   validate: true)
        end.to raise_error(Fontisan::Error, /gvar present without glyf/)
      end

      it "raises error if CFF2 and glyf both present" do
        allow(source_font).to receive(:has_table?) do |tag|
          %w[fvar CFF2].include?(tag)
        end
        allow(source_font).to receive(:table_data).and_return({
                                                                "fvar" => fvar_data,
                                                                "CFF2" => cff2_data,
                                                              })
        target_with_glyf = { "glyf" => "glyf_data".b }

        expect do
          described_class.preserve(source_font, target_with_glyf,
                                   validate: true,
                                   preserve_format_specific: true)
        end.to raise_error(Fontisan::Error, /CFF2 and glyf both present/)
      end

      it "does not raise error when validation is disabled" do
        allow(source_font).to receive(:has_table?).with("gvar").and_return(true)
        allow(source_font).to receive(:table_data).and_return({
                                                                "gvar" => gvar_data,
                                                              })

        expect do
          described_class.preserve(source_font, target_tables,
                                   validate: false)
        end.not_to raise_error
      end
    end

    context "with existing target tables" do
      let(:existing_tables) do
        {
          "head" => "head_data".b,
          "hhea" => "hhea_data".b,
          "maxp" => "maxp_data".b,
        }
      end

      it "preserves existing tables" do
        allow(source_font).to receive(:has_table?).with("fvar").and_return(true)
        allow(source_font).to receive(:table_data).and_return({
                                                                "fvar" => fvar_data,
                                                              })

        result = described_class.preserve(source_font, existing_tables,
                                          validate: false)

        expect(result).to have_key("head")
        expect(result).to have_key("hhea")
        expect(result).to have_key("maxp")
        expect(result).to have_key("fvar")
      end

      it "does not modify original target tables" do
        allow(source_font).to receive(:has_table?).with("fvar").and_return(true)
        allow(source_font).to receive(:table_data).and_return({
                                                                "fvar" => fvar_data,
                                                              })

        original_size = existing_tables.size
        described_class.preserve(source_font, existing_tables,
                                 validate: false)

        # Original should still have same number of keys
        expect(existing_tables.size).to eq(original_size)
      end
    end
  end

  describe "#variable_font?" do
    it "returns true when source has fvar table" do
      allow(source_font).to receive(:has_table?).with("fvar").and_return(true)
      # Mock fvar table for VariationContext
      fvar_table = instance_double(Fontisan::Tables::Fvar, axes: [])
      allow(source_font).to receive(:table).with("fvar").and_return(fvar_table)

      preserver = described_class.new(source_font, target_tables)

      expect(preserver.variable_font?).to be true
    end

    it "returns false when source has no fvar table" do
      allow(source_font).to receive(:has_table?).with("fvar").and_return(false)

      preserver = described_class.new(source_font, target_tables)

      expect(preserver.variable_font?).to be false
    end
  end

  describe "#variation_type" do
    it "returns :truetype for TrueType variable fonts" do
      allow(source_font).to receive(:has_table?) do |tag|
        %w[fvar gvar].include?(tag)
      end

      preserver = described_class.new(source_font, target_tables)

      expect(preserver.variation_type).to eq(:truetype)
    end

    it "returns :postscript for CFF2 variable fonts" do
      allow(source_font).to receive(:has_table?) do |tag|
        %w[fvar CFF2].include?(tag)
      end

      preserver = described_class.new(source_font, target_tables)

      expect(preserver.variation_type).to eq(:postscript)
    end

    it "returns :none for non-variable fonts" do
      allow(source_font).to receive(:has_table?).and_return(false)

      preserver = described_class.new(source_font, target_tables)

      expect(preserver.variation_type).to eq(:none)
    end
  end
end
