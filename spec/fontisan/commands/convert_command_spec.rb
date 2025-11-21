# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::ConvertCommand do
  let(:font_path) { "spec/fixtures/fonts/NotoSans-Regular.ttf" }
  let(:output_path) { "spec/fixtures/output/converted.ttf" }
  let(:options) { { to: "ttf", output: output_path } }

  before do
    # Clean up any existing output files
    FileUtils.rm_f(output_path)
  end

  after do
    # Clean up test output files
    FileUtils.rm_f(output_path) if File.exist?(output_path)
  end

  describe "#initialize" do
    it "initializes with font path and options" do
      command = described_class.new(font_path, options)
      expect(command).to be_a(described_class)
    end

    it "parses target format from options" do
      command = described_class.new(font_path, to: "otf", output: output_path)
      expect(command.instance_variable_get(:@target_format)).to eq(:otf)
    end

    it "accepts various format aliases" do
      {
        "ttf" => :ttf,
        "truetype" => :ttf,
        "otf" => :otf,
        "opentype" => :otf,
        "cff" => :otf,
      }.each do |input, expected|
        command = described_class.new(
          font_path,
          to: input,
          output: output_path,
        )
        expect(command.instance_variable_get(:@target_format)).to eq(expected)
      end
    end

    it "raises ArgumentError for unknown format" do
      expect do
        described_class.new(font_path, to: "unknown", output: output_path)
      end.to raise_error(ArgumentError, /Unknown target format/)
    end
  end

  describe "#run" do
    context "with valid TTF to TTF conversion" do
      it "copies the font successfully" do
        command = described_class.new(font_path, options)
        result = command.run

        expect(result[:success]).to be true
        expect(result[:input_path]).to eq(font_path)
        expect(result[:output_path]).to eq(output_path)
        expect(File.exist?(output_path)).to be true
      end

      it "returns conversion details" do
        command = described_class.new(font_path, options)
        result = command.run

        expect(result).to include(
          :success,
          :input_path,
          :output_path,
          :source_format,
          :target_format,
          :input_size,
          :output_size,
        )
      end

      it "detects source format correctly" do
        command = described_class.new(font_path, options)
        result = command.run

        expect(result[:source_format]).to eq(:ttf)
      end

      it "preserves target format" do
        command = described_class.new(font_path, options)
        result = command.run

        expect(result[:target_format]).to eq(:ttf)
      end
    end

    context "with missing required options" do
      it "raises ArgumentError without output path" do
        command = described_class.new(font_path, to: "ttf")

        expect do
          command.run
        end.to raise_error(ArgumentError, /Output path is required/)
      end

      it "raises ArgumentError without target format" do
        command = described_class.new(font_path, output: output_path)

        expect do
          command.run
        end.to raise_error(ArgumentError, /Target format is required/)
      end
    end

    context "with unsupported conversions" do
      it "raises error for unsupported conversion" do
        command = described_class.new(
          font_path,
          to: "woff",
          output: output_path,
        )

        expect do
          command.run
        end.to raise_error(ArgumentError, /not supported.*Available targets/)
      end

      it "lists available targets in error message" do
        command = described_class.new(
          font_path,
          to: "woff",
          output: output_path,
        )

        begin
          command.run
        rescue ArgumentError => e
          expect(e.message).to include("Available targets")
        end
      end
    end

    context "with TTF to OTF conversion" do
      let(:otf_output) { "spec/fixtures/output/converted.otf" }

      after do
        FileUtils.rm_f(otf_output) if File.exist?(otf_output)
      end

      it "raises NotImplementedError" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
        )

        expect do
          command.run
        end.to raise_error(NotImplementedError)
      end

      it "provides helpful error message" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
        )

        expect { command.run }.to raise_error do |error|
          expect(error.message).to include("needs additional implementation")
        end
      end
    end
  end

  describe ".supported_conversions" do
    it "returns list of supported conversions" do
      conversions = described_class.supported_conversions
      expect(conversions).to be_an(Array)
      expect(conversions).not_to be_empty
    end

    it "includes same-format conversions" do
      conversions = described_class.supported_conversions
      ttf_to_ttf = conversions.find { |c| c[:from] == :ttf && c[:to] == :ttf }
      expect(ttf_to_ttf).not_to be_nil
    end
  end

  describe ".supported?" do
    it "returns true for TTF to TTF" do
      expect(described_class.supported?(:ttf, :ttf)).to be true
    end

    it "returns true for OTF to OTF" do
      expect(described_class.supported?(:otf, :otf)).to be true
    end

    it "returns false for unsupported conversion" do
      expect(described_class.supported?(:ttf, :woff)).to be false
    end
  end

  describe "format parsing" do
    it "normalizes format strings" do
      command = described_class.new(
        font_path,
        to: "TTF",
        output: output_path,
      )
      expect(command.instance_variable_get(:@target_format)).to eq(:ttf)
    end

    it "handles symbol input" do
      command = described_class.new(
        font_path,
        to: :otf,
        output: output_path,
      )
      expect(command.instance_variable_get(:@target_format)).to eq(:otf)
    end
  end

  describe "file size formatting" do
    it "formats bytes" do
      command = described_class.new(font_path, options)
      formatted = command.send(:format_size, 500)
      expect(formatted).to eq("500 bytes")
    end

    it "formats kilobytes" do
      command = described_class.new(font_path, options)
      formatted = command.send(:format_size, 2048)
      expect(formatted).to match(/2\.0 KB/)
    end

    it "formats megabytes" do
      command = described_class.new(font_path, options)
      formatted = command.send(:format_size, 2 * 1024 * 1024)
      expect(formatted).to match(/2\.0 MB/)
    end
  end

  describe "sfnt version determination" do
    it "uses OTTO for OTF" do
      command = described_class.new(font_path, to: "otf", output: output_path)
      version = command.send(:determine_sfnt_version, :otf)
      expect(version).to eq(0x4F54544F)
    end

    it "uses 1.0 for TTF" do
      command = described_class.new(font_path, options)
      version = command.send(:determine_sfnt_version, :ttf)
      expect(version).to eq(0x00010000)
    end
  end
end
