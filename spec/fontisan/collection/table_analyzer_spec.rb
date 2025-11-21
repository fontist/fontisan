# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Collection::TableAnalyzer do
  let(:font1) do
    double(
      "truetype_font",
      table_names: %w[head hhea maxp name cmap],
      table_data: {
        "head" => "head_data_1",
        "hhea" => "shared_hhea_data",
        "maxp" => "maxp_data_1",
        "name" => "shared_name_data",
        "cmap" => "cmap_data_1",
      },
    )
  end

  let(:font2) do
    double(
      "truetype_font",
      table_names: %w[head hhea maxp name cmap],
      table_data: {
        "head" => "head_data_2",
        "hhea" => "shared_hhea_data",
        "maxp" => "maxp_data_2",
        "name" => "shared_name_data",
        "cmap" => "cmap_data_2",
      },
    )
  end

  let(:font3) do
    double(
      "truetype_font",
      table_names: %w[head hhea maxp name],
      table_data: {
        "head" => "head_data_3",
        "hhea" => "shared_hhea_data",
        "maxp" => "maxp_data_3",
        "name" => "shared_name_data",
      },
    )
  end

  let(:fonts) { [font1, font2, font3] }

  describe "#initialize" do
    it "initializes with fonts array" do
      analyzer = described_class.new(fonts)
      expect(analyzer).to be_a(described_class)
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

  describe "#analyze" do
    let(:analyzer) { described_class.new(fonts) }

    it "returns analysis report" do
      report = analyzer.analyze

      expect(report).to be_a(Hash)
      expect(report).to have_key(:total_fonts)
      expect(report).to have_key(:table_checksums)
      expect(report).to have_key(:shared_tables)
      expect(report).to have_key(:unique_tables)
      expect(report).to have_key(:space_savings)
      expect(report).to have_key(:sharing_percentage)
    end

    it "identifies total fonts correctly" do
      report = analyzer.analyze
      expect(report[:total_fonts]).to eq(3)
    end

    it "identifies shared tables" do
      report = analyzer.analyze

      # hhea and name are shared across all 3 fonts
      expect(report[:shared_tables]).to have_key("hhea")
      expect(report[:shared_tables]).to have_key("name")

      # Shared tables should have groups with multiple fonts
      hhea_group = report[:shared_tables]["hhea"].first
      expect(hhea_group[:font_indices]).to contain_exactly(0, 1, 2)
      expect(hhea_group[:count]).to eq(3)
    end

    it "identifies unique tables" do
      report = analyzer.analyze

      # head, maxp, cmap have different content in each font
      expect(report[:unique_tables]).to have_key("head")
      expect(report[:unique_tables]).to have_key("maxp")
    end

    it "calculates space savings" do
      report = analyzer.analyze

      # Should have positive space savings from shared tables
      expect(report[:space_savings]).to be > 0

      # hhea is shared 3 times: saves 2 * size
      # name is shared 3 times: saves 2 * size
      expected_savings = (2 * "shared_hhea_data".bytesize) + (2 * "shared_name_data".bytesize)
      expect(report[:space_savings]).to eq(expected_savings)
    end

    it "calculates sharing percentage" do
      report = analyzer.analyze

      expect(report[:sharing_percentage]).to be > 0
      expect(report[:sharing_percentage]).to be <= 100
    end

    it "collects table checksums" do
      report = analyzer.analyze

      expect(report[:table_checksums]).to be_a(Hash)
      expect(report[:table_checksums]).to have_key("hhea")
      expect(report[:table_checksums]).to have_key("name")
    end
  end

  describe "#shared_tables" do
    let(:analyzer) { described_class.new(fonts) }

    it "returns shared tables map" do
      shared = analyzer.shared_tables

      expect(shared).to be_a(Hash)
      expect(shared).to have_key("hhea")
      expect(shared).to have_key("name")
    end

    it "automatically analyzes if not yet analyzed" do
      shared = analyzer.shared_tables
      expect(shared).not_to be_nil
    end
  end

  describe "#space_savings" do
    let(:analyzer) { described_class.new(fonts) }

    it "returns space savings amount" do
      savings = analyzer.space_savings
      expect(savings).to be_a(Integer)
      expect(savings).to be > 0
    end
  end

  describe "#sharing_percentage" do
    let(:analyzer) { described_class.new(fonts) }

    it "returns sharing percentage" do
      percentage = analyzer.sharing_percentage
      expect(percentage).to be_a(Float)
      expect(percentage).to be >= 0
      expect(percentage).to be <= 100
    end
  end

  context "with all unique tables" do
    let(:unique_fonts) do
      [
        double(
          "truetype_font",
          table_names: %w[head name],
          table_data: {
            "head" => "head_1",
            "name" => "name_1",
          },
        ),
        double(
          "truetype_font",
          table_names: %w[head name],
          table_data: {
            "head" => "head_2",
            "name" => "name_2",
          },
        ),
      ]
    end

    it "reports zero space savings" do
      analyzer = described_class.new(unique_fonts)
      report = analyzer.analyze

      expect(report[:space_savings]).to eq(0)
      expect(report[:shared_tables]).to be_empty
    end
  end

  context "with all shared tables" do
    let(:shared_fonts) do
      [
        double(
          "truetype_font",
          table_names: %w[head name],
          table_data: {
            "head" => "shared_head",
            "name" => "shared_name",
          },
        ),
        double(
          "truetype_font",
          table_names: %w[head name],
          table_data: {
            "head" => "shared_head",
            "name" => "shared_name",
          },
        ),
      ]
    end

    it "reports maximum space savings" do
      analyzer = described_class.new(shared_fonts)
      report = analyzer.analyze

      expect(report[:space_savings]).to be > 0
      expect(report[:shared_tables].size).to eq(2)
      expect(report[:sharing_percentage]).to eq(100.0)
    end
  end
end
