# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Collection::Builder, "variable fonts" do
  let(:test_data_dir) { File.join(__dir__, "../../fixtures") }

  describe "variable font detection" do
    context "with variable fonts" do
      it "detects variable fonts in collection" do
        font = Fontisan::SpecHelpers::FakeFont.new({ "fvar" => "" })

        builder = described_class.new([font, font])
        expect(builder.variable_fonts_in_collection?).to be true
      end
    end

    context "without variable fonts" do
      it "returns false for static fonts" do
        font = Fontisan::SpecHelpers::FakeFont.new({ "head" => "" })

        builder = described_class.new([font, font])
        expect(builder.variable_fonts_in_collection?).to be false
      end
    end
  end

  describe "variation type validation" do
    context "with all TrueType variable fonts" do
      it "passes validation" do
        font1 = create_variable_ttf_mock
        font2 = create_variable_ttf_mock

        builder = described_class.new([font1, font2])
        expect { builder.validate_variation_compatibility! }.not_to raise_error
      end
    end

    context "with all CFF2 variable fonts" do
      it "passes validation" do
        font1 = create_variable_otf_mock
        font2 = create_variable_otf_mock

        builder = described_class.new([font1, font2])
        expect { builder.validate_variation_compatibility! }.not_to raise_error
      end
    end

    context "with mixed TrueType and CFF2 variable fonts" do
      it "raises error" do
        ttf_font = create_variable_ttf_mock
        otf_font = create_variable_otf_mock

        builder = described_class.new([ttf_font, otf_font])
        expect { builder.validate_variation_compatibility! }.to raise_error(
          Fontisan::Error,
          /Cannot mix TrueType and CFF2 variable fonts/,
        )
      end
    end
  end

  describe "axis validation" do
    context "with same axes" do
      it "passes validation" do
        axes = [
          double(axis_tag: "wght"),
          double(axis_tag: "wdth"),
        ]
        font1 = create_variable_font_mock_with_fvar(double("fvar", axes: axes))
        font2 = create_variable_font_mock_with_fvar(double("fvar", axes: axes))

        builder = described_class.new([font1, font2])
        expect { builder.validate_variation_compatibility! }.not_to raise_error
      end
    end

    context "with different axes" do
      it "raises error" do
        font1 = create_variable_font_mock_with_fvar(
          double("fvar", axes: [double(axis_tag: "wght"), double(axis_tag: "wdth")]),
        )
        font2 = create_variable_font_mock_with_fvar(
          double("fvar", axes: [double(axis_tag: "wght"), double(axis_tag: "slnt")]),
        )

        builder = described_class.new([font1, font2])
        expect { builder.validate_variation_compatibility! }.to raise_error(
          Fontisan::Error,
          /has different axes/,
        )
      end
    end

    context "with different number of axes" do
      it "raises error" do
        font1 = create_variable_font_mock_with_fvar(
          double("fvar", axes: [double(axis_tag: "wght")]),
        )
        font2 = create_variable_font_mock_with_fvar(
          double("fvar", axes: [double(axis_tag: "wght"), double(axis_tag: "wdth")]),
        )

        builder = described_class.new([font1, font2])
        expect { builder.validate_variation_compatibility! }.to raise_error(
          Fontisan::Error,
          /has different axes/,
        )
      end
    end
  end

  describe "validate!" do
    context "with variable fonts" do
      it "calls variation compatibility validation" do
        font1 = create_variable_ttf_mock_complete
        font2 = create_variable_ttf_mock_complete

        builder = described_class.new([font1, font2])
        expect(builder).to receive(:validate_variation_compatibility!)
        builder.validate!
      end
    end

    context "with static fonts" do
      it "skips variation validation for static fonts" do
        font1 = create_static_font_mock
        font2 = create_static_font_mock

        builder = described_class.new([font1, font2])
        expect(builder).not_to receive(:validate_variation_compatibility!)
        builder.validate!
      end
    end
  end

  # Helper methods
  def create_variable_ttf_mock
    fvar_table = double("fvar", axes: [])
    font = Fontisan::SpecHelpers::FakeFont.new({ "fvar" => "", "glyf" => "" })
    allow(font).to receive(:table).with("fvar").and_return(fvar_table)
    font
  end

  def create_variable_otf_mock
    fvar_table = double("fvar", axes: [])
    font = Fontisan::SpecHelpers::FakeFont.new({ "fvar" => "", "CFF2" => "" })
    allow(font).to receive(:table).with("fvar").and_return(fvar_table)
    font
  end

  def create_variable_font_mock_with_fvar(fvar_table)
    font = Fontisan::SpecHelpers::FakeFont.new({ "fvar" => "", "glyf" => "" })
    allow(font).to receive(:table).with("fvar").and_return(fvar_table)
    font
  end

  def create_variable_ttf_mock_complete
    axes = [double(axis_tag: "wght"), double(axis_tag: "wdth")]
    fvar = double(axes: axes)

    Fontisan::SpecHelpers::FakeFont.new(
      { "fvar" => "", "glyf" => "", "head" => "", "hhea" => "", "maxp" => "" },
      sfnt_version: 0x00010000,
    ).tap do |font|
      allow(font).to receive(:table).with("fvar").and_return(fvar)
    end
  end

  def create_static_font_mock
    Fontisan::SpecHelpers::FakeFont.new(
      { "head" => "", "hhea" => "", "maxp" => "" },
      sfnt_version: 0x00010000,
    )
  end
end
