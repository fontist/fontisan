# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/validator"

module ValidatorSpecFakes
  FakeAxis = Struct.new(:axis_tag, :min_value, :default_value, :max_value,
                        keyword_init: true)

  FakeFvar = Struct.new(:axes, :instances, keyword_init: true) do
    def axis_count = axes.length
  end

  FakeGvar = Struct.new(:axis_count, :glyph_count, :shared_tuples,
                        :glyph_data, keyword_init: true) do
    def glyph_variation_data(gid)
      glyph_data&.dig(gid)
    end
  end

  FakeMaxp = Struct.new(:num_glyphs, keyword_init: true)
  FakeCff2 = Struct.new(:num_axes, keyword_init: true)

  FakeHvar = Struct.new(:item_variation_store, keyword_init: true)

  FakeStore = Struct.new(:variation_region_list, :item_variation_data_entries,
                         keyword_init: true)

  FakeRegionList = Struct.new(:axis_count, :regions, keyword_init: true)

  FakeRegionAxis = Struct.new(:start_coord, :peak_coord, :end_coord,
                              keyword_init: true)

  def self.build_font(tables: [], table_data: {})
    Fontisan::SpecHelpers::FakeFont.new(table_data).tap do |font|
      # FakeFont uses tables_hash keys for has_table?, so we only need
      # table_data keys to be present. If tables: arg is provided but
      # table_data: isn't, ensure has_table? returns false for everything.
      tables.each do |tag|
        font.tables_hash[tag] ||= nil
      end
      table_data.each do |tag, data|
        font.tables_hash[tag] = data
      end
    end
  end

  def self.build_fvar(axis_count: 2, instance_count: 0)
    axes = Array.new(axis_count) do |i|
      FakeAxis.new(axis_tag: "ax#{i}", min_value: 100.0,
                   default_value: 400.0, max_value: 900.0)
    end

    instances = Array.new(instance_count) do |i|
      {
        name_id: i + 256,
        flags: 0,
        coordinates: Array.new(axis_count) { 400.0 + (i * 100.0) },
        postscript_name_id: nil,
      }
    end

    FakeFvar.new(axes: axes, instances: instances)
  end

  def self.build_gvar(axis_count: 2, glyph_count: 100)
    glyph_data = Array.new(glyph_count) { |_gid| "data" }
    FakeGvar.new(axis_count: axis_count, glyph_count: glyph_count,
                 shared_tuples: [], glyph_data: glyph_data)
  end
end

RSpec.describe Fontisan::Variation::Validator do
  def create_mock_font(options = {})
    ValidatorSpecFakes.build_font(**options)
  end

  def create_mock_fvar(axis_count: 2, instance_count: 0)
    ValidatorSpecFakes.build_fvar(axis_count: axis_count, instance_count: instance_count)
  end

  def create_mock_gvar(axis_count: 2, glyph_count: 100)
    ValidatorSpecFakes.build_gvar(axis_count: axis_count, glyph_count: glyph_count)
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
        font = create_mock_font
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be false
        expect(result[:errors]).to include(/Missing required 'fvar' table/)
      end
    end

    context "with invalid fvar" do
      it "returns error when fvar has no axes" do
        fvar = create_mock_fvar(axis_count: 0)
        font = create_mock_font(table_data: { "fvar" => fvar })
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
        maxp = ValidatorSpecFakes::FakeMaxp.new(num_glyphs: 100)

        font = create_mock_font(
          table_data: { "fvar" => fvar, "gvar" => gvar, "maxp" => maxp },
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
      font = create_mock_font(table_data: { "fvar" => fvar })
      validator = described_class.new(font)

      expect(validator.valid?).to be true
    end

    it "returns false for invalid font" do
      font = create_mock_font
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
          table_data: { "fvar" => fvar, "gvar" => gvar },
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
          table_data: { "fvar" => fvar, "gvar" => gvar },
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be true
      end
    end

    context "with CFF2" do
      it "detects axis count mismatch" do
        fvar = create_mock_fvar(axis_count: 2)
        cff2 = ValidatorSpecFakes::FakeCff2.new(num_axes: 3)

        font = create_mock_font(
          table_data: { "fvar" => fvar, "CFF2" => cff2 },
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

        font = create_mock_font(table_data: { "fvar" => fvar })
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

      region_list = ValidatorSpecFakes::FakeRegionList.new(axis_count: 3)
      store = ValidatorSpecFakes::FakeStore.new(variation_region_list: region_list,
                                                item_variation_data_entries: [])
      hvar = ValidatorSpecFakes::FakeHvar.new(item_variation_store: store)

      font = create_mock_font(
        table_data: { "fvar" => fvar, "HVAR" => hvar },
      )
      validator = described_class.new(font)

      result = validator.validate

      expect(result[:valid]).to be false
      expect(result[:errors]).to include(/HVAR region axis count.*doesn't match fvar/)
    end

    it "handles missing region list gracefully" do
      fvar = create_mock_fvar(axis_count: 2)
      store = ValidatorSpecFakes::FakeStore.new(variation_region_list: nil,
                                                item_variation_data_entries: [])
      hvar = ValidatorSpecFakes::FakeHvar.new(item_variation_store: store)

      font = create_mock_font(
        table_data: { "fvar" => fvar, "HVAR" => hvar },
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
        maxp = ValidatorSpecFakes::FakeMaxp.new(num_glyphs: 100)

        font = create_mock_font(
          table_data: { "fvar" => fvar, "gvar" => gvar, "maxp" => maxp },
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be false
        expect(result[:errors]).to include(/gvar glyph count.*doesn't match maxp/)
      end

      it "warns when first glyph has no variation data" do
        fvar = create_mock_fvar
        gvar = create_mock_gvar
        gvar.glyph_data[0] = nil
        maxp = ValidatorSpecFakes::FakeMaxp.new(num_glyphs: 100)

        font = create_mock_font(
          table_data: { "fvar" => fvar, "gvar" => gvar, "maxp" => maxp },
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/First glyph has no variation data/)
      end

      it "warns when last glyph has no variation data" do
        fvar = create_mock_fvar
        gvar = create_mock_gvar(glyph_count: 100)
        gvar.glyph_data[99] = nil
        maxp = ValidatorSpecFakes::FakeMaxp.new(num_glyphs: 100)

        font = create_mock_font(
          table_data: { "fvar" => fvar, "gvar" => gvar, "maxp" => maxp },
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/Last glyph has no variation data/)
      end
    end

    context "with HVAR" do
      it "warns when HVAR has no item variation store" do
        fvar = create_mock_fvar
        hvar = ValidatorSpecFakes::FakeHvar.new(item_variation_store: nil)

        font = create_mock_font(
          table_data: { "fvar" => fvar, "HVAR" => hvar },
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/HVAR has no item variation store/)
      end

      it "warns when HVAR has no variation data" do
        fvar = create_mock_fvar
        store = ValidatorSpecFakes::FakeStore.new(
          variation_region_list: nil,
          item_variation_data_entries: [],
        )
        hvar = ValidatorSpecFakes::FakeHvar.new(item_variation_store: store)

        font = create_mock_font(
          table_data: { "fvar" => fvar, "HVAR" => hvar },
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
        gvar.shared_tuples = [
          [1.5, 0.5],  # First coord out of range
          [0.5, -1.5], # Second coord out of range
        ]

        font = create_mock_font(
          table_data: { "fvar" => fvar, "gvar" => gvar },
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/gvar shared tuple.*out of range/)
      end

      it "passes when shared tuples are in valid range" do
        fvar = create_mock_fvar(axis_count: 2)
        gvar = create_mock_gvar(axis_count: 2)
        gvar.shared_tuples = [
          [0.5, 0.8],
          [-0.5, 1.0],
        ]

        font = create_mock_font(
          table_data: { "fvar" => fvar, "gvar" => gvar },
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:valid]).to be true
      end
    end

    context "with metrics tables" do
      it "warns when HVAR region coordinates are out of range" do
        fvar = create_mock_fvar(axis_count: 1)

        region_axis = ValidatorSpecFakes::FakeRegionAxis.new(
          start_coord: -1.0, peak_coord: 2.0, end_coord: 1.0,
        )
        region = [region_axis]
        region_list = ValidatorSpecFakes::FakeRegionList.new(
          axis_count: 1, regions: [region],
        )
        store = ValidatorSpecFakes::FakeStore.new(
          variation_region_list: region_list,
          item_variation_data_entries: [],
        )
        hvar = ValidatorSpecFakes::FakeHvar.new(item_variation_store: store)

        font = create_mock_font(
          table_data: { "fvar" => fvar, "HVAR" => hvar },
        )
        validator = described_class.new(font)

        result = validator.validate

        expect(result[:warnings]).to include(/HVAR region.*out of range/)
      end
    end
  end
end
