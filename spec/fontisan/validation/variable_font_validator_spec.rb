# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Validation::VariableFontValidator do
  describe "#validate" do
    context "with non-variable font" do
      it "returns empty errors array" do
        font = create_static_font
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to be_empty
      end
    end

    context "with valid variable font" do
      it "returns no errors" do
        font = create_valid_variable_font
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to be_empty
      end
    end

    context "fvar structure validation" do
      it "detects missing axes" do
        fvar = double(axes: [], axis_count: 0)
        font = create_font_with_fvar(fvar)
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/fvar: No axes defined/))
      end

      it "detects axis count mismatch" do
        axes = [create_axis("wght")]
        fvar = double(axes: axes, axis_count: 2)
        font = create_font_with_fvar(fvar)
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/Axis count mismatch/))
      end
    end

    context "axis validation" do
      it "detects min > max" do
        axis = create_axis("wght", min: 700, max: 400, default: 400)
        fvar = double(axes: [axis], axis_count: 1, instances: [])
        font = create_font_with_fvar(fvar)
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/wght.*min_value.*max_value/))
      end

      it "detects default < min" do
        axis = create_axis("wght", min: 400, max: 700, default: 300)
        fvar = double(axes: [axis], axis_count: 1, instances: [])
        font = create_font_with_fvar(fvar)
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/wght.*default_value.*out of range/))
      end

      it "detects default > max" do
        axis = create_axis("wght", min: 400, max: 700, default: 800)
        fvar = double(axes: [axis], axis_count: 1, instances: [])
        font = create_font_with_fvar(fvar)
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/wght.*default_value.*out of range/))
      end

      it "detects invalid axis tag" do
        axis = create_axis("123", min: 400, max: 700, default: 400)
        fvar = double(axes: [axis], axis_count: 1, instances: [])
        font = create_font_with_fvar(fvar)
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/invalid tag/))
      end

      it "detects too short axis tag" do
        axis = create_axis("wgt", min: 400, max: 700, default: 400)
        fvar = double(axes: [axis], axis_count: 1, instances: [])
        font = create_font_with_fvar(fvar)
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/invalid tag/))
      end
    end

    context "instance validation" do
      it "detects coordinate count mismatch" do
        axes = [create_axis("wght"), create_axis("wdth")]
        instance = { coordinates: [400] } # Only 1 coord for 2 axes
        fvar = double(axes: axes, axis_count: 2, instances: [instance])
        font = create_font_with_fvar(fvar)
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/Instance 0.*coordinate count mismatch/))
      end

      it "detects coordinate out of range (below min)" do
        axes = [create_axis("wght", min: 400, max: 700, default: 400)]
        instance = { coordinates: [300] }
        fvar = double(axes: axes, axis_count: 1, instances: [instance])
        font = create_font_with_fvar(fvar)
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/Instance 0.*wght.*out of range/))
      end

      it "detects coordinate out of range (above max)" do
        axes = [create_axis("wght", min: 400, max: 700, default: 400)]
        instance = { coordinates: [800] }
        fvar = double(axes: axes, axis_count: 1, instances: [instance])
        font = create_font_with_fvar(fvar)
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/Instance 0.*wght.*out of range/))
      end
    end

    context "variation table validation" do
      it "detects missing gvar in TrueType variable font" do
        fvar = double(axes: [create_axis("wght")], axis_count: 1, instances: [])
        font = create_font_with_tables(
          fvar: fvar,
          glyf: true,
          gvar: false,
        )
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/TrueType.*missing gvar/))
      end

      it "detects missing CFF2 in CFF variable font" do
        fvar = double(axes: [create_axis("wght")], axis_count: 1, instances: [])
        font = create_font_with_tables(
          fvar: fvar,
          cff: true,
          cff2: false,
        )
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/CFF.*missing CFF2/))
      end

      it "detects both gvar and CFF2 present" do
        fvar = double(axes: [create_axis("wght")], axis_count: 1, instances: [])
        font = create_font_with_tables(
          fvar: fvar,
          gvar: true,
          cff2: true,
        )
        validator = described_class.new(font)
        errors = validator.validate

        expect(errors).to include(match(/both gvar and CFF2/))
      end
    end
  end

  # Helper methods
  def create_static_font
    font = double("Font")
    allow(font).to receive(:has_table?).and_return(false)
    font
  end

  def create_valid_variable_font
    axes = [
      create_axis("wght", min: 400, max: 700, default: 400),
      create_axis("wdth", min: 75, max: 100, default: 100),
    ]
    instances = [
      { coordinates: [400, 100] },
      { coordinates: [700, 100] },
    ]
    fvar = double(axes: axes, axis_count: 2, instances: instances)

    create_font_with_tables(
      fvar: fvar,
      glyf: true,
      gvar: true,
    )
  end

  def create_font_with_fvar(fvar_table)
    font = double("Font")
    # Setup has_table? to return true for fvar, false for everything else
    allow(font).to receive(:has_table?) do |tag|
      tag == "fvar"
    end
    # Setup table method
    allow(font).to receive(:table).with("fvar").and_return(fvar_table)
    allow(font).to receive(:table_data).and_return({})
    font
  end

  def create_font_with_tables(tables)
    font = double("Font")
    fvar = tables[:fvar]

    # Setup has_table? to respond based on tables hash
    allow(font).to receive(:has_table?) do |tag|
      case tag
      when "fvar" then !fvar.nil?
      when "glyf" then tables[:glyf] == true
      when "gvar" then tables[:gvar] == true
      when "CFF " then tables[:cff] == true
      when "CFF2" then tables[:cff2] == true
      else false
      end
    end

    # Setup table responses
    allow(font).to receive(:table).with("fvar").and_return(fvar)
    allow(font).to receive(:table_data).and_return({})

    font
  end

  def create_axis(tag, min: 400, max: 700, default: 400)
    double(
      "Axis",
      axis_tag: tag,
      min_value: min,
      max_value: max,
      default_value: default,
    )
  end
end
