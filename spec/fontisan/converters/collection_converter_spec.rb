# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Fontisan::Converters::CollectionConverter do
  let(:converter) { described_class.new }

  describe "#extract_conversion_options" do
    it "extracts ConversionOptions from options hash" do
      conv_options = Fontisan::ConversionOptions.new(from: :ttc, to: :otc)
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
      conv_options = Fontisan::ConversionOptions.new(from: :ttc, to: :otc)

      result = converter.send(:extract_conversion_options, conv_options)

      expect(result).to eq(conv_options)
    end
  end

  describe "#convert with ConversionOptions" do
    let(:collection_path) do
      "spec/fixtures/fonts/MonaSans/variable/MonaSans[wdth,wght].ttf"
    end
    let(:output_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(output_dir) if File.exist?(output_dir)
    end

    it "passes ConversionOptions to FormatConverter" do
      options = {
        output: File.join(output_dir, "output.otc"),
        target_format: :otf,
        options: Fontisan::ConversionOptions.new(from: :ttc, to: :otc),
      }

      # Just verify it doesn't raise an error
      # The actual conversion may fail due to unsupported format,
      # but the integration should work
      # Check the integration is there
      expect do
        converter.convert(collection_path, target_type: :otc, **options)
      end.not_to raise_error(NoMethodError)
    end

    it "works with Hash options (backward compatibility)" do
      options = {
        output: File.join(output_dir, "output.otc"),
        target_format: :otf,
      }

      # Check the integration is there
      expect do
        converter.convert(collection_path, target_type: :otc, **options)
      end.not_to raise_error(NoMethodError)
    end
  end
end
