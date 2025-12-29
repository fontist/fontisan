# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::ConvertCommand do
  let(:fixtures_dir) { File.expand_path("../../fixtures/fonts", __dir__) }
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:variable_ttf) do
    font_fixture_path("MonaSans",
                      "fonts/variable/MonaSansVF[wdth,wght,opsz,ital].ttf")
  end
  let(:output_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(output_dir) if File.exist?(output_dir)
  end

  describe "#initialize" do
    it "initializes with input path and options" do
      output_path = File.join(output_dir, "output.otf")
      command = described_class.new(ttf_path, to: "otf", output: output_path)

      expect(command).to be_a(Fontisan::Commands::BaseCommand)
    end

    it "parses target format correctly" do
      output_path = File.join(output_dir, "output.otf")
      command = described_class.new(ttf_path, to: "otf", output: output_path)

      expect(command.instance_variable_get(:@target_format)).to eq(:otf)
    end

    it "parses coordinates string correctly" do
      output_path = File.join(output_dir, "output.ttf")
      command = described_class.new(
        variable_ttf,
        to: "ttf",
        output: output_path,
        coordinates: "wght=700,wdth=100",
      )

      coords = command.instance_variable_get(:@coordinates)
      expect(coords).to eq({ "wght" => 700.0, "wdth" => 100.0 })
    end

    it "handles instance_coordinates hash" do
      output_path = File.join(output_dir, "output.ttf")
      coords_hash = { "wght" => 700.0, "wdth" => 100.0 }
      command = described_class.new(
        variable_ttf,
        to: "ttf",
        output: output_path,
        instance_coordinates: coords_hash,
      )

      coords = command.instance_variable_get(:@coordinates)
      expect(coords).to eq(coords_hash)
    end
  end

  describe "#parse_coordinates" do
    let(:command) do
      output_path = File.join(output_dir, "output.ttf")
      described_class.new(ttf_path, to: "ttf", output: output_path)
    end

    it "parses simple coordinate string" do
      coords = command.send(:parse_coordinates, "wght=700")
      expect(coords).to eq({ "wght" => 700.0 })
    end

    it "parses multiple coordinates" do
      coords = command.send(:parse_coordinates, "wght=700,wdth=100,slnt=-10")
      expect(coords).to eq({
                             "wght" => 700.0,
                             "wdth" => 100.0,
                             "slnt" => -10.0,
                           })
    end

    it "handles whitespace in coordinate string" do
      coords = command.send(:parse_coordinates, "wght = 700 ,   wdth=100")
      expect(coords).to eq({ "wght" => 700.0, "wdth" => 100.0 })
    end

    it "handles empty pairs gracefully" do
      coords = command.send(:parse_coordinates, "wght=700,,wdth=100")
      expect(coords).to eq({ "wght" => 700.0, "wdth" => 100.0 })
    end
  end

  describe "#run" do
    it "converts TTF to OTF successfully" do
      output_path = File.join(output_dir, "output.otf")
      command = described_class.new(
        ttf_path,
        to: "otf",
        output: output_path,
        quiet: true,
        no_validate: true,
      )

      result = command.run

      expect(result[:success]).to be(true)
      expect(result[:output_path]).to eq(output_path)
      expect(File.exist?(output_path)).to be(true)

      # Verify output is OTF
      font = Fontisan::FontLoader.load(output_path)
      expect(font).to be_a(Fontisan::OpenTypeFont)
      expect(font.has_table?("CFF ")).to be(true)
    end

    it "converts TTF to TTF (copy) successfully" do
      output_path = File.join(output_dir, "output.ttf")
      command = described_class.new(
        ttf_path,
        to: "ttf",
        output: output_path,
        quiet: true,
        no_validate: true,
      )

      result = command.run

      expect(result[:success]).to be(true)
      expect(File.exist?(output_path)).to be(true)

      # Verify output is TTF
      font = Fontisan::FontLoader.load(output_path)
      expect(font).to be_a(Fontisan::TrueTypeFont)
      expect(font.has_table?("glyf")).to be(true)
    end

    it "raises error when output path is missing" do
      command = described_class.new(ttf_path, to: "otf")

      expect do
        command.run
      end.to raise_error(ArgumentError, /Output path is required/)
    end

    it "raises error when target format is missing" do
      output_path = File.join(output_dir, "output.otf")
      command = described_class.new(ttf_path, output: output_path)

      expect do
        command.run
      end.to raise_error(ArgumentError, /Target format is required/)
    end

    it "raises error for unknown target format" do
      output_path = File.join(output_dir, "output.xyz")

      expect do
        described_class.new(ttf_path, to: "xyz", output: output_path)
      end.to raise_error(ArgumentError, /Unknown target format/)
    end

    it "includes variation strategy in result" do
      output_path = File.join(output_dir, "output.ttf")
      command = described_class.new(
        ttf_path,
        to: "ttf",
        output: output_path,
        quiet: true,
        no_validate: true,
      )

      result = command.run

      expect(result).to have_key(:variation_strategy)
      expect(result[:variation_strategy]).to eq(:preserve) # Static font uses preserve
    end
  end

  describe "validation control" do
    it "skips validation when no_validate is true" do
      output_path = File.join(output_dir, "output.otf")
      command = described_class.new(
        ttf_path,
        to: "otf",
        output: output_path,
        quiet: true,
        no_validate: true,
      )

      # Should succeed without validation
      result = command.run
      expect(result[:success]).to be(true)
    end

    it "validates output by default" do
      output_path = File.join(output_dir, "output.otf")
      command = described_class.new(
        ttf_path,
        to: "otf",
        output: output_path,
        quiet: true,
      )

      result = command.run
      expect(result[:success]).to be(true)
      # Validation happens internally, no errors means validation passed
    end
  end

  describe "verbose mode" do
    it "produces verbose output when enabled" do
      output_path = File.join(output_dir, "output.otf")
      command = described_class.new(
        ttf_path,
        to: "otf",
        output: output_path,
        verbose: true,
        no_validate: true,
      )

      expect do
        command.run
      end.to output(/TransformationPipeline/).to_stdout
    end
  end
end
