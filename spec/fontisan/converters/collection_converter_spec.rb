# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Fontisan::Converters::CollectionConverter do
  let(:converter) { described_class.new }
  let(:output_dir) { Dir.mktmpdir }
  let(:collection_path) { File.join(output_dir, "input.ttc") }
  let(:output_path) { File.join(output_dir, "output.otc") }
  let(:source_font) { Fontisan::FontLoader.load(fixture_path("fonttools/TestTTF.ttf")) }
  let(:converted_font) { Fontisan::FontLoader.load(fixture_path("fonttools/TestOTF.otf")) }
  let(:format_converter) { instance_double(Fontisan::Converters::FormatConverter) }
  let(:conv_options) do
    Fontisan::ConversionOptions.new(from: :ttc, to: :otc,
                                    generating: { target_format: "otf" })
  end

  before do
    Fontisan::Collection::Builder.new([source_font]).build_to_file(collection_path)
    allow(Fontisan::Converters::FormatConverter).to receive(:new).and_return(format_converter)
    allow(format_converter).to receive(:convert).and_return(converted_font.table_data)
  end

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe "#convert options" do
    it "passes nested ConversionOptions unchanged to the outline converter" do
      result = converter.convert(collection_path, target_type: :otc,
                                                  options: { output: output_path, options: conv_options })

      expect(format_converter).to have_received(:convert).with(
        an_instance_of(Fontisan::TrueTypeFont), :otf,
        hash_including(options: equal(conv_options))
      )
      expect(result[:conversions]).to eq([
                                           { index: 0, source_format: :ttf, target_format: :otf, status: :converted },
                                         ])
      expect(Fontisan::FontLoader.load_collection(output_path).num_fonts).to eq(1)
    end

    it "preserves the source outline format when ConversionOptions are absent" do
      result = converter.convert(collection_path, target_type: :otc,
                                                  options: { output: output_path })

      expect(result[:conversions]).to eq([
                                           { index: 0, source_format: :ttf, target_format: :ttf, status: :preserved },
                                         ])
      File.open(output_path, "rb") do |io|
        fonts = Fontisan::FontLoader.load_collection(output_path).extract_fonts(io)
        expect(fonts).to all(be_a(Fontisan::TrueTypeFont))
        expect(fonts.map(&:outline_type)).to eq([:truetype])
      end
    end

    it "uses the nested generating target ahead of the hash target" do
      result = converter.convert(collection_path, target_type: :otc,
                                                  options: { output: output_path, target_format: :ttf,
                                                             options: conv_options })

      expect(format_converter).to have_received(:convert).with(
        an_instance_of(Fontisan::TrueTypeFont), :otf,
        hash_including(target_format: "otf", options: equal(conv_options))
      )
      expect(result[:conversions].first).to include(target_format: :otf, status: :converted)
    end

    it "accepts a hash target format without ConversionOptions" do
      result = converter.convert(collection_path, target_type: :otc,
                                                  options: { output: output_path, target_format: :otf })

      expect(format_converter).to have_received(:convert).with(
        an_instance_of(Fontisan::TrueTypeFont), :otf, hash_excluding(:options)
      )
      expect(result[:conversions].first).to include(target_format: :otf, status: :converted)
    end

    it "rejects options without the required output path" do
      expect do
        converter.convert(collection_path, target_type: :otc,
                                           options: { options: conv_options })
      end.to raise_error(ArgumentError, "Output path is required (:output option)")
    end
  end
end
