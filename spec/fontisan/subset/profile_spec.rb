# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Subset::Profile do
  describe ".for_name" do
    it "returns tables for pdf profile" do
      tables = described_class.for_name("pdf")
      expect(tables).to be_an(Array)
      expect(tables).to include("cmap", "head", "hhea", "hmtx", "maxp", "name",
                                "post", "loca", "glyf")
    end

    it "returns tables for web profile" do
      tables = described_class.for_name("web")
      expect(tables).to be_an(Array)
      expect(tables).to include("cmap", "head", "hhea", "hmtx", "maxp", "name",
                                "OS/2", "post", "loca", "glyf")
    end

    it "returns tables for minimal profile" do
      tables = described_class.for_name("minimal")
      expect(tables).to be_an(Array)
      expect(tables).to include("cmap", "head", "hhea", "hmtx", "maxp", "name",
                                "OS/2", "post")
      expect(tables).not_to include("loca", "glyf")
    end

    it "returns tables for full profile" do
      tables = described_class.for_name("full")
      expect(tables).to be_an(Array)
      expect(tables.size).to be > 20
    end

    it "is case-insensitive" do
      expect(described_class.for_name("PDF")).to eq(described_class.for_name("pdf"))
      expect(described_class.for_name("Web")).to eq(described_class.for_name("web"))
    end

    it "raises error for unknown profile" do
      expect do
        described_class.for_name("invalid_profile")
      end.to raise_error(ArgumentError, /Unknown profile/)
    end

    it "returns independent copies of arrays" do
      tables1 = described_class.for_name("pdf")
      tables2 = described_class.for_name("pdf")

      tables1 << "CUSTOM"
      expect(tables2).not_to include("CUSTOM")
    end
  end

  describe ".custom" do
    it "validates and returns custom table list" do
      custom_tables = ["cmap", "head", "maxp"]
      result = described_class.custom(custom_tables)
      expect(result).to eq(custom_tables)
    end

    it "returns independent copy of array" do
      custom_tables = ["cmap", "head", "maxp"]
      result = described_class.custom(custom_tables)

      result << "hhea"
      expect(custom_tables).not_to include("hhea")
    end

    it "raises error for unknown table tags" do
      expect do
        described_class.custom(["cmap", "invalid_table", "head"])
      end.to raise_error(ArgumentError, /Unknown table tags: invalid_table/)
    end

    it "raises error for multiple unknown tables" do
      expect do
        described_class.custom(["cmap", "invalid1", "invalid2"])
      end.to raise_error(ArgumentError,
                         /Unknown table tags: invalid1, invalid2/)
    end

    it "accepts string input" do
      result = described_class.custom("cmap")
      expect(result).to eq(["cmap"])
    end

    it "handles empty array" do
      result = described_class.custom([])
      expect(result).to eq([])
    end
  end

  describe ".known_table?" do
    it "returns true for known tables" do
      expect(described_class.known_table?("cmap")).to be true
      expect(described_class.known_table?("head")).to be true
      expect(described_class.known_table?("glyf")).to be true
      expect(described_class.known_table?("GSUB")).to be true
    end

    it "returns false for unknown tables" do
      expect(described_class.known_table?("invalid")).to be false
      expect(described_class.known_table?("test")).to be false
    end

    it "handles string conversion" do
      expect(described_class.known_table?(:cmap)).to be true
    end
  end

  describe ".valid_names" do
    it "returns array of valid profile names" do
      names = described_class.valid_names
      expect(names).to be_an(Array)
      expect(names).to include("pdf", "web", "minimal", "full")
    end

    it "returns sorted names" do
      names = described_class.valid_names
      expect(names).to eq(names.sort)
    end

    it "returns independent copy" do
      names1 = described_class.valid_names
      names2 = described_class.valid_names

      names1 << "custom"
      expect(names2).not_to include("custom")
    end
  end

  describe ".description" do
    it "returns description for pdf profile" do
      desc = described_class.description("pdf")
      expect(desc).to be_a(String)
      expect(desc).to match(/PDF/i)
    end

    it "returns description for web profile" do
      desc = described_class.description("web")
      expect(desc).to be_a(String)
      expect(desc).to match(/web/i)
    end

    it "returns nil for unknown profile" do
      desc = described_class.description("invalid")
      expect(desc).to be_nil
    end

    it "is case-insensitive" do
      expect(described_class.description("PDF")).to eq(described_class.description("pdf"))
    end
  end

  describe "YAML configuration loading" do
    it "loads profiles from YAML file" do
      # This implicitly tests YAML loading
      tables = described_class.for_name("pdf")
      expect(tables).to be_an(Array)
      expect(tables).not_to be_empty
    end

    it "caches loaded profiles" do
      # Call twice to test caching
      tables1 = described_class.for_name("pdf")
      tables2 = described_class.for_name("pdf")

      expect(tables1).to eq(tables2)
    end

    it "handles missing configuration file" do
      # Temporarily mock the config path
      allow(File).to receive(:join).and_call_original
      allow(File).to receive(:join).with(anything,
                                         "../config/subset_profiles.yml")
        .and_return("/nonexistent/path.yml")

      # Clear cache to force reload
      described_class.send(:clear_cache!)

      expect do
        described_class.for_name("pdf")
      end.to raise_error(Fontisan::Error,
                         /Profile configuration file not found/)

      # Restore for other tests
      described_class.send(:clear_cache!)
    end
  end

  describe "constants" do
    it "defines KNOWN_TABLES" do
      expect(described_class::KNOWN_TABLES).to be_an(Array)
      expect(described_class::KNOWN_TABLES).to be_frozen
    end

    it "includes common tables in KNOWN_TABLES" do
      tables = described_class::KNOWN_TABLES
      expect(tables).to include("cmap", "head", "hhea", "hmtx", "maxp", "name",
                                "post")
      expect(tables).to include("glyf", "loca", "OS/2")
      expect(tables).to include("GSUB", "GPOS", "GDEF")
    end
  end

  describe "profile completeness" do
    it "pdf profile has minimum required tables" do
      tables = described_class.for_name("pdf")
      required = %w[cmap head hhea hmtx maxp name post]
      required.each do |table|
        expect(tables).to include(table),
                          "PDF profile missing required table: #{table}"
      end
    end

    it "web profile has browser compatibility tables" do
      tables = described_class.for_name("web")
      web_required = %w[cmap head hhea hmtx maxp name OS/2 post]
      web_required.each do |table|
        expect(tables).to include(table),
                          "Web profile missing required table: #{table}"
      end
    end

    it "minimal profile has absolute minimum tables" do
      tables = described_class.for_name("minimal")
      minimal_required = %w[cmap head hhea hmtx maxp]
      minimal_required.each do |table|
        expect(tables).to include(table),
                          "Minimal profile missing required table: #{table}"
      end
    end
  end
end
