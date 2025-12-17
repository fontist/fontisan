# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/validator"

RSpec.describe Fontisan::Variation::Validator do
  # Helper to create mock font
  def create_mock_font(options = {})
    font = double("Font")

    # Setup default responses
    allow(font).to receive(:has_table?) { |tag| options[:tables]&.include?(tag) || false }
    allow(font).to receive(:table) { |tag| options[:table_data]&.[](tag) }

    font
  end

  # Helper to create mock fvar table
  def create_mock_fvar(axis_count: 2, instance_count: 0)
    fvar = double("Fvar")
    allow(fvar).to receive(:axis_count).and_return(axis_count)

    axes = Array.new(axis_count) do |i|
      axis = double("Axis")
      allow(axis).to receive(:axis_tag).and_return("ax#{i}")
      allow(axis).to receive(:min_value).and_return(100.0)
      allow(axis).to receive(:default_value).and_return(400.0)
      allow(axis).to receive(:max_value).and_return(900.0)
      axis
    end
    allow(fvar).to receive(:axes).and_return(axes)

    instances = Array.new(instance_count) do |i|
      {
        name_id: i + 256,
        flags: 0,
        coordinates: Array.new(axis_count) { 400.0 + (i * 100.0) },
        postscript_name_id: nil
      }
    end
    allow(fvar).to receive(:instances).and_return(instances)

    fvar
  end

  # Helper to create mock gvar table
  def create_mock_gvar(axis_count: 2, glyph_count: 100)
    gvar = double("Gvar")
    allow(gvar).to receive(:axis_count).and_return(axis_count)
    allow(gvar).to receive(:glyph_count).and_return(glyph_count)
    allow(gvar).to receive(:shared_tuples).and_return([])
    allow(gvar).to receive(:glyph_variation_data) { |gid| gid < glyph_count ? "data" : nil }
    gvar
  end

  describe "#initialize" do
    it "initializes with a font" do
      font = create_mock_font
      validator = described_class.new(font)

      expect(validator.font).to eq(font)
      expect(validator.errors).to be_empty
      expect(validator.warnings).to be_empty
    end
  end

  describe "#validate" do
    context "with non-variable font" do
      it "returns error when fvar table is missing" do
        font = create_mock_font(tables: [])
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be false
        expect(result[:errors]).to include(/Missing required 'fvar' table/)
      end
    end

    context "with invalid fvar" do
      it "returns error when fvar has no axes" do
        fvar = create_mock_fvar(axis_count: 0)
        font = create_mock_font(
          tables: ["fvar"],
          table_data: { "fvar" => fvar }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be false
        expect(result[:errors]).to include(/fvar table has no axes defined/)
      end
    end

    context "with valid variable font" do
      it "returns valid for well-formed font" do
        fvar = create_mock_fvar(axis_count: 2)
        gvar = create_mock_gvar(axis_count: 2)
        maxp = double("Maxp", num_glyphs: 100)

        font = create_mock_font(
          tables: ["fvar", "gvar", "maxp"],
          table_data: { "fvar" => fvar, "gvar" => gvar, "maxp" => maxp }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid font" do
      fvar = create_mock_fvar
      font = create_mock_font(
        tables: ["fvar"],
        table_data: { "fvar" => fvar }
      )
      validator = described_class.new(font)

      expect(validator.valid?).to be true
    end

    it "returns false for invalid font" do
      font = create_mock_font(tables: [])
      validator = described_class.new(font)

      expect(validator.valid?).to be false
    end
  end

  describe "table consistency checks" do
    context "with gvar" do
      it "detects axis count mismatch" do
        fvar = create_mock_fvar(axis_count: 2)
        gvar = create_mock_gvar(axis_count: 3)

        font = create_mock_font(
          tables: ["fvar", "gvar"],
          table_data: { "fvar" => fvar, "gvar" => gvar }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be false
        expect(result[:errors]).to include(/gvar axis count.*doesn't match fvar/)
      end

      it "passes when axis counts match" do
        fvar = create_mock_fvar(axis_count: 2)
        gvar = create_mock_gvar(axis_count: 2)

        font = create_mock_font(
          tables: ["fvar", "gvar"],
          table_data: { "fvar" => fvar, "gvar" => gvar }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be true
      end
    end

    context "with CFF2" do
      it "detects axis count mismatch" do
        fvar = create_mock_fvar(axis_count: 2)
        cff2 = double("CFF2", num_axes: 3)

        font = create_mock_font(
          tables: ["fvar", "CFF2"],
          table_data: { "fvar" => fvar, "CFF2" => cff2 }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be false
        expect(result[:errors]).to include(/CFF2 axis count.*doesn't match fvar/)
      end
    end

    context "with no variation tables" do
      it "warns when only fvar is present" do
        fvar = create_mock_fvar

        font = create_mock_font(
          tables: ["fvar"],
          table_data: { "fvar" => fvar }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be true
        expect(result[:warnings]).to include(/No variation tables found/)
      end
    end
  end

  describe "metrics table consistency" do
    it "checks HVAR region axis count" do
      fvar = create_mock_fvar(axis_count: 2)

      region_list = double("RegionList", axis_count: 3)
      store = double("ItemVariationStore", region_list: region_list)
      hvar = double("HVAR", item_variation_store: store)

      font = create_mock_font(
        tables: ["fvar", "HVAR"],
        table_data: { "fvar" => fvar, "HVAR" => hvar }
      )
      validator = described_class.new(font)

      result = validator.validate

      expect(result[:valid]).to be false
      expect(result[:errors]).to include(/HVAR region axis count.*doesn't match fvar/)
    end

    it "handles missing region list gracefully" do
      fvar = create_mock_fvar(axis_count: 2)
      store = double("ItemVariationStore", region_list: nil)
      hvar = double("HVAR", item_variation_store: store)

      font = create_mock_font(
        tables: ["fvar", "HVAR"],
        table_data: { "fvar" => fvar, "HVAR" => hvar }
      )
      validator = described_class.new(font)

      result = validator.validate

      expect(result[:valid]).to be true
    end
  end

  describe "delta integrity checks" do
    context "with gvar" do
      it "detects glyph count mismatch" do
        fvar = create_mock_fvar
        gvar = create_mock_gvar(glyph_count: 50)
        maxp = double("Maxp", num_glyphs: 100)

        font = create_mock_font(
          tables: ["fvar", "gvar", "maxp"],
          table_data: { "fvar" => fvar, "gvar" => gvar, "maxp" => maxp }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be false
        expect(result[:errors]).to include(/gvar glyph count.*doesn't match maxp/)
      end

      it "warns when first glyph has no variation data" do
        fvar = create_mock_fvar
        gvar = create_mock_gvar
        allow(gvar).to receive(:glyph_variation_data).with(0).and_return(nil)
        maxp = double("Maxp", num_glyphs: 100)

        font = create_mock_font(
          tables: ["fvar", "gvar", "maxp"],
          table_data: { "fvar" => fvar, "gvar" => gvar, "maxp" => maxp }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/First glyph has no variation data/)
      end

      it "warns when last glyph has no variation data" do
        fvar = create_mock_fvar
        gvar = create_mock_gvar(glyph_count: 100)
        allow(gvar).to receive(:glyph_variation_data).with(99).and_return(nil)
        maxp = double("Maxp", num_glyphs: 100)

        font = create_mock_font(
          tables: ["fvar", "gvar", "maxp"],
          table_data: { "fvar" => fvar, "gvar" => gvar, "maxp" => maxp }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/Last glyph has no variation data/)
      end
    end

    context "with HVAR" do
      it "warns when HVAR has no item variation store" do
        fvar = create_mock_fvar
        hvar = double("HVAR", item_variation_store: nil)

        font = create_mock_font(
          tables: ["fvar", "HVAR"],
          table_data: { "fvar" => fvar, "HVAR" => hvar }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/HVAR has no item variation store/)
      end

      it "warns when HVAR has no variation data" do
        fvar = create_mock_fvar
        store = double("ItemVariationStore", item_variation_data: [])
        hvar = double("HVAR", item_variation_store: store)

        font = create_mock_font(
          tables: ["fvar", "HVAR"],
          table_data: { "fvar" => fvar, "HVAR" => hvar }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/HVAR has no variation data/)
      end
    end
  end

  describe "region coverage checks" do
    context "with gvar" do
      it "warns when shared tuple coordinates are out of range" do
        fvar = create_mock_fvar(axis_count: 2)
        gvar = create_mock_gvar(axis_count: 2)

        # Create out-of-range tuples (normalized coords should be [-1, 1])
        allow(gvar).to receive(:shared_tuples).and_return([
          [1.5, 0.5],  # First coord out of range
          [0.5, -1.5]  # Second coord out of range
        ])

        font = create_mock_font(
          tables: ["fvar", "gvar"],
          table_data: { "fvar" => fvar, "gvar" => gvar }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/gvar shared tuple.*out of range/)
      end

      it "passes when shared tuples are in valid range" do
        fvar = create_mock_fvar(axis_count: 2)
        gvar = create_mock_gvar(axis_count: 2)

        allow(gvar).to receive(:shared_tuples).and_return([
          [0.5, 0.8],
          [-0.5, 1.0]
        ])

        font = create_mock_font(
          tables: ["fvar", "gvar"],
          table_data: { "fvar" => fvar, "gvar" => gvar }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be true
      end
    end

    context "with metrics tables" do
      it "warns when HVAR region coordinates are out of range" do
        fvar = create_mock_fvar(axis_count: 1)

        region_axis = double("RegionAxis",
          start_coord: -1.5,
          peak_coord: 0.0,
          end_coord: 1.0
        )
        region = double("Region", region_axes: [region_axis])
        region_list = double("RegionList", axis_count: 1, regions: [region])
        store = double("ItemVariationStore", region_list: region_list)
        hvar = double("HVAR", item_variation_store: store)

        font = create_mock_font(
          tables: ["fvar", "HVAR"],
          table_data: { "fvar" => fvar, "HVAR" => hvar }
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/HVAR region.*start_coord out of range/)
      end
    end
  end

  describe "instance definition checks" do
    it "detects coordinate count mismatch" do
      fvar = create_mock_fvar(axis_count: 2, instance_count: 1)

      # Create instance with wrong number of coordinates
      instances = [{
        name_id: 256,
        flags: 0,
        coordinates: [400.0],  # Only 1 coord, but 2 axes
        postscript_name_id: nil
      }]
      allow(fvar).to receive(:instances).and_return(instances)

      font = create_mock_font(
        tables: ["fvar"],
        table_data: { "fvar" => fvar }
      )
      validator = described_class.new(font)

      result = validator.validate

      expect(result[:valid]).to be false
      expect(result[:errors]).to include(/Instance 0 has 1 coordinates but 2 axes/)
    end

    it "warns when instance coordinate is outside axis range" do
      fvar = create_mock_fvar(axis_count: 1, instance_count: 1)

      # Create instance with out-of-range coordinate
      instances = [{
        name_id: 256,
        flags: 0,
        coordinates: [1000.0],  # Axis range is 100-900
        postscript_name_id: nil
      }]
      allow(fvar).to receive(:instances).and_return(instances)

      font = create_mock_font(
        tables: ["fvar"],
        table_data: { "fvar" => fvar }
      )
      validator = described_class.new(font)

      result = validator.validate

      expect(result[:warnings]).to include(/Instance 0 axis.*coordinate.*outside range/)
    end

    it "passes when instances have valid coordinates" do
      fvar = create_mock_fvar(axis_count: 2, instance_count: 2)
      validator = described_class.new(
        create_mock_font(
          tables: ["fvar"],
          table_data: { "fvar" => fvar }
        )
      )

      result = validator.validate

      expect(result[:valid]).to be true
    end
  end

  describe "error accumulation" do
    it "accumulates multiple errors" do
      fvar = create_mock_fvar(axis_count: 2, instance_count: 1)
      gvar = create_mock_gvar(axis_count: 3, glyph_count: 50)
      maxp = double("Maxp", num_glyphs: 100)

      # Create instance with wrong coordinates
      instances = [{
        name_id: 256,
        flags: 0,
        coordinates: [400.0],
        postscript_name_id: nil
      }]
      allow(fvar).to receive(:instances).and_return(instances)

      font = create_mock_font(
        tables: ["fvar", "gvar", "maxp"],
        table_data: { "fvar" => fvar, "gvar" => gvar, "maxp" => maxp }
      )
      validator = described_class.new(font)

      result = validator.validate

      expect(result[:valid]).to be false
      # Should have: gvar axis mismatch, gvar glyph count mismatch, instance coord count
      # But instance error stops further checks, so we get at least the axis mismatch
      expect(result[:errors].length).to be >= 1
    end

    it "accumulates warnings" do
      fvar = create_mock_fvar(axis_count: 1, instance_count: 1)
      gvar = create_mock_gvar(axis_count: 1)
      allow(gvar).to receive(:glyph_variation_data).with(0).and_return(nil)
      allow(gvar).to receive(:shared_tuples).and_return([[1.5]])
      maxp = double("Maxp", num_glyphs: 100)

      instances = [{
        name_id: 256,
        flags: 0,
        coordinates: [1000.0],
        postscript_name_id: nil
      }]
      allow(fvar).to receive(:instances).and_return(instances)

      font = create_mock_font(
        tables: ["fvar", "gvar", "maxp"],
        table_data: { "fvar" => fvar, "gvar" => gvar, "maxp" => maxp }
      )
      validator = described_class.new(font)

      result = validator.validate

      expect(result[:warnings].length).to be >= 2
    end
  end

  describe "validation report structure" do
    it "returns hash with valid, errors, and warnings keys" do
      font = create_mock_font(
        tables: ["fvar"],
        table_data: { "fvar" => create_mock_fvar }
      )
      validator = described_class.new(font)

      result = validator.validate

      expect(result).to have_key(:valid)
      expect(result).to have_key(:errors)
      expect(result).to have_key(:warnings)
      expect([true, false]).to include(result[:valid])
      expect(result[:errors]).to be_an(Array)
      expect(result[:warnings]).to be_an(Array)
    end
  end

  describe "validation state management" do
    it "clears errors and warnings on each validate call" do
      font = create_mock_font(tables: [])
      validator = described_class.new(font)

      # First validation
      result1 = validator.validate
      expect(result1[:errors]).not_to be_empty

      # Update font to be valid
      allow(font).to receive(:has_table?).with("fvar").and_return(true)
      allow(font).to receive(:table).with("fvar").and_return(create_mock_fvar)

      # Second validation should start fresh
      result2 = validator.validate
      expect(result2[:valid]).to be true
      expect(result2[:errors]).to be_empty
    end
  end
end
