# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::PackCommand do
  let(:font_path1) { font_fixture_path("SourceSans3", "OTF/SourceSans3-Regular.otf") }
  let(:font_path2) { font_fixture_path("SourceSans3", "OTF/SourceSans3-Bold.otf") }
  let(:font_paths) { [font_path1, font_path2] }
  let(:output_path) { "output.ttc" }

  let(:mock_font1) { instance_double(Fontisan::TrueTypeFont, table_data: {}, respond_to?: true, table_names: []) }
  let(:mock_font2) { instance_double(Fontisan::TrueTypeFont, table_data: {}, respond_to?: true, table_names: []) }

  describe "#initialize" do
    it "initializes with font paths and output" do
      command = described_class.new(font_paths, output: output_path)
      expect(command).to be_a(described_class)
    end

    it "raises error without output path" do
      expect do
        described_class.new(font_paths)
      end.to raise_error(ArgumentError, /Output path is required/)
    end

    it "raises error with empty font paths" do
      expect do
        described_class.new([], output: output_path)
      end.to raise_error(ArgumentError, /Must specify at least 2 font files/)
    end

    it "raises error with single font" do
      expect do
        described_class.new([font_path1], output: output_path)
      end.to raise_error(ArgumentError, /requires at least 2 fonts/)
    end

    it "accepts format option" do
      command = described_class.new(font_paths, output: output_path,
                                                format: :otc)
      expect(command).to be_a(described_class)
    end

    it "accepts optimize option" do
      command = described_class.new(font_paths, output: output_path,
                                                optimize: false)
      expect(command).to be_a(described_class)
    end

    it "accepts verbose option" do
      command = described_class.new(font_paths, output: output_path,
                                                verbose: true)
      expect(command).to be_a(described_class)
    end
  end

  describe "#run" do
    let(:command) { described_class.new(font_paths, output: output_path) }
    let(:mock_builder) { instance_double(Fontisan::Collection::Builder) }
    let(:build_result) do
      {
        binary: "BINARY",
        space_savings: 100,
        num_fonts: 2,
        format: :ttc,
        analysis: {},
        statistics: { sharing_percentage: 33.3 },
        output_path: output_path,
        output_size: 1000,
      }
    end

    before do
      allow(Fontisan::FontLoader).to receive(:load).and_return(mock_font1,
                                                               mock_font2)
      allow(Fontisan::Collection::Builder).to receive(:new).and_return(mock_builder)
      allow(mock_builder).to receive(:validate!)
      allow(mock_builder).to receive(:build_to_file).and_return(build_result)
    end

    it "returns result hash" do
      result = command.run
      expect(result).to be_a(Hash)
      expect(result).to have_key(:output_path)
      expect(result).to have_key(:num_fonts)
    end

    it "loads all fonts" do
      expect(Fontisan::FontLoader).to receive(:load).twice
      command.run
    end

    it "creates builder with fonts" do
      expect(Fontisan::Collection::Builder).to receive(:new).with(
        [mock_font1, mock_font2],
        hash_including(format: :ttc),
      )
      command.run
    end

    it "validates before building" do
      expect(mock_builder).to receive(:validate!)
      command.run
    end

    it "builds to file" do
      expect(mock_builder).to receive(:build_to_file).with(output_path)
      command.run
    end
  end

  describe "error handling" do
    let(:command) { described_class.new(font_paths, output: output_path) }

    it "raises error if font file not found" do
      allow(Fontisan::FontLoader).to receive(:load).and_raise(Errno::ENOENT)
      expect do
        command.run
      end.to raise_error(Fontisan::Error, /Font file not found/)
    end

    it "raises error if font loading fails" do
      allow(Fontisan::FontLoader).to receive(:load).and_raise(StandardError,
                                                              "Load error")
      expect do
        command.run
      end.to raise_error(Fontisan::Error, /Failed to load font/)
    end
  end

  describe "format validation" do
    it "accepts ttc format" do
      expect do
        described_class.new(font_paths, output: output_path, format: "ttc")
      end.not_to raise_error
    end

    it "accepts otc format" do
      expect do
        described_class.new(font_paths, output: output_path, format: "otc")
      end.not_to raise_error
    end

    it "raises error for invalid format" do
      expect do
        described_class.new(font_paths, output: output_path, format: "invalid")
      end.to raise_error(ArgumentError, /Invalid format/)
    end
  end
end
