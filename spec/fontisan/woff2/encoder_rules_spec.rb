# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Woff2::EncoderRules do
  let(:head_binary) do
    # Minimal head table — only the first 18 bytes matter for flags
    # (offsets 16..17). Built via the Head BinData record so the test
    # stays aligned with the model.
    head = Fontisan::Tables::Head.new
    head.flags = 0x000B # baseline + LSB-at-0 + ppem-integral (bits 0,1,3)
    head.to_binary_s
  end

  let(:dsig_binary) { "DSIG-payload" }
  let(:cmap_binary) { "cmap-payload" }

  let(:table_data) do
    { "head" => head_binary.dup, "DSIG" => dsig_binary.dup,
      "cmap" => cmap_binary.dup }
  end

  describe "::EXCLUDED_TABLES" do
    it "includes DSIG per WOFF2 spec section 5" do
      expect(described_class::EXCLUDED_TABLES).to include("DSIG")
    end
  end

  describe "::excluded?" do
    it "returns true for tags in EXCLUDED_TABLES" do
      expect(described_class.excluded?("DSIG")).to be true
    end

    it "returns false for tags not in EXCLUDED_TABLES" do
      expect(described_class.excluded?("head")).to be false
      expect(described_class.excluded?("cmap")).to be false
    end
  end

  describe "::exclude_tables!" do
    it "deletes DSIG from the table collection" do
      described_class.exclude_tables!(table_data)
      expect(table_data).not_to have_key("DSIG")
    end

    it "leaves other tables untouched" do
      described_class.exclude_tables!(table_data)
      expect(table_data).to have_key("head")
      expect(table_data).to have_key("cmap")
    end
  end

  describe "::mark_lossless_modifying!" do
    it "sets bit 11 (FLAG_LOSSLESS_MODIFYING) on head.flags" do
      described_class.mark_lossless_modifying!(table_data)
      head = Fontisan::Tables::Head.read(table_data["head"])
      expect(head.flags & Fontisan::Tables::Head::FLAG_LOSSLESS_MODIFYING)
        .to be_nonzero
    end

    it "preserves the other flag bits" do
      described_class.mark_lossless_modifying!(table_data)
      head = Fontisan::Tables::Head.read(table_data["head"])
      expect(head.flags & ~Fontisan::Tables::Head::FLAG_LOSSLESS_MODIFYING)
        .to eq(0x000B)
    end

    it "is idempotent" do
      described_class.mark_lossless_modifying!(table_data)
      before = table_data["head"]
      described_class.mark_lossless_modifying!(table_data)
      expect(table_data["head"]).to eq(before)
    end

    it "is a no-op when no head table is present" do
      table_data.delete("head")
      expect { described_class.mark_lossless_modifying!(table_data) }
        .not_to raise_error
    end
  end

  describe "::apply!" do
    it "runs every encoder rule (exclusion + head marking)" do
      described_class.apply!(table_data)
      expect(table_data).not_to have_key("DSIG")
      head = Fontisan::Tables::Head.read(table_data["head"])
      expect(head.flags & Fontisan::Tables::Head::FLAG_LOSSLESS_MODIFYING)
        .to be_nonzero
    end

    it "returns the same hash for chaining" do
      expect(described_class.apply!(table_data)).to be(table_data)
    end
  end
end
