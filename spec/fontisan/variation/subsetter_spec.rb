# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/subsetter"
require "fontisan/variation/validator"

RSpec.describe Fontisan::Variation::Subsetter do
  # Helper to create mock font with basic structure
  def create_mock_font(options = {})
    font = double("Font")

    tables = options[:tables] || ["fvar", "gvar", "maxp"]
    table_data = options[:table_data] || {}

    allow(font).to receive(:has_table?) { |tag| tables.include?(tag) }
    allow(font).to receive(:table) { |tag| table_data[tag] }
    allow(font).to receive(:table_data).and_return(options[:all_tables] || {})

    font
  end

  # Helper to create mock fvar
  def create_mock_fvar(axes: ["wght", "wdth"])
    fvar = double("Fvar")

    axis_objects = axes.map do |tag|
      axis = double("Axis")
      allow(axis).to receive_messages(axis_tag: tag, min_value: 100.0,
                                      default_value: 400.0, max_value: 900.0)
      axis
    end

    allow(fvar).to receive_messages(axis_count: axes.length,
                                    axes: axis_objects, instances: [])

    fvar
  end

  # Helper to create mock maxp
  def create_mock_maxp(num_glyphs: 100)
    double("Maxp", num_glyphs: num_glyphs)
  end

  describe "#initialize" do
    it "initializes with font and default options" do
      font = create_mock_font
      subsetter = described_class.new(font)

      expect(subsetter.font).to eq(font)
      expect(subsetter.options[:validate]).to be true
      expect(subsetter.options[:optimize]).to be true
    end

    it "accepts custom options" do
      font = create_mock_font
      subsetter = described_class.new(font, validate: false, optimize: false)

      expect(subsetter.options[:validate]).to be false
      expect(subsetter.options[:optimize]).to be false
    end

    it "creates a validator" do
      font = create_mock_font
      subsetter = described_class.new(font)

      expect(subsetter.validator).to be_a(Fontisan::Variation::Validator)
    end

    it "initializes with custom threshold" do
      font = create_mock_font
      subsetter = described_class.new(font, region_threshold: 0.001)

      expect(subsetter.options[:region_threshold]).to eq(0.001)
    end
  end

  describe "#subset_glyphs" do
    let(:font) do
      create_mock_font(
        table_data: {
          "fvar" => create_mock_fvar,
          "maxp" => create_mock_maxp(num_glyphs: 100),
        },
        all_tables: { "fvar" => "data", "maxp" => "data" },
      )
    end

    it "returns subset result with tables and report" do
      subsetter = described_class.new(font, validate: false)

      result = subsetter.subset_glyphs([0, 1, 2, 3])

      expect(result).to have_key(:tables)
      expect(result).to have_key(:report)
    end

    it "reports glyph counts" do
      subsetter = described_class.new(font, validate: false)

      result = subsetter.subset_glyphs([0, 1, 2])

      expect(result[:report][:operation]).to eq(:subset_glyphs)
      expect(result[:report][:original_glyph_count]).to eq(100)
      expect(result[:report][:subset_glyph_count]).to eq(3)
      expect(result[:report][:glyphs_removed]).to eq(97)
    end

    it "marks gvar as updated when present" do
      font_with_gvar = create_mock_font(
        tables: ["fvar", "gvar", "maxp"],
        table_data: {
          "fvar" => create_mock_fvar,
          "gvar" => double("Gvar"),
          "maxp" => create_mock_maxp,
        },
        all_tables: { "fvar" => "data", "gvar" => "data", "maxp" => "data" },
      )

      subsetter = described_class.new(font_with_gvar, validate: false)
      result = subsetter.subset_glyphs([0, 1])

      expect(result[:report][:gvar_updated]).to be true
    end

    it "marks CFF2 as updated when present" do
      font_with_cff2 = create_mock_font(
        tables: ["fvar", "CFF2", "maxp"],
        table_data: {
          "fvar" => create_mock_fvar,
          "CFF2" => double("CFF2"),
          "maxp" => create_mock_maxp,
        },
        all_tables: { "fvar" => "data", "CFF2" => "data", "maxp" => "data" },
      )

      subsetter = described_class.new(font_with_cff2, validate: false)
      result = subsetter.subset_glyphs([0, 1])

      expect(result[:report][:cff2_updated]).to be true
    end

    context "with validation enabled" do
      it "validates input font" do
        validator = instance_double(Fontisan::Variation::Validator)
        allow(Fontisan::Variation::Validator).to receive(:new).and_return(validator)
        allow(validator).to receive(:validate).and_return({ valid: true,
                                                            errors: [], warnings: [] })

        subsetter = described_class.new(font, validate: true)
        subsetter.subset_glyphs([0, 1])

        # Should validate at least once (may validate twice: input and output)
        expect(validator).to have_received(:validate).at_least(:once)
      end

      it "raises error for invalid input font" do
        validator = instance_double(Fontisan::Variation::Validator)
        allow(Fontisan::Variation::Validator).to receive(:new).and_return(validator)
        allow(validator).to receive(:validate).and_return({
                                                            valid: false,
                                                            errors: ["Missing fvar table"],
                                                            warnings: [],
                                                          })

        subsetter = described_class.new(font, validate: true)

        expect do
          subsetter.subset_glyphs([0, 1])
        end.to raise_error(/Invalid input font/)
      end
    end
  end

  describe "#subset_axes" do
    let(:font) do
      fvar = create_mock_fvar(axes: ["wght", "wdth", "slnt"])
      create_mock_font(
        tables: ["fvar"],
        table_data: { "fvar" => fvar },
        all_tables: { "fvar" => "data" },
      )
    end

    it "returns subset result" do
      subsetter = described_class.new(font, validate: false)

      result = subsetter.subset_axes(["wght", "wdth"])

      expect(result).to have_key(:tables)
      expect(result).to have_key(:report)
    end

    it "reports axis counts" do
      subsetter = described_class.new(font, validate: false)

      result = subsetter.subset_axes(["wght"])

      expect(result[:report][:operation]).to eq(:subset_axes)
      expect(result[:report][:original_axis_count]).to eq(3)
      expect(result[:report][:subset_axis_count]).to eq(1)
      expect(result[:report][:axes_removed]).to eq(2)
      expect(result[:report][:removed_axes]).to eq(["wdth", "slnt"])
    end

    it "handles missing fvar gracefully" do
      font_no_fvar = create_mock_font(
        tables: [],
        table_data: {},
        all_tables: {},
      )

      subsetter = described_class.new(font_no_fvar, validate: false)
      result = subsetter.subset_axes(["wght"])

      expect(result[:report]).to have_key(:error)
    end

    it "marks gvar as updated when present" do
      fvar = create_mock_fvar(axes: ["wght", "wdth"])
      font_with_gvar = create_mock_font(
        tables: ["fvar", "gvar"],
        table_data: {
          "fvar" => fvar,
          "gvar" => double("Gvar"),
        },
        all_tables: { "fvar" => "data", "gvar" => "data" },
      )

      subsetter = described_class.new(font_with_gvar, validate: false)
      result = subsetter.subset_axes(["wght"])

      expect(result[:report][:gvar_updated]).to be true
    end

    it "marks CFF2 as updated when present" do
      fvar = create_mock_fvar(axes: ["wght", "wdth"])
      font_with_cff2 = create_mock_font(
        tables: ["fvar", "CFF2"],
        table_data: {
          "fvar" => fvar,
          "CFF2" => double("CFF2"),
        },
        all_tables: { "fvar" => "data", "CFF2" => "data" },
      )

      subsetter = described_class.new(font_with_cff2, validate: false)
      result = subsetter.subset_axes(["wght"])

      expect(result[:report][:cff2_updated]).to be true
    end
  end

  describe "#simplify_regions" do
    let(:font) do
      fvar = create_mock_fvar
      create_mock_font(
        tables: ["fvar"],
        table_data: { "fvar" => fvar },
        all_tables: { "fvar" => "data" },
      )
    end

    it "returns simplification result" do
      subsetter = described_class.new(font, validate: false)

      result = subsetter.simplify_regions

      expect(result).to have_key(:tables)
      expect(result).to have_key(:report)
      expect(result[:report][:operation]).to eq(:simplify_regions)
    end

    it "uses default threshold from options" do
      subsetter = described_class.new(font, validate: false,
                                            region_threshold: 0.001)

      result = subsetter.simplify_regions

      expect(result[:report][:threshold]).to eq(0.001)
    end

    it "accepts custom threshold parameter" do
      subsetter = described_class.new(font, validate: false,
                                            region_threshold: 0.01)

      result = subsetter.simplify_regions(threshold: 0.005)

      expect(result[:report][:threshold]).to eq(0.005)
    end

    context "with CFF2 table" do
      it "optimizes CFF2 regions" do
        cff2 = double("CFF2")
        font_with_cff2 = create_mock_font(
          tables: ["fvar", "CFF2"],
          table_data: {
            "fvar" => create_mock_fvar,
            "CFF2" => cff2,
          },
          all_tables: { "fvar" => "data", "CFF2" => "data" },
        )

        # Mock optimizer
        optimizer = instance_double(Fontisan::Variation::Optimizer)
        allow(Fontisan::Variation::Optimizer).to receive(:new).and_return(optimizer)
        allow(optimizer).to receive_messages(optimize: cff2,
                                             stats: { regions_deduplicated: 5 })

        subsetter = described_class.new(font_with_cff2, validate: false)
        result = subsetter.simplify_regions

        expect(result[:report][:regions_deduplicated]).to eq(5)
        expect(result[:report][:cff2_optimized]).to be true
      end
    end
  end

  describe "#subset" do
    let(:font) do
      fvar = create_mock_fvar(axes: ["wght", "wdth"])
      create_mock_font(
        tables: ["fvar", "maxp"],
        table_data: {
          "fvar" => fvar,
          "maxp" => create_mock_maxp(num_glyphs: 100),
        },
        all_tables: { "fvar" => "data", "maxp" => "data" },
      )
    end

    it "performs combined subset operation" do
      subsetter = described_class.new(font, validate: false)

      result = subsetter.subset(glyphs: [0, 1, 2], axes: ["wght"],
                                simplify: false)

      expect(result).to have_key(:tables)
      expect(result).to have_key(:report)
      expect(result[:report][:operation]).to eq(:combined_subset)
    end

    it "records operation steps" do
      subsetter = described_class.new(font, validate: false)

      result = subsetter.subset(glyphs: [0, 1], axes: nil, simplify: false)

      expect(result[:report][:steps]).to be_an(Array)
      expect(result[:report][:steps].first[:step]).to eq(:subset_glyphs)
    end

    it "subsets glyphs when specified" do
      subsetter = described_class.new(font, validate: false)

      result = subsetter.subset(glyphs: [0, 1, 2], axes: nil, simplify: false)

      steps = result[:report][:steps]
      expect(steps.any? { |s| s[:step] == :subset_glyphs }).to be true
    end

    it "skips glyph subsetting when not specified" do
      subsetter = described_class.new(font, validate: false)

      result = subsetter.subset(glyphs: nil, axes: ["wght"], simplify: false)

      steps = result[:report][:steps]
      expect(steps.any? { |s| s[:step] == :subset_glyphs }).to be false
    end

    it "subsets axes when specified" do
      subsetter = described_class.new(font, validate: false)

      # Need to mock temp font creation for axis subsetting
      result = subsetter.subset(glyphs: nil, axes: ["wght"], simplify: false)

      steps = result[:report][:steps]
      expect(steps.any? { |s| s[:step] == :subset_axes }).to be true
    end

    it "skips axis subsetting when not specified" do
      subsetter = described_class.new(font, validate: false)

      result = subsetter.subset(glyphs: [0, 1], axes: nil, simplify: false)

      steps = result[:report][:steps]
      expect(steps.any? { |s| s[:step] == :subset_axes }).to be false
    end

    it "simplifies regions when requested and optimize enabled" do
      subsetter = described_class.new(font, validate: false, optimize: true)

      result = subsetter.subset(glyphs: nil, axes: nil, simplify: true)

      steps = result[:report][:steps]
      expect(steps.any? { |s| s[:step] == :simplify_regions }).to be true
    end

    it "skips simplification when optimize disabled" do
      subsetter = described_class.new(font, validate: false, optimize: false)

      result = subsetter.subset(glyphs: nil, axes: nil, simplify: true)

      steps = result[:report][:steps]
      expect(steps.any? { |s| s[:step] == :simplify_regions }).to be false
    end

    it "skips simplification when not requested" do
      subsetter = described_class.new(font, validate: false, optimize: true)

      result = subsetter.subset(glyphs: nil, axes: nil, simplify: false)

      steps = result[:report][:steps]
      expect(steps.any? { |s| s[:step] == :simplify_regions }).to be false
    end
  end

  describe "validation integration" do
    it "validates before subsetting when enabled" do
      font = create_mock_font(
        table_data: { "fvar" => create_mock_fvar },
        all_tables: { "fvar" => "data" },
      )

      validator = instance_double(Fontisan::Variation::Validator)
      allow(Fontisan::Variation::Validator).to receive(:new).and_return(validator)
      allow(validator).to receive(:validate).and_return({ valid: true,
                                                          errors: [], warnings: [] })

      subsetter = described_class.new(font, validate: true)
      subsetter.subset_glyphs([0, 1])

      expect(validator).to have_received(:validate).at_least(:once)
    end

    it "skips validation when disabled" do
      font = create_mock_font(
        table_data: { "maxp" => create_mock_maxp },
        all_tables: { "maxp" => "data" },
      )

      subsetter = described_class.new(font, validate: false)

      # Just verify no error is raised when validation is disabled
      expect { subsetter.subset_glyphs([0, 1]) }.not_to raise_error
    end
  end

  describe "report generation" do
    let(:font) do
      create_mock_font(
        table_data: { "maxp" => create_mock_maxp },
        all_tables: { "maxp" => "data" },
      )
    end

    it "stores report in subsetter" do
      subsetter = described_class.new(font, validate: false)

      subsetter.subset_glyphs([0, 1])

      expect(subsetter.report).to be_a(Hash)
      expect(subsetter.report[:operation]).to eq(:subset_glyphs)
    end

    it "updates report on each operation" do
      subsetter = described_class.new(font, validate: false)

      subsetter.subset_glyphs([0, 1])
      first_report = subsetter.report.dup

      subsetter.simplify_regions
      second_report = subsetter.report

      expect(second_report[:operation]).not_to eq(first_report[:operation])
    end
  end

  describe "error handling" do
    it "continues on non-critical errors during subsetting" do
      font = create_mock_font(
        tables: ["fvar", "gvar", "maxp"],
        table_data: {
          "fvar" => create_mock_fvar,
          "gvar" => double("Gvar"),
          "maxp" => create_mock_maxp,
        },
        all_tables: { "fvar" => "data", "gvar" => "data", "maxp" => "data" },
      )

      subsetter = described_class.new(font, validate: false)

      expect { subsetter.subset_glyphs([0, 1]) }.not_to raise_error
    end
  end

  describe "placeholder implementations" do
    let(:font) do
      create_mock_font(
        tables: ["fvar", "maxp"],
        table_data: {
          "fvar" => create_mock_fvar,
          "maxp" => create_mock_maxp,
        },
        all_tables: { "fvar" => "data", "maxp" => "data" },
      )
    end

    it "includes notes for unimplemented gvar subsetting" do
      font_with_gvar = create_mock_font(
        tables: ["fvar", "gvar", "maxp"],
        table_data: {
          "fvar" => create_mock_fvar,
          "gvar" => double("Gvar"),
          "maxp" => create_mock_maxp,
        },
        all_tables: { "fvar" => "data", "gvar" => "data", "maxp" => "data" },
      )

      subsetter = described_class.new(font_with_gvar, validate: false)
      result = subsetter.subset_glyphs([0, 1])

      expect(result[:report]).to have_key(:gvar_note)
    end

    it "includes notes for unimplemented CFF2 subsetting" do
      font_with_cff2 = create_mock_font(
        tables: ["fvar", "CFF2", "maxp"],
        table_data: {
          "fvar" => create_mock_fvar,
          "CFF2" => double("CFF2"),
          "maxp" => create_mock_maxp,
        },
        all_tables: { "fvar" => "data", "CFF2" => "data", "maxp" => "data" },
      )

      subsetter = described_class.new(font_with_cff2, validate: false)
      result = subsetter.subset_glyphs([0, 1])

      expect(result[:report]).to have_key(:cff2_note)
    end

    it "includes notes for unimplemented metrics subsetting" do
      font_with_hvar = create_mock_font(
        tables: ["fvar", "HVAR", "maxp"],
        table_data: {
          "fvar" => create_mock_fvar,
          "HVAR" => double("HVAR"),
          "maxp" => create_mock_maxp,
        },
        all_tables: { "fvar" => "data", "HVAR" => "data", "maxp" => "data" },
      )

      subsetter = described_class.new(font_with_hvar, validate: false)
      result = subsetter.subset_glyphs([0, 1])

      expect(result[:report]).to have_key(:hvar_note)
    end
  end
end
