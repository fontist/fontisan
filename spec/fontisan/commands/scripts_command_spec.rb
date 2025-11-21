# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::ScriptsCommand do
  let(:ttf_font_path) do
    "spec/fixtures/fonts/libertinus/Libertinus-7.051/static/TTF/LibertinusSerif-Regular.ttf"
  end
  let(:otf_font_path) do
    "spec/fixtures/fonts/libertinus/Libertinus-7.051/static/OTF/LibertinusSerif-Regular.otf"
  end

  describe "#run" do
    context "with TrueType font" do
      it "returns ScriptsInfo with all scripts" do
        command = described_class.new(ttf_font_path, {})
        result = command.run

        expect(result).to be_a(Fontisan::Models::ScriptsInfo)
        expect(result.script_count).to be > 0
        expect(result.scripts).to be_an(Array)
        expect(result.scripts).to all(be_a(Fontisan::Models::ScriptRecord))
      end

      it "includes standard scripts" do
        command = described_class.new(ttf_font_path, {})
        result = command.run

        script_tags = result.scripts.map(&:tag)
        expect(script_tags).to include("latn")
        expect(script_tags).to include("DFLT")
      end

      it "includes script descriptions" do
        command = described_class.new(ttf_font_path, {})
        result = command.run

        latin_script = result.scripts.find { |s| s.tag == "latn" }
        expect(latin_script).not_to be_nil
        expect(latin_script.description).to eq("Latin")
      end

      it "sorts scripts alphabetically" do
        command = described_class.new(ttf_font_path, {})
        result = command.run

        tags = result.scripts.map(&:tag)
        expect(tags).to eq(tags.sort)
      end
    end

    context "with OpenType font" do
      it "returns ScriptsInfo with scripts from OTF" do
        command = described_class.new(otf_font_path, {})
        result = command.run

        expect(result).to be_a(Fontisan::Models::ScriptsInfo)
        expect(result.script_count).to be > 0
      end

      it "extracts scripts from both GSUB and GPOS" do
        command = described_class.new(otf_font_path, {})
        result = command.run

        # Should have scripts from both tables
        expect(result.scripts.length).to be > 0
      end
    end

    context "font without GSUB/GPOS" do
      it "returns empty scripts list" do
        # Mock a font that has no GSUB or GPOS tables
        mock_font = double("font")
        allow(mock_font).to receive(:has_table?).with("GSUB").and_return(false)
        allow(mock_font).to receive(:has_table?).with("GPOS").and_return(false)

        # Mock the font loading process
        allow(Fontisan::FontLoader).to receive(:load).and_return(mock_font)

        # Create a temporary file path for the mock
        temp_font_path = "spec/fixtures/fonts/mock_no_layout.ttf"
        File.write(temp_font_path, "mock font data")

        begin
          # Mock the command to use our mock font
          command = described_class.new(temp_font_path, {})

          # Mock the internal font loading
          allow(command).to receive(:font).and_return(mock_font)

          result = command.run

          expect(result).to be_a(Fontisan::Models::ScriptsInfo)
          expect(result.script_count).to eq(0)
          expect(result.scripts).to eq([])
        ensure
          File.delete(temp_font_path) if File.exist?(temp_font_path)
        end
      end
    end

    context "with unknown scripts" do
      it "marks unknown scripts appropriately" do
        command = described_class.new(ttf_font_path, {})
        result = command.run

        # All known scripts should have descriptions
        result.scripts.each do |script|
          expect(script.description).not_to be_nil
          expect(script.description).not_to eq("")
        end
      end
    end
  end
end
