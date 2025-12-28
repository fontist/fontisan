# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Pipeline::TransformationPipeline do
  let(:fixture_path) { File.join(__dir__, "../../fixtures/fonts") }
  let(:output_dir) { File.join(__dir__, "../../tmp/pipeline_output") }
  let(:input_font) { File.join(fixture_path, "noto-sans/NotoSans-Regular.ttf") }
  let(:output_font) { File.join(output_dir, "output.otf") }

  before do
    # Create output directory
    FileUtils.mkdir_p(output_dir)
  end

  after do
    # Clean up output files
    FileUtils.rm_rf(output_dir) if File.exist?(output_dir)
  end

  describe "#initialize" do
    it "initializes with valid paths" do
      pipeline = described_class.new(input_font, output_font)
      expect(pipeline.input_path).to eq(input_font)
      expect(pipeline.output_path).to eq(output_font)
    end

    it "raises error if input file does not exist" do
      expect do
        described_class.new("nonexistent.ttf", output_font)
      end.to raise_error(ArgumentError, /Input file not found/)
    end

    it "raises error if output directory does not exist" do
      expect do
        described_class.new(input_font, "/nonexistent/dir/output.ttf")
      end.to raise_error(ArgumentError, /Output directory not found/)
    end

    it "accepts options" do
      pipeline = described_class.new(
        input_font,
        output_font,
        target_format: :otf,
        validate: false,
        verbose: true,
      )
      expect(pipeline.options[:target_format]).to eq(:otf)
      expect(pipeline.options[:validate]).to be(false)
      expect(pipeline.options[:verbose]).to be(true)
    end

    it "uses default options" do
      pipeline = described_class.new(input_font, output_font)
      expect(pipeline.options[:validate]).to be(true)
      expect(pipeline.options[:verbose]).to be(false)
    end
  end

  describe "#transform" do
    context "with TTF to OTF conversion" do
      let(:output_font) { File.join(output_dir, "output.otf") }

      it "transforms font successfully" do
        pipeline = described_class.new(input_font, output_font, validate: false)
        result = pipeline.transform

        expect(result[:success]).to be(true)
        expect(result[:output_path]).to eq(output_font)
        expect(File.exist?(output_font)).to be(true)
      end

      it "detects format correctly" do
        pipeline = described_class.new(input_font, output_font, validate: false)
        result = pipeline.transform

        expect(result[:details][:source_format]).to eq(:ttf)
        expect(result[:details][:target_format]).to eq(:otf)
      end

      it "provides transformation details" do
        pipeline = described_class.new(input_font, output_font, validate: false)
        result = pipeline.transform

        expect(result[:details]).to include(
          :source_format,
          :source_variation,
          :target_format,
          :variation_strategy,
        )
      end
    end

    context "with same format copy" do
      let(:output_font) { File.join(output_dir, "copy.ttf") }

      it "copies font successfully" do
        pipeline = described_class.new(input_font, output_font, validate: false)
        result = pipeline.transform

        expect(result[:success]).to be(true)
        expect(File.exist?(output_font)).to be(true)
      end

      it "uses preserve strategy for static fonts" do
        pipeline = described_class.new(input_font, output_font, validate: false)
        result = pipeline.transform

        expect(result[:details][:variation_strategy]).to eq(:preserve)
      end
    end

    context "with target format detection from extension" do
      it "detects .ttf extension" do
        output = File.join(output_dir, "output.ttf")
        pipeline = described_class.new(input_font, output, validate: false)
        result = pipeline.transform

        expect(result[:details][:target_format]).to eq(:ttf)
      end

      it "detects .otf extension" do
        output = File.join(output_dir, "output.otf")
        pipeline = described_class.new(input_font, output, validate: false)
        result = pipeline.transform

        expect(result[:details][:target_format]).to eq(:otf)
      end

      it "uses explicit target_format over extension" do
        output = File.join(output_dir, "output.ttf")
        pipeline = described_class.new(
          input_font,
          output,
          target_format: :otf,
          validate: false,
        )
        result = pipeline.transform

        expect(result[:details][:target_format]).to eq(:otf)
      end
    end

    context "with validation" do
      it "validates output by default", :slow do
        pipeline = described_class.new(input_font, output_font)

        # Should not raise - validation passes
        expect { pipeline.transform }.not_to raise_error
      end

      it "skips validation when requested" do
        pipeline = described_class.new(input_font, output_font, validate: false)
        result = pipeline.transform

        expect(result[:success]).to be(true)
      end
    end

    context "with error handling" do
      it "handles conversion errors gracefully" do
        # Create invalid font path
        invalid_input = File.join(fixture_path, "invalid.ttf")
        File.write(invalid_input, "not a font")

        pipeline = described_class.new(invalid_input, output_font)

        expect { pipeline.transform }.to raise_error(Fontisan::Error)

        # Clean up
        File.delete(invalid_input)
      end

      it "provides error context in message" do
        invalid_input = File.join(fixture_path, "invalid.ttf")
        File.write(invalid_input, "not a font")

        pipeline = described_class.new(invalid_input, output_font)

        expect { pipeline.transform }.to raise_error(Fontisan::Error, /Transformation failed/)

        File.delete(invalid_input)
      end
    end
  end

  describe "#target_format" do
    it "returns explicit target format" do
      pipeline = described_class.new(
        input_font,
        output_font,
        target_format: :woff2,
      )
      expect(pipeline.send(:target_format)).to eq(:woff2)
    end

    it "detects format from .ttf extension" do
      output = File.join(output_dir, "output.ttf")
      pipeline = described_class.new(input_font, output)
      expect(pipeline.send(:target_format)).to eq(:ttf)
    end

    it "detects format from .otf extension" do
      output = File.join(output_dir, "output.otf")
      pipeline = described_class.new(input_font, output)
      expect(pipeline.send(:target_format)).to eq(:otf)
    end

    it "raises error for unknown extension" do
      output = File.join(output_dir, "output.unknown")
      pipeline = described_class.new(input_font, output)

      expect { pipeline.send(:target_format) }.to raise_error(
        ArgumentError,
        /Cannot determine target format/,
      )
    end
  end

  describe "variation strategy selection" do
    let(:variable_font) { font_fixture_path("MonaSans", "fonts/variable/MonaSansVF[wdth,wght,opsz,ital].ttf") }

    context "with static font" do
      it "uses preserve strategy" do
        pipeline = described_class.new(input_font, output_font, validate: false)
        result = pipeline.transform

        expect(result[:details][:source_variation]).to eq(:static)
        expect(result[:details][:variation_strategy]).to eq(:preserve)
      end
    end

    context "with explicit coordinates" do
      it "uses instance strategy when coordinates provided" do
        skip "Variable font fixture not available" unless File.exist?(variable_font)

        output = File.join(output_dir, "instance.ttf")
        pipeline = described_class.new(
          variable_font,
          output,
          coordinates: { "wght" => 700.0 },
          validate: false,
        )
        result = pipeline.transform

        expect(result[:details][:variation_strategy]).to eq(:instance)
      end
    end

    context "with explicit instance index" do
      it "uses named strategy when instance_index provided" do
        skip "Variable font fixture not available" unless File.exist?(variable_font)

        output = File.join(output_dir, "named.ttf")
        pipeline = described_class.new(
          variable_font,
          output,
          instance_index: 0,
          validate: false,
        )
        result = pipeline.transform

        expect(result[:details][:variation_strategy]).to eq(:named)
      end
    end

    context "with preserve_variation option" do
      it "respects preserve_variation: false" do
        skip "Variable font fixture not available" unless File.exist?(variable_font)

        output = File.join(output_dir, "no_variation.ttf")
        pipeline = described_class.new(
          variable_font,
          output,
          preserve_variation: false,
          validate: false,
        )
        result = pipeline.transform

        expect(result[:details][:variation_strategy]).to eq(:instance)
      end
    end
  end

  describe "format compatibility" do
    it "handles same format (no conversion)" do
      output = File.join(output_dir, "copy.ttf")
      pipeline = described_class.new(input_font, output, validate: false)
      result = pipeline.transform

      expect(result[:success]).to be(true)
      expect(result[:details][:source_format]).to eq(:ttf)
      expect(result[:details][:target_format]).to eq(:ttf)
    end

    it "handles same outline family (TTF to TTF)" do
      output = File.join(output_dir, "converted.ttf")
      pipeline = described_class.new(input_font, output, validate: false)
      result = pipeline.transform

      expect(result[:success]).to be(true)
    end

    it "handles different outline family (TTF to OTF)" do
      output = File.join(output_dir, "converted.otf")
      pipeline = described_class.new(input_font, output, validate: false)
      result = pipeline.transform

      expect(result[:success]).to be(true)
      expect(result[:details][:source_format]).to eq(:ttf)
      expect(result[:details][:target_format]).to eq(:otf)
    end
  end

  describe "verbose output" do
    it "logs steps when verbose is true" do
      pipeline = described_class.new(
        input_font,
        output_font,
        verbose: true,
        validate: false,
      )

      expect do
        pipeline.transform
      end.to output(/Starting transformation/).to_stdout
    end

    it "suppresses logs when verbose is false" do
      pipeline = described_class.new(
        input_font,
        output_font,
        verbose: false,
        validate: false,
      )

      expect do
        pipeline.transform
      end.not_to output.to_stdout
    end
  end
end
