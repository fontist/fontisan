# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Hints::PostScriptHintExtractor do
  let(:extractor) { described_class.new }

  describe "#extract_from_font" do
    context "with an OpenType/CFF font" do
      # Note: We need a test font with CFF outlines
      # Using SourceSansPro-Regular.otf if available
      let(:font_path) { "spec/fixtures/fonts/SourceSansPro-Regular.otf" }

      before do
        skip "Test font not available" unless File.exist?(font_path)
      end

      let(:font) { Fontisan::FontLoader.load(font_path) }

      it "returns a HintSet" do
        result = extractor.extract_from_font(font)
        expect(result).to be_a(Fontisan::Models::HintSet)
      end

      it "sets format to postscript" do
        result = extractor.extract_from_font(font)
        expect(result.format).to eq("postscript")
      end

      it "extracts Private dict hints if present" do
        result = extractor.extract_from_font(font)
        expect(result.private_dict_hints).not_to be_nil
        # Should be valid JSON
        expect { JSON.parse(result.private_dict_hints) }.not_to raise_error
      end

      it "sets has_hints flag appropriately" do
        result = extractor.extract_from_font(font)
        # Most CFF fonts have hints
        expect(result.has_hints).to be true
      end
    end

    context "with a font without CFF table" do
      it "returns empty HintSet without errors" do
        font = instance_double(Fontisan::OpenTypeFont)
        allow(font).to receive(:has_table?).with("CFF ").and_return(false)
        allow(font).to receive(:table).and_return(nil)

        result = extractor.extract_from_font(font)
        expect(result).to be_a(Fontisan::Models::HintSet)
        expect(result.private_dict_hints).to eq("{}")
      end
    end
  end

  describe "#extract" do
    context "with CharString containing hints" do
      it "extracts hstem hints" do
        # CharString with hstem operator (1)
        # Format: position width 1 (hstem)
        charstring_bytes = [
          100 + 139, # position = 100 (single byte encoding)
          50 + 139,  # width = 50
          1          # hstem operator
        ]
        charstring = double("charstring", data: charstring_bytes, bytes: charstring_bytes)

        hints = extractor.extract(charstring)
        expect(hints).not_to be_empty
        expect(hints.first.type).to eq(:stem)
        expect(hints.first.data[:orientation]).to eq(:horizontal)
      end

      it "extracts vstem hints" do
        # CharString with vstem operator (3)
        charstring_bytes = [
          100 + 139, # position = 100
          50 + 139,  # width = 50
          3          # vstem operator
        ]
        charstring = double("charstring", data: charstring_bytes, bytes: charstring_bytes)

        hints = extractor.extract(charstring)
        expect(hints).not_to be_empty
        expect(hints.first.type).to eq(:stem)
        expect(hints.first.data[:orientation]).to eq(:vertical)
      end

      it "returns empty array for nil charstring" do
        hints = extractor.extract(nil)
        expect(hints).to be_empty
      end

      it "returns empty array for empty charstring" do
        charstring = double("charstring", data: "", bytes: [])
        hints = extractor.extract(charstring)
        expect(hints).to be_empty
      end
    end
  end

  describe "private methods" do
    describe "#extract_private_dict_hints" do
      it "extracts hint parameters from Private dict" do
        font = instance_double(Fontisan::OpenTypeFont)
        allow(font).to receive(:has_table?).with("CFF ").and_return(true)

        private_dict = double("private_dict")
        # Set up respond_to? to return true for supported methods
        allow(private_dict).to receive(:respond_to?) do |method|
          [:blue_values, :std_hw, :std_vw, :other_blues, :family_blues,
           :family_other_blues, :blue_scale, :blue_shift, :blue_fuzz,
           :stem_snap_h, :stem_snap_v, :force_bold, :language_group].include?(method)
        end
        # Set up actual methods
        allow(private_dict).to receive(:blue_values).and_return([-20, 0, 450, 470])
        allow(private_dict).to receive(:std_hw).and_return(68)
        allow(private_dict).to receive(:std_vw).and_return(88)
        allow(private_dict).to receive(:other_blues).and_return(nil)
        allow(private_dict).to receive(:family_blues).and_return(nil)
        allow(private_dict).to receive(:family_other_blues).and_return(nil)
        allow(private_dict).to receive(:blue_scale).and_return(nil)
        allow(private_dict).to receive(:blue_shift).and_return(nil)
        allow(private_dict).to receive(:blue_fuzz).and_return(nil)
        allow(private_dict).to receive(:stem_snap_h).and_return(nil)
        allow(private_dict).to receive(:stem_snap_v).and_return(nil)
        allow(private_dict).to receive(:force_bold).and_return(nil)
        allow(private_dict).to receive(:language_group).and_return(nil)

        cff_table = double("cff_table")
        allow(cff_table).to receive(:private_dict).with(0).and_return(private_dict)

        allow(font).to receive(:table).with("CFF ").and_return(cff_table)

        hints = extractor.send(:extract_private_dict_hints, font)
        expect(hints).to be_a(Hash)
        expect(hints[:blue_values]).to eq([-20, 0, 450, 470])
        expect(hints[:std_hw]).to eq(68)
        expect(hints[:std_vw]).to eq(88)
      end

      it "returns empty hash for font without CFF table" do
        font = instance_double(Fontisan::OpenTypeFont)
        allow(font).to receive(:has_table?).with("CFF ").and_return(false)

        hints = extractor.send(:extract_private_dict_hints, font)
        expect(hints).to eq({})
      end
    end
  end
end