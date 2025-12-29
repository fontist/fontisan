# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Collection::TableDeduplicator do
  let(:fonts) { [font1, font2, font3] }
  let(:font3) do
    double(
      "truetype_font",
      table_names: %w[head hhea maxp],
      table_data: {
        "head" => "head_data_3",
        "hhea" => "shared_hhea_data",
        "maxp" => "maxp_data_3",
      },
    ).tap do |font|
      allow(font).to receive(:has_table?).with("fvar").and_return(false)
    end
  end
  let(:font2) do
    double(
      "truetype_font",
      table_names: %w[head hhea maxp name],
      table_data: {
        "head" => "head_data_2",
        "hhea" => "shared_hhea_data",
        "maxp" => "maxp_data_2",
        "name" => "shared_name_data",
      },
    ).tap do |font|
      allow(font).to receive(:has_table?).with("fvar").and_return(false)
    end
  end
  let(:font1) do
    double(
      "truetype_font",
      table_names: %w[head hhea maxp name],
      table_data: {
        "head" => "head_data_1",
        "hhea" => "shared_hhea_data",
        "maxp" => "maxp_data_1",
        "name" => "shared_name_data",
      },
    ).tap do |font|
      allow(font).to receive(:has_table?).with("fvar").and_return(false)
    end
  end

  describe "variable font table deduplication" do
    describe "shareable variation tables" do
      it "shares identical fvar tables" do
        fvar_data = "fvar_table_content"
        font1 = create_font_with_table("fvar", fvar_data)
        font2 = create_font_with_table("fvar", fvar_data)

        deduplicator = described_class.new([font1, font2])
        sharing_map = deduplicator.build_sharing_map

        # Both fonts should reference the same canonical fvar
        canonical_id_1 = sharing_map[0]["fvar"][:canonical_id]
        canonical_id_2 = sharing_map[1]["fvar"][:canonical_id]
        expect(canonical_id_1).to eq(canonical_id_2)
        expect(sharing_map[0]["fvar"][:shared]).to be true
      end

      it "shares identical avar tables" do
        avar_data = "avar_table_content"
        font1 = create_font_with_table("avar", avar_data)
        font2 = create_font_with_table("avar", avar_data)

        deduplicator = described_class.new([font1, font2])
        sharing_map = deduplicator.build_sharing_map

        canonical_id_1 = sharing_map[0]["avar"][:canonical_id]
        canonical_id_2 = sharing_map[1]["avar"][:canonical_id]
        expect(canonical_id_1).to eq(canonical_id_2)
        expect(sharing_map[0]["avar"][:shared]).to be true
      end

      it "shares identical STAT tables" do
        stat_data = "stat_table_content"
        font1 = create_font_with_table("STAT", stat_data)
        font2 = create_font_with_table("STAT", stat_data)

        deduplicator = described_class.new([font1, font2])
        sharing_map = deduplicator.build_sharing_map

        canonical_id_1 = sharing_map[0]["STAT"][:canonical_id]
        canonical_id_2 = sharing_map[1]["STAT"][:canonical_id]
        expect(canonical_id_1).to eq(canonical_id_2)
      end

      it "shares identical HVAR tables" do
        hvar_data = "hvar_table_content"
        font1 = create_font_with_table("HVAR", hvar_data)
        font2 = create_font_with_table("HVAR", hvar_data)

        deduplicator = described_class.new([font1, font2])
        sharing_map = deduplicator.build_sharing_map

        canonical_id_1 = sharing_map[0]["HVAR"][:canonical_id]
        canonical_id_2 = sharing_map[1]["HVAR"][:canonical_id]
        expect(canonical_id_1).to eq(canonical_id_2)
      end

      it "shares identical VVAR tables" do
        vvar_data = "vvar_table_content"
        font1 = create_font_with_table("VVAR", vvar_data)
        font2 = create_font_with_table("VVAR", vvar_data)

        deduplicator = described_class.new([font1, font2])
        sharing_map = deduplicator.build_sharing_map

        canonical_id_1 = sharing_map[0]["VVAR"][:canonical_id]
        canonical_id_2 = sharing_map[1]["VVAR"][:canonical_id]
        expect(canonical_id_1).to eq(canonical_id_2)
      end

      it "shares identical MVAR tables" do
        mvar_data = "mvar_table_content"
        font1 = create_font_with_table("MVAR", mvar_data)
        font2 = create_font_with_table("MVAR", mvar_data)

        deduplicator = described_class.new([font1, font2])
        sharing_map = deduplicator.build_sharing_map

        canonical_id_1 = sharing_map[0]["MVAR"][:canonical_id]
        canonical_id_2 = sharing_map[1]["MVAR"][:canonical_id]
        expect(canonical_id_1).to eq(canonical_id_2)
      end
    end

    describe "font-specific variation tables" do
      it "keeps gvar tables separate even if identical" do
        gvar_data = "gvar_table_content"
        font1 = create_variable_font_with_tables("fvar" => "fvar",
                                                 "gvar" => gvar_data)
        font2 = create_variable_font_with_tables("fvar" => "fvar",
                                                 "gvar" => gvar_data)

        deduplicator = described_class.new([font1, font2])
        sharing_map = deduplicator.build_sharing_map

        # gvar should not be marked as shared
        expect(sharing_map[0]["gvar"][:shared]).to be false
        expect(sharing_map[1]["gvar"][:shared]).to be false
      end

      it "keeps CFF2 tables separate even if identical" do
        cff2_data = "cff2_table_content"
        font1 = create_variable_font_with_tables("fvar" => "fvar",
                                                 "CFF2" => cff2_data)
        font2 = create_variable_font_with_tables("fvar" => "fvar",
                                                 "CFF2" => cff2_data)

        deduplicator = described_class.new([font1, font2])
        sharing_map = deduplicator.build_sharing_map

        # CFF2 should not be marked as shared
        expect(sharing_map[0]["CFF2"][:shared]).to be false
        expect(sharing_map[1]["CFF2"][:shared]).to be false
      end
    end

    describe "has_variable_fonts?" do
      it "returns true when fonts have fvar table" do
        font = create_font_with_table("fvar", "fvar_data")
        deduplicator = described_class.new([font])

        expect(deduplicator.send(:has_variable_fonts?)).to be true
      end

      it "returns false when fonts do not have fvar table" do
        font = create_font_with_table("head", "head_data")
        deduplicator = described_class.new([font])

        expect(deduplicator.send(:has_variable_fonts?)).to be false
      end
    end

    describe "different variation table content" do
      it "does not share different fvar tables" do
        font1 = create_font_with_table("fvar", "fvar_content_1")
        font2 = create_font_with_table("fvar", "fvar_content_2")

        deduplicator = described_class.new([font1, font2])
        sharing_map = deduplicator.build_sharing_map

        canonical_id_1 = sharing_map[0]["fvar"][:canonical_id]
        canonical_id_2 = sharing_map[1]["fvar"][:canonical_id]
        expect(canonical_id_1).not_to eq(canonical_id_2)
        expect(sharing_map[0]["fvar"][:shared]).to be false
        expect(sharing_map[1]["fvar"][:shared]).to be false
      end
    end
  end

  describe "#initialize" do
    it "initializes with fonts array" do
      deduplicator = described_class.new(fonts)
      expect(deduplicator).to be_a(described_class)
    end

    it "raises error when fonts is nil" do
      expect do
        described_class.new(nil)
      end.to raise_error(ArgumentError, "fonts cannot be nil or empty")
    end

    it "raises error when fonts is empty" do
      expect do
        described_class.new([])
      end.to raise_error(ArgumentError, "fonts cannot be nil or empty")
    end

    it "raises error when fonts is not an array" do
      expect do
        described_class.new("not_an_array")
      end.to raise_error(ArgumentError, "fonts must be an array")
    end
  end

  describe "#build_sharing_map" do
    let(:deduplicator) { described_class.new(fonts) }

    it "returns sharing map" do
      sharing_map = deduplicator.build_sharing_map

      expect(sharing_map).to be_a(Hash)
      expect(sharing_map).to have_key(0)
      expect(sharing_map).to have_key(1)
      expect(sharing_map).to have_key(2)
    end

    it "creates entries for each font and table" do
      sharing_map = deduplicator.build_sharing_map

      expect(sharing_map[0]).to have_key("head")
      expect(sharing_map[0]).to have_key("hhea")
      expect(sharing_map[0]).to have_key("maxp")
      expect(sharing_map[0]).to have_key("name")
    end

    it "includes canonical_id for each table" do
      sharing_map = deduplicator.build_sharing_map

      expect(sharing_map[0]["head"]).to have_key(:canonical_id)
      expect(sharing_map[0]["head"]).to have_key(:checksum)
      expect(sharing_map[0]["head"]).to have_key(:data)
      expect(sharing_map[0]["head"]).to have_key(:size)
      expect(sharing_map[0]["head"]).to have_key(:shared)
    end

    it "marks shared tables correctly" do
      sharing_map = deduplicator.build_sharing_map

      # hhea is shared across all 3 fonts
      expect(sharing_map[0]["hhea"][:shared]).to be true
      expect(sharing_map[1]["hhea"][:shared]).to be true
      expect(sharing_map[2]["hhea"][:shared]).to be true

      # head is unique to each font
      expect(sharing_map[0]["head"][:shared]).to be false
      expect(sharing_map[1]["head"][:shared]).to be false
      expect(sharing_map[2]["head"][:shared]).to be false
    end

    it "uses same canonical_id for identical tables" do
      sharing_map = deduplicator.build_sharing_map

      # hhea should have same canonical_id across all fonts
      hhea_id_0 = sharing_map[0]["hhea"][:canonical_id]
      hhea_id_1 = sharing_map[1]["hhea"][:canonical_id]
      hhea_id_2 = sharing_map[2]["hhea"][:canonical_id]

      expect(hhea_id_0).to eq(hhea_id_1)
      expect(hhea_id_1).to eq(hhea_id_2)
    end

    it "uses different canonical_ids for different tables" do
      sharing_map = deduplicator.build_sharing_map

      # head should have different canonical_ids
      head_id_0 = sharing_map[0]["head"][:canonical_id]
      head_id_1 = sharing_map[1]["head"][:canonical_id]

      expect(head_id_0).not_to eq(head_id_1)
    end
  end

  describe "#canonical_tables" do
    let(:deduplicator) { described_class.new(fonts) }

    before do
      deduplicator.build_sharing_map
    end

    it "returns canonical tables map" do
      canonical = deduplicator.canonical_tables

      expect(canonical).to be_a(Hash)
      expect(canonical).to have_key("head")
      expect(canonical).to have_key("hhea")
    end

    it "stores unique versions of each table" do
      canonical = deduplicator.canonical_tables

      # Should have 3 unique head tables
      expect(canonical["head"].size).to eq(3)

      # Should have 1 canonical hhea table (shared)
      expect(canonical["hhea"].size).to eq(1)
    end
  end

  describe "#canonical_table_data" do
    let(:deduplicator) { described_class.new(fonts) }

    before do
      deduplicator.build_sharing_map
    end

    it "returns table data for canonical ID" do
      sharing_map = deduplicator.sharing_map
      canonical_id = sharing_map[0]["hhea"][:canonical_id]

      data = deduplicator.canonical_table_data("hhea", canonical_id)

      expect(data).to eq("shared_hhea_data")
    end

    it "returns nil for non-existent canonical ID" do
      data = deduplicator.canonical_table_data("hhea", "nonexistent_id")
      expect(data).to be_nil
    end
  end

  describe "#canonical_tables_for_tag" do
    let(:deduplicator) { described_class.new(fonts) }

    before do
      deduplicator.build_sharing_map
    end

    it "returns all canonical versions for a tag" do
      canonical_heads = deduplicator.canonical_tables_for_tag("head")

      expect(canonical_heads).to be_a(Hash)
      expect(canonical_heads.size).to eq(3)
    end

    it "returns nil for non-existent tag" do
      result = deduplicator.canonical_tables_for_tag("nonexistent")
      expect(result).to be_nil
    end
  end

  describe "#statistics" do
    let(:deduplicator) { described_class.new(fonts) }

    before do
      deduplicator.build_sharing_map
    end

    it "returns statistics hash" do
      stats = deduplicator.statistics

      expect(stats).to be_a(Hash)
      expect(stats).to have_key(:total_tables)
      expect(stats).to have_key(:shared_tables)
      expect(stats).to have_key(:unique_tables)
      expect(stats).to have_key(:sharing_percentage)
      expect(stats).to have_key(:canonical_count)
    end

    it "counts total tables correctly" do
      stats = deduplicator.statistics

      # Font1: 4 tables, Font2: 4 tables, Font3: 3 tables = 11 total
      expect(stats[:total_tables]).to eq(11)
    end

    it "counts shared tables correctly" do
      stats = deduplicator.statistics

      # hhea is shared across 3 fonts = 3 instances
      # name is shared across 2 fonts = 2 instances
      # Total shared: 5
      expect(stats[:shared_tables]).to eq(5)
    end

    it "calculates sharing percentage" do
      stats = deduplicator.statistics

      expect(stats[:sharing_percentage]).to be > 0
      expect(stats[:sharing_percentage]).to be <= 100
    end
  end

  context "with identical tables across all fonts" do
    let(:identical_fonts) do
      [
        double(
          "truetype_font",
          table_names: %w[head name],
          table_data: {
            "head" => "same_data",
            "name" => "same_name",
          },
        ).tap { |f| allow(f).to receive(:has_table?).with("fvar").and_return(false) },
        double(
          "truetype_font",
          table_names: %w[head name],
          table_data: {
            "head" => "same_data",
            "name" => "same_name",
          },
        ).tap { |f| allow(f).to receive(:has_table?).with("fvar").and_return(false) },
      ]
    end

    it "shares all tables" do
      deduplicator = described_class.new(identical_fonts)
      deduplicator.build_sharing_map

      stats = deduplicator.statistics
      expect(stats[:sharing_percentage]).to eq(100.0)
    end
  end

  context "with no shared tables" do
    let(:unique_fonts) do
      [
        double(
          "truetype_font",
          table_names: %w[head name],
          table_data: {
            "head" => "unique_1",
            "name" => "name_1",
          },
        ).tap { |f| allow(f).to receive(:has_table?).with("fvar").and_return(false) },
        double(
          "truetype_font",
          table_names: %w[head name],
          table_data: {
            "head" => "unique_2",
            "name" => "name_2",
          },
        ).tap { |f| allow(f).to receive(:has_table?).with("fvar").and_return(false) },
      ]
    end

    it "has no shared tables" do
      deduplicator = described_class.new(unique_fonts)
      deduplicator.build_sharing_map

      stats = deduplicator.statistics
      expect(stats[:shared_tables]).to eq(0)
      expect(stats[:sharing_percentage]).to eq(0.0)
    end
  end

  # Helper methods
  def create_font_with_table(tag, data)
    font = instance_double(Fontisan::TrueTypeFont)
    allow(font).to receive_messages(table_names: [tag],
                                    table_data: { tag => data }, has_table?: false)
    allow(font).to receive(:has_table?).with(tag).and_return(true)
    allow(font).to receive(:has_table?).with("fvar").and_return(tag == "fvar")
    font
  end

  def create_variable_font_with_tables(tables)
    font = instance_double(Fontisan::TrueTypeFont)

    # Default to false for all tables
    allow(font).to receive_messages(table_names: tables.keys,
                                    table_data: tables, has_table?: false)

    # Set true for tables that exist
    tables.each_key do |tag|
      allow(font).to receive(:has_table?).with(tag).and_return(true)
    end

    font
  end
end
