# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::SubsetCommand do
  let(:font_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:output_path) { File.join(Dir.tmpdir, "subset_test.ttf") }

  after do
    File.delete(output_path) if File.exist?(output_path)
  end

  describe "#initialize" do
    it "initializes with font path and options" do
      options = { text: "ABC", output: output_path }
      command = described_class.new(font_path, options)

      expect(command).to be_a(described_class)
    end

    it "raises error without output path" do
      expect do
        described_class.new(font_path, text: "ABC")
      end.to raise_error(ArgumentError, /Output path is required/)
    end

    it "raises error without input method" do
      expect do
        described_class.new(font_path, output: output_path)
      end.to raise_error(ArgumentError,
                         /Must specify --text, --glyphs, or --unicode/)
    end

    it "raises error with multiple input methods" do
      expect do
        described_class.new(font_path, text: "ABC", glyphs: [0, 1],
                                       output: output_path)
      end.to raise_error(ArgumentError, /Can only specify one of/)
    end
  end

  describe "#run with text input" do
    let(:options) { { text: "ABC", output: output_path, profile: "pdf" } }
    let(:command) { described_class.new(font_path, options) }

    it "creates subset font file" do
      command.run
      expect(File.exist?(output_path)).to be true
    end

    it "returns result hash with metadata" do
      result = command.run

      expect(result).to be_a(Hash)
      expect(result[:input]).to eq(font_path)
      expect(result[:output]).to eq(output_path)
      expect(result[:original_glyphs]).to be > 0
      expect(result[:subset_glyphs]).to be > 0
      expect(result[:profile]).to eq("pdf")
      expect(result[:size]).to be > 0
    end

    it "produces valid font binary" do
      command.run

      # Read output file
      subset_data = File.binread(output_path)

      # Should have valid sfnt header
      sfnt_version = subset_data[0, 4].unpack1("N")
      expect([0x00010000, 0x4F54544F]).to include(sfnt_version)
    end

    it "includes glyphs for all characters in text" do
      result = command.run

      # Subset should include .notdef + glyphs for A, B, C
      expect(result[:subset_glyphs]).to be >= 4
    end

    it "warns about unmapped characters when verbose" do
      options_with_verbose = options.merge(verbose: true)
      command_verbose = described_class.new(font_path, options_with_verbose)

      # Add unmapped character
      options_with_verbose[:text] = "ABC\u{FFFF}"

      expect do
        command_verbose.run
      end.to output(/not found in font/).to_stderr
    end

    it "handles empty result when no characters found" do
      options_empty = { text: "\u{FFFF}", output: output_path }
      command_empty = described_class.new(font_path, options_empty)

      expect do
        command_empty.run
      end.to raise_error(ArgumentError, /No characters from text found/)
    end
  end

  describe "#run with glyphs input" do
    let(:options) { { glyphs: "0,1,65,66,67", output: output_path } }
    let(:command) { described_class.new(font_path, options) }

    it "creates subset font with specified glyphs" do
      result = command.run

      expect(File.exist?(output_path)).to be true
      expect(result[:subset_glyphs]).to be >= 5
    end

    it "accepts array of glyph IDs" do
      options_array = { glyphs: [0, 1, 65, 66, 67], output: output_path }
      command_array = described_class.new(font_path, options_array)

      command_array.run
      expect(File.exist?(output_path)).to be true
    end

    it "accepts space-separated glyph IDs" do
      options_space = { glyphs: "0 1 65 66 67", output: output_path }
      command_space = described_class.new(font_path, options_space)

      command_space.run
      expect(File.exist?(output_path)).to be true
    end
  end

  describe "#run with unicode input" do
    let(:options) { { unicode: "U+0041,U+0042,U+0043", output: output_path } }
    let(:command) { described_class.new(font_path, options) }

    it "creates subset font from Unicode codepoints" do
      result = command.run

      expect(File.exist?(output_path)).to be true
      expect(result[:subset_glyphs]).to be >= 4 # .notdef + A, B, C
    end

    it "accepts hex values without U+ prefix" do
      options_hex = { unicode: "0x41,0x42,0x43", output: output_path }
      command_hex = described_class.new(font_path, options_hex)

      command_hex.run
      expect(File.exist?(output_path)).to be true
    end

    it "accepts decimal values" do
      options_decimal = { unicode: "65,66,67", output: output_path }
      command_decimal = described_class.new(font_path, options_decimal)

      command_decimal.run
      expect(File.exist?(output_path)).to be true
    end

    it "warns about unmapped codepoints when verbose" do
      options_verbose = options.merge(verbose: true, unicode: "U+0041,U+FFFF")
      command_verbose = described_class.new(font_path, options_verbose)

      expect do
        command_verbose.run
      end.to output(/not found in font/).to_stderr
    end
  end

  describe "profile options" do
    let(:base_options) { { text: "ABC", output: output_path } }

    it "subsets with pdf profile" do
      command = described_class.new(font_path,
                                    base_options.merge(profile: "pdf"))
      result = command.run
      expect(result[:profile]).to eq("pdf")
    end

    it "subsets with web profile" do
      command = described_class.new(font_path,
                                    base_options.merge(profile: "web"))
      result = command.run
      expect(result[:profile]).to eq("web")
    end

    it "subsets with minimal profile" do
      command = described_class.new(font_path,
                                    base_options.merge(profile: "minimal"))
      result = command.run
      expect(result[:profile]).to eq("minimal")
    end

    it "defaults to pdf profile" do
      command = described_class.new(font_path, base_options)
      result = command.run
      expect(result[:profile]).to eq("pdf")
    end
  end

  describe "subsetting options" do
    let(:base_options) { { text: "ABC", output: output_path } }

    it "handles retain_gids option" do
      command = described_class.new(font_path,
                                    base_options.merge(retain_gids: true))
      command.run
      expect(File.exist?(output_path)).to be true
    end

    it "handles drop_hints option" do
      command = described_class.new(font_path,
                                    base_options.merge(drop_hints: true))
      command.run
      expect(File.exist?(output_path)).to be true
    end

    it "handles drop_names option" do
      command = described_class.new(font_path,
                                    base_options.merge(drop_names: true))
      command.run
      expect(File.exist?(output_path)).to be true
    end

    it "handles combined options" do
      combined = base_options.merge(
        retain_gids: false,
        drop_hints: true,
        drop_names: true,
        unicode_ranges: false,
      )
      command = described_class.new(font_path, combined)
      command.run
      expect(File.exist?(output_path)).to be true
    end
  end

  describe "error handling" do
    it "raises error for missing font file" do
      expect do
        described_class.new("nonexistent.ttf", text: "ABC",
                                               output: output_path)
      end.to raise_error(Errno::ENOENT)
    end

    it "raises error for invalid glyph IDs" do
      command = described_class.new(font_path, glyphs: [99999],
                                               output: output_path)
      expect do
        command.run
      end.to raise_error(ArgumentError, /exceeds/)
    end

    it "provides clear error messages" do
      command = described_class.new(font_path, glyphs: [-1],
                                               output: output_path)
      expect do
        command.run
      end.to raise_error(ArgumentError, /Invalid glyph ID/)
    end
  end

  describe "edge cases" do
    it "handles single character subset" do
      command = described_class.new(font_path, text: "A", output: output_path)
      command.run
      expect(File.exist?(output_path)).to be true
    end

    it "handles large text input" do
      large_text = "#{('A'..'Z').to_a.join}#{('a'..'z').to_a.join}0123456789"
      command = described_class.new(font_path, text: large_text,
                                               output: output_path)
      result = command.run
      expect(result[:subset_glyphs]).to be > 60
    end

    it "handles duplicate characters in text" do
      command = described_class.new(font_path, text: "AAABBBCCC",
                                               output: output_path)
      result = command.run
      # Should deduplicate - expect glyphs for .notdef, A, B, C
      expect(result[:subset_glyphs]).to be <= 10
    end

    it "handles special characters" do
      command = described_class.new(font_path, text: "ABC!@#",
                                               output: output_path)
      command.run
      expect(File.exist?(output_path)).to be true
    end
  end

  describe "output file management" do
    it "creates parent directories if needed" do
      nested_output = File.join(Dir.tmpdir, "fontisan_test", "nested",
                                "subset.ttf")

      begin
        command = described_class.new(font_path, text: "ABC",
                                                 output: nested_output)
        command.run

        expect(File.exist?(nested_output)).to be true
      ensure
        FileUtils.rm_rf(File.join(Dir.tmpdir, "fontisan_test"))
      end
    end

    it "overwrites existing output file" do
      # Create initial file
      File.write(output_path, "existing content")

      command = described_class.new(font_path, text: "ABC", output: output_path)
      command.run

      # Should be overwritten with valid font
      subset_data = File.binread(output_path)
      expect(subset_data).not_to eq("existing content")
      expect(subset_data[0, 4].unpack1("N")).to be > 0
    end
  end

  describe "result metadata" do
    let(:command) do
      described_class.new(font_path, text: "ABC", output: output_path)
    end

    it "includes input path in result" do
      result = command.run
      expect(result[:input]).to eq(font_path)
    end

    it "includes output path in result" do
      result = command.run
      expect(result[:output]).to eq(output_path)
    end

    it "includes original glyph count in result" do
      result = command.run
      expect(result[:original_glyphs]).to be > 0
    end

    it "includes subset glyph count in result" do
      result = command.run
      expect(result[:subset_glyphs]).to be > 0
      expect(result[:subset_glyphs]).to be < result[:original_glyphs]
    end

    it "includes profile in result" do
      result = command.run
      expect(result[:profile]).to eq("pdf")
    end

    it "includes output file size in result" do
      result = command.run
      expect(result[:size]).to eq(File.size(output_path))
    end
  end
end
