# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Collection::Builder, "variable fonts" do
  let(:test_data_dir) { File.join(__dir__, "../../fixtures") }

  describe "variable font detection" do
    context "with variable fonts" do
      it "detects variable fonts in collection" do
        # Create mock variable font
        font = instance_double(Fontisan::TrueTypeFont)
        allow(font).to receive(:has_table?).with("fvar").and_return(true)
        allow(font).to receive(:table_data).and_return({})
        allow(font).to receive(:respond_to?).with(:table_data).and_return(true)

        builder = described_class.new([font, font])
        expect(builder.variable_fonts_in_collection?).to be true
      end
    end

    context "without variable fonts" do
      it "returns false for static fonts" do
        font = instance_double(Fontisan::TrueTypeFont)
        allow(font).to receive(:has_table?).with("fvar").and_return(false)
        allow(font).to receive(:table_data).and_return({})
        allow(font).to receive(:respond_to?).with(:table_data).and_return(true)

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
        fvar1 = double(axes: axes)
        fvar2 = double(axes: axes)

        font1 = create_variable_font_mock_with_fvar(fvar1)
        font2 = create_variable_font_mock_with_fvar(fvar2)

        builder = described_class.new([font1, font2])
        expect { builder.validate_variation_compatibility! }.not_to raise_error
      end
    end

    context "with different axes" do
      it "raises error" do
        axes1 = [double(axis_tag: "wght"), double(axis_tag: "wdth")]
        axes2 = [double(axis_tag: "wght"), double(axis_tag: "slnt")]
        fvar1 = double(axes: axes1)
        fvar2 = double(axes: axes2)

        font1 = create_variable_font_mock_with_fvar(fvar1)
        font2 = create_variable_font_mock_with_fvar(fvar2)

        builder = described_class.new([font1, font2])
        expect { builder.validate_variation_compatibility! }.to raise_error(
          Fontisan::Error,
          /has different axes/,
        )
      end
    end

    context "with different number of axes" do
      it "raises error" do
        axes1 = [double(axis_tag: "wght")]
        axes2 = [double(axis_tag: "wght"), double(axis_tag: "wdth")]
        fvar1 = double(axes: axes1)
        fvar2 = double(axes: axes2)

        font1 = create_variable_font_mock_with_fvar(fvar1)
        font2 = create_variable_font_mock_with_fvar(fvar2)

        builder = described_class.new([font1, font2])
        expect { builder.validate_variation_compatibility! }.to raise_error(
          Fontisan::Error,
          /has different axes/,
        )
      end
    end
  end

  describe "validate! with variable fonts" do
    it "calls variation compatibility validation" do
      font1 = create_variable_ttf_mock_complete
      font2 = create_variable_ttf_mock_complete

      builder = described_class.new([font1, font2])
      expect(builder).to receive(:validate_variation_compatibility!)
      builder.validate!
    end

    it "skips variation validation for static fonts" do
      font1 = create_static_font_mock
      font2 = create_static_font_mock

      builder = described_class.new([font1, font2])
      expect(builder).not_to receive(:validate_variation_compatibility!)
      builder.validate!
    end
  end

  # Helper methods
  def create_variable_ttf_mock
    fvar_table = double("fvar", axes: [])
    font = instance_double(Fontisan::TrueTypeFont)
    allow(font).to receive(:has_table?) do |tag|
      case tag
      when "fvar", "glyf" then true
      when "CFF2" then false
      else false
      end
    end
    allow(font).to receive(:table).with("fvar").and_return(fvar_table)
    allow(font).to receive(:table_data).and_return({})
    allow(font).to receive(:respond_to?).with(:table_data).and_return(true)
    font
  end

  def create_variable_otf_mock
    fvar_table = double("fvar", axes: [])
    font = instance_double(Fontisan::OpenTypeFont)
    allow(font).to receive(:has_table?) do |tag|
      case tag
      when "fvar", "CFF2" then true
      when "glyf" then false
      else false
      end
    end
    allow(font).to receive(:table).with("fvar").and_return(fvar_table)
    allow(font).to receive(:table_data).and_return({})
    allow(font).to receive(:respond_to?).with(:table_data).and_return(true)
    font
  end

  def create_variable_font_mock_with_fvar(fvar_table)
    font = instance_double(Fontisan::TrueTypeFont)
    allow(font).to receive(:has_table?) do |tag|
      case tag
      when "fvar", "glyf" then true
      when "CFF2" then false
      else false
      end
    end
    allow(font).to receive(:table).with("fvar").and_return(fvar_table)
    allow(font).to receive(:table_data).and_return({})
    allow(font).to receive(:respond_to?).with(:table_data).and_return(true)
    font
  end

  def create_variable_ttf_mock_complete
    axes = [double(axis_tag: "wght"), double(axis_tag: "wdth")]
    fvar = double(axes: axes)

    header = double(sfnt_version: 0x00010000)
    font = double("TrueTypeFont")

    allow(font).to receive(:has_table?) do |tag|
      %w[fvar glyf head hhea maxp].include?(tag)
    end
    allow(font).to receive(:table).with("fvar").and_return(fvar)
    allow(font).to receive_messages(header: header, table_data: {})
    allow(font).to receive(:respond_to?).with(:table_data).and_return(true)

    font
  end

  def create_static_font_mock
    header = double(sfnt_version: 0x00010000)
    font = double("TrueTypeFont")

    allow(font).to receive(:has_table?) do |tag|
      %w[head hhea maxp].include?(tag) && tag != "fvar"
    end
    allow(font).to receive_messages(header: header, table_data: {})
    allow(font).to receive(:respond_to?).with(:table_data).and_return(true)

    font
  end
end
