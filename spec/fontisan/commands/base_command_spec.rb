# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::BaseCommand do
  # Helper to build minimal valid font binary data
  def build_font_data
    sfnt_version = [0x00010000].pack("N")
    num_tables = [1].pack("n")
    search_range = [0].pack("n")
    entry_selector = [0].pack("n")
    range_shift = [0].pack("n")

    directory = sfnt_version + num_tables + search_range + entry_selector + range_shift

    # Add a minimal head table entry
    tag = "head"
    checksum = [0].pack("N")
    offset = [12 + 16].pack("N")
    length = [54].pack("N")

    head_data = "\u0000\u0001\u0000\u0000#{"\x00" * 50}" # Minimal head table

    directory + tag + checksum + offset + length + head_data
  end

  let(:temp_font_file) do
    file = Tempfile.new(["test-font", ".ttf"])
    file.binmode
    file.write(build_font_data)
    file.close
    file
  end

  after do
    temp_font_file&.unlink
  end

  describe "#initialize" do
    context "with a valid TTF file" do
      it "loads the font successfully" do
        command = described_class.new(temp_font_file.path)
        expect(command.send(:font)).to be_a(Fontisan::TrueTypeFont)
      end

      it "stores the font path" do
        command = described_class.new(temp_font_file.path)
        expect(command.send(:font_path)).to eq(temp_font_file.path)
      end

      it "stores the options" do
        options = { verbose: true }
        command = described_class.new(temp_font_file.path, options)
        expect(command.send(:options)).to eq(options)
      end
    end

    context "with a TTC file" do
      let(:ttc_file) { font_fixture_path("NotoSerifCJK", "NotoSerifCJK.ttc") }

      it "detects TTC files and uses default font_index" do
        skip "TTC fixture not downloaded" unless File.exist?(ttc_file)

        command = described_class.new(ttc_file)
        font = command.send(:font)

        expect(font).not_to be_nil
        expect([Fontisan::TrueTypeFont,
                Fontisan::OpenTypeFont]).to include(font.class)
      end

      it "uses custom font_index from options" do
        skip "TTC fixture not downloaded" unless File.exist?(ttc_file)

        command = described_class.new(ttc_file, { font_index: 1 })
        font = command.send(:font)

        expect(font).not_to be_nil
        expect([Fontisan::TrueTypeFont,
                Fontisan::OpenTypeFont]).to include(font.class)
      end
    end

    context "with an OTC file" do
      let(:otc_file) do
        font_fixture_path("NotoSerifCJK-VF",
                          "Variable/OTC/NotoSerifCJK-VF.otf.ttc")
      end

      it "detects OTC files and loads OpenType fonts" do
        skip "OTC fixture not downloaded" unless File.exist?(otc_file)

        command = described_class.new(otc_file)
        font = command.send(:font)

        expect(font).not_to be_nil
        expect(font).to be_a(Fontisan::OpenTypeFont)
      end

      it "uses custom font_index for OTC" do
        skip "OTC fixture not downloaded" unless File.exist?(otc_file)

        command = described_class.new(otc_file, { font_index: 0 })
        font = command.send(:font)

        expect(font).not_to be_nil
        expect(font).to be_a(Fontisan::OpenTypeFont)
      end
    end

    context "with error handling" do
      it "raises an error when file doesn't exist" do
        expect do
          described_class.new("nonexistent.ttf")
        end.to raise_error(Errno::ENOENT)
      end

      it "raises an error with invalid font data" do
        # Create invalid binary data file
        file = Tempfile.new(["invalid", ".ttf"])
        file.binmode
        file.write("invalid data")
        file.close

        expect do
          described_class.new(file.path)
        end.to raise_error(Fontisan::Error)

        file.unlink
      end

      it "raises UnsupportedFormatError for WOFF files" do
        # Create WOFF signature file
        file = Tempfile.new(["test", ".woff"])
        file.binmode
        file.write("wOFF#{"\x00" * 100}")
        file.close

        expect do
          described_class.new(file.path)
        end.to raise_error(Fontisan::UnsupportedFormatError,
                           /Unsupported font format: WOFF/)

        file.unlink
      end

      it "raises UnsupportedFormatError for WOFF2 files" do
        # Create WOFF2 signature file
        file = Tempfile.new(["test", ".woff2"])
        file.binmode
        file.write("wOF2#{"\x00" * 100}")
        file.close

        expect do
          described_class.new(file.path)
        end.to raise_error(Fontisan::UnsupportedFormatError,
                           /Unsupported font format: WOFF2/)

        file.unlink
      end
    end
  end

  describe "#run" do
    it "raises NotImplementedError" do
      command = described_class.new(temp_font_file.path)
      expect do
        command.run
      end.to raise_error(NotImplementedError,
                         "Subclasses must implement the run method")
    end
  end

  describe "protected attributes" do
    let(:command) { described_class.new(temp_font_file.path) }

    it "provides access to font_path" do
      expect(command.send(:font_path)).to eq(temp_font_file.path)
    end

    it "provides access to font" do
      expect(command.send(:font)).to be_a(Fontisan::TrueTypeFont)
    end

    it "provides access to options" do
      expect(command.send(:options)).to be_a(Hash)
    end
  end
end
