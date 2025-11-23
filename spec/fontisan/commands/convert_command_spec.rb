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

      before do
        FileUtils.mkdir_p("spec/fixtures/output")
      end

      after do
        FileUtils.rm_f(otf_output) if File.exist?(otf_output)
      end

      # NOTE: NotoSans-Regular.ttf contains compound glyphs starting at glyph 111
      # Compound glyph support has been implemented in Phase 1 Week 5

      it "successfully converts fonts with compound glyphs", :compound_glyphs do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
        )

        result = command.run

        expect(result[:success]).to be true
        expect(result[:target_format]).to eq(:otf)
        expect(File.exist?(otf_output)).to be true
      end

      it "produces valid CFF output for compound glyphs", :compound_glyphs do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
        )

        command.run

        # Load output font and verify structure
        output_font = Fontisan::OpenTypeFont.from_file(otf_output)
        expect(output_font.has_table?("CFF ")).to be true
        expect(output_font.has_table?("glyf")).to be false
        expect(output_font.has_table?("loca")).to be false
      end

      it "successfully converts TTF to OTF" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
        )

        result = command.run

        expect(result[:success]).to be true
        expect(result[:target_format]).to eq(:otf)
        expect(File.exist?(otf_output)).to be true
      end

      it "creates output file with CFF table" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
        )

        command.run

        # Load output font and verify structure
        output_font = Fontisan::OpenTypeFont.from_file(otf_output)
        expect(output_font.has_table?("CFF ")).to be true
        expect(output_font.has_table?("glyf")).to be false
        expect(output_font.has_table?("loca")).to be false
      end

      it "updates maxp table to version 0.5" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
        )

        command.run

        # Verify maxp version
        output_font = Fontisan::OpenTypeFont.from_file(otf_output)
        maxp = output_font.table("maxp")
        expect(maxp.version_raw).to eq(Fontisan::Tables::Maxp::VERSION_0_5)
        expect(maxp.version).to eq(0.5)
      end

      it "preserves other font tables" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
        )

        command.run

        # Verify common tables are preserved
        output_font = Fontisan::OpenTypeFont.from_file(otf_output)
        %w[head hhea maxp name post cmap].each do |tag|
          expect(output_font.has_table?(tag)).to be true
        end
      end

      it "returns conversion details" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
        )

        result = command.run

        expect(result[:source_format]).to eq(:ttf)
        expect(result[:target_format]).to eq(:otf)
        expect(result[:input_size]).to be > 0
        expect(result[:output_size]).to be > 0
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

  describe "subroutine optimization" do
    let(:otf_output) { "spec/fixtures/output/optimized.otf" }

    before do
      FileUtils.mkdir_p("spec/fixtures/output")
    end

    after do
      FileUtils.rm_f(otf_output) if File.exist?(otf_output)
    end

    describe "#initialize with optimization options" do
      it "accepts optimize option" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
          optimize: true,
        )
        expect(command.instance_variable_get(:@optimize)).to be true
      end

      it "accepts min_pattern_length option" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
          optimize: true,
          min_pattern_length: 15,
        )
        expect(command.instance_variable_get(:@min_pattern_length)).to eq(15)
      end

      it "accepts max_subroutines option" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
          optimize: true,
          max_subroutines: 1000,
        )
        expect(command.instance_variable_get(:@max_subroutines)).to eq(1000)
      end

      it "accepts optimize_ordering option" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
          optimize: true,
          optimize_ordering: false,
        )
        expect(command.instance_variable_get(:@optimize_ordering)).to be false
      end

      it "uses default values when not specified" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
        )
        expect(command.instance_variable_get(:@optimize)).to be false
        expect(command.instance_variable_get(:@min_pattern_length)).to eq(10)
        expect(command.instance_variable_get(:@max_subroutines)).to eq(65_535)
        expect(command.instance_variable_get(:@optimize_ordering)).to be true
      end
    end

    describe "#run with optimization" do
      it "passes optimization options to converter" do
        # Mock the entire conversion flow BEFORE creating command
        mock_font = double("Font", has_table?: true, table: double)
        allow(mock_font).to receive(:instance_variable_get).and_return(nil)
        allow(Fontisan::FontLoader).to receive(:load_file).and_return(mock_font)

        converter = instance_double(Fontisan::Converters::FormatConverter)
        allow(Fontisan::Converters::FormatConverter).to receive(:new).and_return(converter)
        allow(converter).to receive(:supported?).and_return(true)

        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
          optimize: true,
          min_pattern_length: 12,
          max_subroutines: 5000,
        )

        # Expect converter to receive correct options
        expect(converter).to receive(:convert) do |_font, target, options|
          expect(target).to eq(:otf)
          expect(options[:target_format]).to eq(:otf)
          expect(options[:optimize_subroutines]).to be true
          expect(options[:min_pattern_length]).to eq(12)
          expect(options[:max_subroutines]).to eq(5000)
          expect(options[:optimize_ordering]).to be true
          {} # Return empty tables hash
        end

        # Mock FontWriter and File operations
        allow(Fontisan::FontWriter).to receive(:write_to_file)
        allow(File).to receive(:size).with(otf_output).and_return(100000)
        allow(File).to receive(:size).with(font_path).and_return(100000)

        expect { command.run }.to output(/Conversion complete/).to_stdout
      end

      it "does not pass optimization when disabled" do
        # Mock the entire conversion flow BEFORE creating command
        mock_font = double("Font", has_table?: true, table: double)
        allow(mock_font).to receive(:instance_variable_get).and_return(nil)
        allow(Fontisan::FontLoader).to receive(:load_file).and_return(mock_font)

        converter = instance_double(Fontisan::Converters::FormatConverter)
        allow(Fontisan::Converters::FormatConverter).to receive(:new).and_return(converter)
        allow(converter).to receive(:supported?).and_return(true)

        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
          optimize: false,
        )

        expect(converter).to receive(:convert) do |_font, _target, options|
          expect(options[:optimize_subroutines]).to be false
          {}
        end

        allow(Fontisan::FontWriter).to receive(:write_to_file)
        allow(File).to receive(:size).with(otf_output).and_return(100000)
        allow(File).to receive(:size).with(font_path).and_return(100000)

        expect { command.run }.to output(/Conversion complete/).to_stdout
      end

      it "displays optimization results when verbose" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
          optimize: true,
          verbose: true,
        )

        # Mock the entire conversion flow
        mock_font = double("Font", has_table?: true, table: double)
        allow(mock_font).to receive(:instance_variable_get).and_return(nil)
        allow(Fontisan::FontLoader).to receive(:load_file).and_return(mock_font)

        # Mock successful conversion with optimization result
        tables = {}
        optimization_result = {
          local_subrs: [[0x0B]],
          selected_count: 5,
          pattern_count: 10,
          savings: 1000,
          bias: 107,
        }
        tables.instance_variable_set(:@subroutine_optimization, optimization_result)

        converter = instance_double(Fontisan::Converters::FormatConverter)
        allow(Fontisan::Converters::FormatConverter).to receive(:new).and_return(converter)
        allow(converter).to receive(:convert).and_return(tables)

        allow(Fontisan::FontWriter).to receive(:write_to_file)
        allow(File).to receive(:size).with(otf_output).and_return(100000)
        allow(File).to receive(:size).with(font_path).and_return(100000)

        expect do
          command.run
        end.to output(/Subroutine Optimization Results/).to_stdout
      end

      it "does not display results when not verbose" do
        command = described_class.new(
          font_path,
          to: "otf",
          output: otf_output,
          optimize: true,
          verbose: false,
        )

        # Mock the entire conversion flow
        mock_font = double("Font", has_table?: true, table: double)
        allow(mock_font).to receive(:instance_variable_get).and_return(nil)
        allow(Fontisan::FontLoader).to receive(:load_file).and_return(mock_font)

        converter = instance_double(Fontisan::Converters::FormatConverter)
        allow(Fontisan::Converters::FormatConverter).to receive(:new).and_return(converter)
        allow(converter).to receive(:convert).and_return({})

        allow(Fontisan::FontWriter).to receive(:write_to_file)
        allow(File).to receive(:size).with(otf_output).and_return(100000)
        allow(File).to receive(:size).with(font_path).and_return(100000)

        expect do
          command.run
        end.not_to output(/Subroutine Optimization/).to_stdout
      end
    end
  end
end
