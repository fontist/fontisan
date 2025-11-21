# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::UnpackCommand do
  let(:collection_path) { "spec/fixtures/fonttools/TestTTC.ttc" }
  let(:output_dir) { "output_fonts" }

  let(:mock_collection) do
    instance_double(
      Fontisan::TrueTypeCollection,
      font_count: 2,
      extract_fonts: [mock_font1, mock_font2],
    )
  end

  let(:mock_font1) do
    instance_double(
      Fontisan::TrueTypeFont,
      table: mock_name_table1,
      respond_to?: true,
    )
  end

  let(:mock_font2) do
    instance_double(
      Fontisan::TrueTypeFont,
      table: mock_name_table2,
      respond_to?: true,
    )
  end

  let(:mock_name_table1) do
    instance_double(
      Fontisan::Tables::Name,
      english_name: "Font1",
    )
  end

  let(:mock_name_table2) do
    instance_double(
      Fontisan::Tables::Name,
      english_name: "Font2",
    )
  end

  describe "#initialize" do
    it "initializes with collection path and output dir" do
      command = described_class.new(collection_path, output_dir: output_dir)
      expect(command).to be_a(described_class)
    end

    it "raises error without output_dir" do
      expect do
        described_class.new(collection_path)
      end.to raise_error(ArgumentError, /Output directory is required/)
    end

    it "raises error if collection file doesn't exist" do
      expect do
        described_class.new("nonexistent.ttc", output_dir: output_dir)
      end.to raise_error(ArgumentError, /Collection file not found/)
    end

    it "accepts font_index option" do
      allow(File).to receive(:exist?).and_return(true)
      command = described_class.new(collection_path, output_dir: output_dir,
                                                     font_index: 1)
      expect(command).to be_a(described_class)
    end

    it "raises error for negative font_index" do
      allow(File).to receive(:exist?).and_return(true)
      expect do
        described_class.new(collection_path, output_dir: output_dir,
                                             font_index: -1)
      end.to raise_error(ArgumentError, /Font index must be >= 0/)
    end
  end

  describe "#run" do
    let(:command) do
      described_class.new(collection_path, output_dir: output_dir)
    end
    let(:temp_dir) { Dir.mktmpdir }

    before do
      allow(File).to receive(:exist?).with(collection_path).and_return(true)
      allow(File).to receive(:open).and_yield(StringIO.new("ttcf"))
      allow(Fontisan::TrueTypeCollection).to receive(:read).and_return(mock_collection)
      allow(FileUtils).to receive(:mkdir_p)
      allow(mock_font1).to receive(:to_file)
      allow(mock_font2).to receive(:to_file)
    end

    after do
      FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
    end

    it "returns result hash" do
      result = command.run
      expect(result).to be_a(Hash)
      expect(result).to have_key(:collection)
      expect(result).to have_key(:output_dir)
      expect(result).to have_key(:num_fonts)
      expect(result).to have_key(:fonts_extracted)
      expect(result).to have_key(:extracted_files)
    end

    it "creates output directory if needed" do
      expect(FileUtils).to receive(:mkdir_p).with(output_dir)
      command.run
    end

    it "extracts all fonts by default" do
      result = command.run
      expect(result[:fonts_extracted]).to eq(2)
    end

    it "writes extracted fonts" do
      expect(mock_font1).to receive(:to_file)
      expect(mock_font2).to receive(:to_file)
      command.run
    end
  end

  describe "font index extraction" do
    let(:command) do
      described_class.new(collection_path, output_dir: output_dir,
                                           font_index: 0)
    end

    before do
      allow(File).to receive(:exist?).with(collection_path).and_return(true)
      allow(File).to receive(:open).and_yield(StringIO.new("ttcf"))
      allow(Fontisan::TrueTypeCollection).to receive(:read).and_return(mock_collection)
      allow(FileUtils).to receive(:mkdir_p)
      allow(mock_font1).to receive(:to_file)
    end

    it "extracts only specified font" do
      result = command.run
      expect(result[:fonts_extracted]).to eq(1)
    end

    it "raises error if index out of range" do
      command = described_class.new(collection_path, output_dir: output_dir,
                                                     font_index: 10)
      allow(File).to receive(:exist?).with(collection_path).and_return(true)
      allow(File).to receive(:open).and_yield(StringIO.new("ttcf"))
      allow(Fontisan::TrueTypeCollection).to receive(:read).and_return(mock_collection)

      expect do
        command.run
      end.to raise_error(ArgumentError, /Font index .* out of range/)
    end
  end

  describe "error handling" do
    let(:command) do
      described_class.new(collection_path, output_dir: output_dir)
    end

    it "raises error for invalid collection file" do
      allow(File).to receive(:exist?).with(collection_path).and_return(true)
      allow(File).to receive(:open).and_yield(StringIO.new("invalid"))

      expect do
        command.run
      end.to raise_error(Fontisan::Error, /Not a valid TTC\/OTC file/)
    end
  end

  describe "format conversion" do
    let(:command) do
      described_class.new(collection_path, output_dir: output_dir,
                                           format: :woff)
    end
    let(:mock_converter) { instance_double(Fontisan::Converters::FormatConverter) }

    before do
      allow(File).to receive(:exist?).with(collection_path).and_return(true)
      allow(File).to receive(:open).and_yield(StringIO.new("ttcf"))
      allow(Fontisan::TrueTypeCollection).to receive(:read).and_return(mock_collection)
      allow(FileUtils).to receive(:mkdir_p)
      allow(Fontisan::Converters::FormatConverter).to receive(:new).and_return(mock_converter)
      allow(mock_converter).to receive(:convert)
    end

    it "converts fonts during extraction" do
      expect(mock_converter).to receive(:convert).twice
      command.run
    end
  end
end
