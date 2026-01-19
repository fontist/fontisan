# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Fontisan::Converters::Type1Converter do
  let(:converter) { described_class.new }

  describe "#extract_conversion_options" do
    it "extracts ConversionOptions from options hash" do
      conv_options = Fontisan::ConversionOptions.new(from: :type1, to: :otf)
      options = { options: conv_options }

      result = converter.send(:extract_conversion_options, options)

      expect(result).to eq(conv_options)
    end

    it "returns nil when no ConversionOptions provided" do
      options = { target_format: :otf }

      result = converter.send(:extract_conversion_options, options)

      expect(result).to be_nil
    end

    it "returns ConversionOptions when passed directly" do
      conv_options = Fontisan::ConversionOptions.new(from: :type1, to: :otf)

      result = converter.send(:extract_conversion_options, conv_options)

      expect(result).to eq(conv_options)
    end
  end

  describe "#apply_opening_options" do
    let(:mock_charstrings) { instance_double(Fontisan::Type1::CharStrings) }
    let(:mock_font_dictionary) { instance_double(Object) }
    let(:mock_font) do
      instance_double(Fontisan::Type1Font,
                     charstrings: mock_charstrings,
                     font_dictionary: mock_font_dictionary)
    end

    before do
      allow(mock_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      # Stub the methods to call the original (no-op) implementation
      allow(converter).to receive(:generate_unicode_mappings) { |font| nil }
      allow(converter).to receive(:decompose_seac_glyphs) { |font| nil }
    end

    it "applies generate_unicode option when set" do
      conv_options = Fontisan::ConversionOptions.new(
        from: :type1,
        to: :otf,
        opening: { generate_unicode: true }
      )

      expect(converter).to receive(:generate_unicode_mappings).with(mock_font)

      converter.send(:apply_opening_options, mock_font, conv_options)
    end

    it "applies decompose_composites option when set" do
      conv_options = Fontisan::ConversionOptions.new(
        from: :type1,
        to: :otf,
        opening: { decompose_composites: true }
      )

      expect(converter).to receive(:decompose_seac_glyphs).with(mock_font)

      converter.send(:apply_opening_options, mock_font, conv_options)
    end

    it "skips opening options when not set" do
      conv_options = Fontisan::ConversionOptions.new(
        from: :type1,
        to: :otf,
        opening: {}
      )

      # Just verify it runs without error
      expect {
        converter.send(:apply_opening_options, mock_font, conv_options)
      }.not_to raise_error
    end

    it "skips opening options when conv_options is nil" do
      # Just verify it runs without error
      expect {
        converter.send(:apply_opening_options, mock_font, nil)
      }.not_to raise_error
    end
  end

  describe "#convert with ConversionOptions" do
    let(:mock_font) do
      # Use a stub that responds to is_a? properly
      font = double("Type1Font")
      allow(font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      allow(font).to receive(:is_a?).with(Fontisan::OpenTypeFont).and_return(false)
      allow(font).to receive(:is_a?).with(Fontisan::TrueTypeFont).and_return(false)
      allow(font).to receive(:is_a?).with(Fontisan::WoffFont).and_return(false)
      allow(font).to receive(:is_a?).with(Fontisan::Woff2Font).and_return(false)
      allow(font).to receive(:class).and_return(Fontisan::Type1Font)
      font
    end

    before do
      # Stub detect_format to return :type1 (called before validate)
      allow(converter).to receive(:detect_format).and_return(:type1)
      # Stub validate to prevent errors
      allow(converter).to receive(:validate).and_return(nil)
      # Stub apply_opening_options to prevent actual option processing
      allow(converter).to receive(:apply_opening_options).and_return(nil)
      # Stub conversion methods
      allow(converter).to receive(:convert_type1_to_otf).and_return({})
      allow(converter).to receive(:convert_type1_to_ttf).and_return({})
    end

    context "target format detection" do
      it "extracts ConversionOptions from options hash" do
        conv_options = Fontisan::ConversionOptions.new(from: :type1, to: :otf)
        options = { options: conv_options }

        expect {
          converter.convert(mock_font, options)
        }.not_to raise_error
      end

      it "uses ConversionOptions target format when not specified in options" do
        conv_options = Fontisan::ConversionOptions.new(from: :type1, to: :ttf)
        options = { options: conv_options }

        # When target is TTF, convert_type1_to_ttf is called with the ConversionOptions
        expect(converter).to receive(:convert_type1_to_ttf).with(mock_font, conv_options)

        converter.convert(mock_font, options)
      end
    end

    context "with recommended options" do
      it "uses recommended options for Type 1 to OTF" do
        options = Fontisan::ConversionOptions.recommended(from: :type1, to: :otf)

        expect {
          converter.convert(mock_font, options: options)
        }.not_to raise_error
      end
    end

    context "with preset options" do
      it "uses type1_to_modern preset" do
        options = Fontisan::ConversionOptions.from_preset(:type1_to_modern)

        expect {
          converter.convert(mock_font, options: options)
        }.not_to raise_error
      end
    end

    context "with Hash options (backward compatibility)" do
      it "accepts Hash options without ConversionOptions" do
        expect {
          converter.convert(mock_font, target_format: :otf)
        }.not_to raise_error
      end
    end
  end
end

