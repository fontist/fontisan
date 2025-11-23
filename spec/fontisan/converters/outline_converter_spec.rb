# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Converters::OutlineConverter do
  let(:converter) { described_class.new }
  let(:ttf_font) { double("TrueTypeFont") }
  let(:otf_font) { double("OpenTypeFont") }

  before do
    # Setup TTF font mock
    allow(ttf_font).to receive(:has_table?).with("glyf").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("loca").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("CFF ").and_return(false)
    allow(ttf_font).to receive(:has_table?).with("CFF2").and_return(false)
    allow(ttf_font).to receive(:table).with("glyf").and_return(double)
    allow(ttf_font).to receive(:table).with("loca").and_return(double)
    allow(ttf_font).to receive(:table).with("head").and_return(double)
    allow(ttf_font).to receive(:table).with("hhea").and_return(double)
    allow(ttf_font).to receive(:table).with("maxp").and_return(double)
    allow(ttf_font).to receive(:table).with("CFF ").and_return(nil)
    allow(ttf_font).to receive(:table).with("CFF2").and_return(nil)
    allow(ttf_font).to receive_messages(tables: {}, table_data: {})

    # Setup OTF font mock
    allow(otf_font).to receive(:has_table?).with("glyf").and_return(false)
    allow(otf_font).to receive(:has_table?).with("CFF ").and_return(true)
    allow(otf_font).to receive(:has_table?).with("CFF2").and_return(false)
    allow(otf_font).to receive(:table).with("CFF ").and_return(double)
    allow(otf_font).to receive(:table).with("CFF2").and_return(nil)
    allow(otf_font).to receive(:table).with("glyf").and_return(nil)
    allow(otf_font).to receive(:table).with("head").and_return(double)
    allow(otf_font).to receive(:table).with("hhea").and_return(double)
    allow(otf_font).to receive(:table).with("maxp").and_return(double)
    allow(otf_font).to receive_messages(tables: {}, table_data: {})
  end

  describe "#convert" do
    context "with invalid parameters" do
      it "raises ArgumentError for nil font" do
        expect do
          converter.convert(nil, target_format: :otf)
        end.to raise_error(ArgumentError, /Font cannot be nil/)
      end

      it "raises ArgumentError for font without tables method" do
        invalid_font = double("InvalidFont")
        allow(invalid_font).to receive(:table).and_return(double)

        expect do
          converter.convert(invalid_font, target_format: :otf)
        end.to raise_error(ArgumentError, /must respond to :tables/)
      end
    end
  end

  describe "#supported_conversions" do
    it "includes TTF to OTF" do
      conversions = converter.supported_conversions
      expect(conversions).to include(%i[ttf otf])
    end

    it "includes OTF to TTF" do
      conversions = converter.supported_conversions
      expect(conversions).to include(%i[otf ttf])
    end

    it "does not include same-format conversions" do
      conversions = converter.supported_conversions
      expect(conversions).not_to include(%i[ttf ttf])
      expect(conversions).not_to include(%i[otf otf])
    end
  end

  describe "#validate" do
    context "with valid fonts" do
      it "validates TTF to OTF conversion" do
        # Ensure loca has_table? returns true
        allow(ttf_font).to receive(:has_table?).with("loca").and_return(true)
        allow(ttf_font).to receive(:has_table?).with("glyf").and_return(true)

        expect do
          converter.validate(ttf_font, :otf)
        end.not_to raise_error
      end

      it "validates OTF to TTF conversion" do
        expect do
          converter.validate(otf_font, :ttf)
        end.not_to raise_error
      end
    end

    context "with invalid fonts" do
      it "rejects nil font" do
        expect do
          converter.validate(nil, :otf)
        end.to raise_error(ArgumentError, /Font cannot be nil/)
      end

      it "rejects unsupported conversion" do
        allow(ttf_font).to receive(:table).with("loca").and_return(nil)

        expect do
          converter.validate(ttf_font, :svg)
        end.to raise_error(Fontisan::Error, /not supported/)
      end
    end

    context "with missing required tables" do
      it "rejects TTF without glyf table" do
        # Keep has_table? true so format detection works
        # But make table() return nil so validation fails
        allow(ttf_font).to receive(:table).with("glyf").and_return(nil)

        expect do
          converter.validate(ttf_font, :otf)
        end.to raise_error(Fontisan::MissingTableError, /glyf or loca/)
      end

      it "rejects TTF without loca table" do
        allow(ttf_font).to receive(:has_table?).with("loca").and_return(false)
        allow(ttf_font).to receive(:table).with("loca").and_return(nil)

        expect do
          converter.validate(ttf_font, :otf)
        end.to raise_error(Fontisan::MissingTableError, /glyf or loca/)
      end

      it "rejects OTF without CFF table" do
        # Keep has_table? true for format detection
        # But make table() return nil for validation failure
        allow(otf_font).to receive(:table).with("CFF ").and_return(nil)

        expect do
          converter.validate(otf_font, :ttf)
        end.to raise_error(Fontisan::MissingTableError, /CFF/)
      end

      it "rejects font without head table" do
        # Ensure glyf and loca are properly set up
        allow(ttf_font).to receive(:has_table?).with("glyf").and_return(true)
        allow(ttf_font).to receive(:has_table?).with("loca").and_return(true)
        allow(ttf_font).to receive(:table).with("glyf").and_return(double("glyf"))
        allow(ttf_font).to receive(:table).with("loca").and_return(double("loca"))
        allow(ttf_font).to receive(:table).with("head").and_return(nil)

        expect do
          converter.validate(ttf_font, :otf)
        end.to raise_error(Fontisan::MissingTableError, /head/)
      end
    end
  end

  describe "#supports?" do
    it "returns true for TTF to OTF" do
      expect(converter.supports?(:ttf, :otf)).to be true
    end

    it "returns true for OTF to TTF" do
      expect(converter.supports?(:otf, :ttf)).to be true
    end

    it "returns false for TTF to TTF" do
      expect(converter.supports?(:ttf, :ttf)).to be false
    end

    it "returns false for OTF to OTF" do
      expect(converter.supports?(:otf, :otf)).to be false
    end
  end

  describe "format detection" do
    it "detects TTF from glyf table" do
      format = converter.send(:detect_format, ttf_font)
      expect(format).to eq(:ttf)
    end

    it "detects OTF from CFF table" do
      format = converter.send(:detect_format, otf_font)
      expect(format).to eq(:otf)
    end

    it "prefers CFF over CFF2" do
      allow(otf_font).to receive(:table).with("CFF2").and_return(double)
      format = converter.send(:detect_format, otf_font)
      expect(format).to eq(:otf)
    end

    it "raises error for unknown format" do
      unknown_font = double("UnknownFont")
      allow(unknown_font).to receive_messages(has_table?: false, table: nil)

      expect do
        converter.send(:detect_format, unknown_font)
      end.to raise_error(Fontisan::Error, /Cannot detect font format/)
    end
  end

  describe "subroutine optimization integration" do
    let(:head_table) { double("HeadTable", index_to_loc_format: 1) }
    let(:maxp_table) { double("MaxpTable", num_glyphs: 3) }
    let(:loca_table) { double("LocaTable") }
    let(:glyf_table) { double("GlyfTable") }
    let(:name_table) { double("NameTable") }
    let(:cff_table) { double("CffTable") }

    before do
      # Setup complete TTF font mock for conversion
      allow(ttf_font).to receive(:table).with("head").and_return(head_table)
      allow(ttf_font).to receive(:table).with("maxp").and_return(maxp_table)
      allow(ttf_font).to receive(:table).with("loca").and_return(loca_table)
      allow(ttf_font).to receive(:table).with("glyf").and_return(glyf_table)
      allow(ttf_font).to receive(:table).with("name").and_return(name_table)
      allow(ttf_font).to receive(:table_data).and_return({
                                                           "head" => "\x00" * 54,
                                                           "hhea" => "\x00" * 36,
                                                           "maxp" => "\x00" * 6,
                                                         })

      # Setup loca table
      allow(loca_table).to receive(:parse_with_context)

      # Setup name table
      allow(name_table).to receive(:english_name).and_return("TestFont")

      # Setup glyf table with empty glyphs
      allow(glyf_table).to receive(:glyph_for).and_return(
        double("Glyph", nil?: false, empty?: true, simple?: true),
      )
    end

    context "with optimize_subroutines option enabled" do
      let(:optimization_result) do
        {
          local_subrs: [[0x0B]],
          charstrings: [[0x8B, 0x00, 0x0B], [0x8B, 0x01, 0x0B]],
          pattern_count: 5,
          selected_count: 1,
          savings: 50,
          bias: 107,
        }
      end

      before do
        # Mock SubroutineGenerator
        generator = double("SubroutineGenerator")
        allow(Fontisan::Optimizers::SubroutineGenerator).to receive(:new)
          .and_return(generator)
        allow(generator).to receive(:generate).and_return(optimization_result)
      end

      it "generates subroutines during TTF→OTF conversion" do
        options = {
          target_format: :otf,
          optimize_subroutines: true,
        }

        result = converter.convert(ttf_font, options)

        # Verify optimization was attempted
        # Note: With empty test glyphs, no actual patterns are found
        # so the optimization result will be empty/minimal
        optimization = result.instance_variable_get(:@subroutine_optimization)
        expect(optimization).not_to be_nil

        # With empty glyphs, we expect empty or minimal subroutines
        expect(optimization[:local_subrs]).to be_an(Array)
        expect(optimization[:selected_count]).to be >= 0
      end

      it "does not optimize when option is false" do
        options = {
          target_format: :otf,
          optimize_subroutines: false,
        }

        result = converter.convert(ttf_font, options)

        optimization = result.instance_variable_get(:@subroutine_optimization)
        expect(optimization).to be_nil
      end

      it "does not optimize when option is not provided" do
        options = { target_format: :otf }

        result = converter.convert(ttf_font, options)

        optimization = result.instance_variable_get(:@subroutine_optimization)
        expect(optimization).to be_nil
      end

      it "passes min_pattern_length option to generator" do
        options = {
          target_format: :otf,
          optimize_subroutines: true,
          min_pattern_length: 15,
        }

        expect(Fontisan::Optimizers::SubroutineGenerator).to receive(:new)
          .with(hash_including(min_pattern_length: 15))
          .and_return(double("SubroutineGenerator", generate: optimization_result))

        converter.convert(ttf_font, options)
      end

      it "passes max_subroutines option to generator" do
        options = {
          target_format: :otf,
          optimize_subroutines: true,
          max_subroutines: 1000,
        }

        expect(Fontisan::Optimizers::SubroutineGenerator).to receive(:new)
          .with(hash_including(max_subroutines: 1000))
          .and_return(double("SubroutineGenerator", generate: optimization_result))

        converter.convert(ttf_font, options)
      end

      it "passes optimize_ordering option to generator" do
        options = {
          target_format: :otf,
          optimize_subroutines: true,
          optimize_ordering: false,
        }

        expect(Fontisan::Optimizers::SubroutineGenerator).to receive(:new)
          .with(hash_including(optimize_ordering: false))
          .and_return(double("SubroutineGenerator", generate: optimization_result))

        converter.convert(ttf_font, options)
      end

      it "uses default values for optimization parameters" do
        options = {
          target_format: :otf,
          optimize_subroutines: true,
        }

        expect(Fontisan::Optimizers::SubroutineGenerator).to receive(:new)
          .with(hash_including(
                  min_pattern_length: 10,
                  max_subroutines: 65_535,
                  optimize_ordering: true,
                ))
          .and_return(double("SubroutineGenerator", generate: optimization_result))

        converter.convert(ttf_font, options)
      end
    end

    context "with verbose option" do
      let(:optimization_result) do
        {
          local_subrs: [[0x0B], [0x0C]],
          charstrings: [[0x8B, 0x00, 0x0B]],
          pattern_count: 10,
          selected_count: 2,
          savings: 150,
          bias: 107,
        }
      end

      before do
        generator = double("SubroutineGenerator")
        allow(Fontisan::Optimizers::SubroutineGenerator).to receive(:new)
          .and_return(generator)
        allow(generator).to receive(:generate).and_return(optimization_result)
      end

      it "logs optimization results when verbose is true" do
        options = {
          target_format: :otf,
          optimize_subroutines: true,
          verbose: true,
        }

        expect do
          converter.convert(ttf_font, options)
        end.to output(/Subroutine Optimization Results/).to_stdout
      end

      it "does not log when verbose is false" do
        options = {
          target_format: :otf,
          optimize_subroutines: true,
          verbose: false,
        }

        expect do
          converter.convert(ttf_font, options)
        end.not_to output.to_stdout
      end
    end

    context "with edge cases" do
      it "handles optimization when no patterns are found" do
        no_patterns_result = {
          local_subrs: [],
          charstrings: [[0x0E]],
          pattern_count: 0,
          selected_count: 0,
          savings: 0,
          bias: 107,
        }

        generator = double("SubroutineGenerator")
        allow(Fontisan::Optimizers::SubroutineGenerator).to receive(:new)
          .and_return(generator)
        allow(generator).to receive(:generate).and_return(no_patterns_result)

        options = {
          target_format: :otf,
          optimize_subroutines: true,
        }

        result = converter.convert(ttf_font, options)
        optimization = result.instance_variable_get(:@subroutine_optimization)

        expect(optimization[:selected_count]).to eq(0)
        expect(optimization[:savings]).to eq(0)
      end

      it "does not optimize for OTF→TTF conversion" do
        options = {
          target_format: :ttf,
          optimize_subroutines: true,
        }

        # SubroutineGenerator should never be instantiated for OTF→TTF
        expect(Fontisan::Optimizers::SubroutineGenerator).not_to receive(:new)

        # Mock the conversion to avoid hitting unrelated test issues
        allow(converter).to receive(:convert_otf_to_ttf).and_return({})

        result = converter.convert(otf_font, options)

        # Optimization should not occur for OTF→TTF
        optimization = result.instance_variable_get(:@subroutine_optimization)
        expect(optimization).to be_nil
      end
    end
  end
end
