# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/instance_writer"
require "fontisan/font_writer"
require "fontisan/converters/outline_converter"
require "fontisan/converters/woff_writer"
require "tempfile"

RSpec.describe Fontisan::Variation::InstanceWriter do
  let(:minimal_tables) do
    {
      "head" => "\x00" * 54,
      "hhea" => "\x00" * 36,
      "maxp" => [0x00010000, 1].pack("Nn"),
      "glyf" => "",
      "loca" => [0, 0].pack("N*"),
    }
  end

  let(:cff_tables) do
    {
      "head" => "\x00" * 54,
      "hhea" => "\x00" * 36,
      "maxp" => [0x00005000, 1].pack("Nn"),
      "CFF " => "\x01\x00\x04\x04",
    }
  end

  describe ".write" do
    it "writes instance to TTF file" do
      Tempfile.create(["test", ".ttf"]) do |file|
        bytes = described_class.write(minimal_tables, file.path)
        expect(bytes).to be > 0
        expect(File.exist?(file.path)).to be true
        expect(File.size(file.path)).to eq(bytes)
      end
    end

    it "writes instance to OTF file" do
      Tempfile.create(["test", ".otf"]) do |file|
        bytes = described_class.write(cff_tables, file.path)
        expect(bytes).to be > 0
        expect(File.exist?(file.path)).to be true
      end
    end

    it "detects format from extension" do
      Tempfile.create(["test", ".ttf"]) do |file|
        described_class.write(minimal_tables, file.path)
        data = File.binread(file.path)
        # Check SFNT version for TrueType (0x00010000)
        sfnt_version = data[0, 4].unpack1("N")
        expect(sfnt_version).to eq(0x00010000)
      end
    end

    it "uses explicit format option" do
      Tempfile.create(["test", ".bin"]) do |file|
        described_class.write(minimal_tables, file.path, format: :ttf)
        expect(File.exist?(file.path)).to be true
      end
    end
  end

  describe "#initialize" do
    it "initializes with valid tables" do
      writer = described_class.new(minimal_tables)
      expect(writer.tables).to eq(minimal_tables)
    end

    it "raises error for nil tables" do
      expect { described_class.new(nil) }.to raise_error(
        ArgumentError,
        "Tables cannot be nil",
      )
    end

    it "raises error for non-Hash tables" do
      expect { described_class.new("invalid") }.to raise_error(
        ArgumentError,
        /Tables must be a Hash/,
      )
    end

    it "raises error for empty tables" do
      expect { described_class.new({}) }.to raise_error(
        ArgumentError,
        "Tables cannot be empty",
      )
    end

    it "raises error for missing required head table" do
      tables = minimal_tables.dup
      tables.delete("head")
      expect { described_class.new(tables) }.to raise_error(
        ArgumentError,
        "Missing required table: head",
      )
    end

    it "raises error for missing required hhea table" do
      tables = minimal_tables.dup
      tables.delete("hhea")
      expect { described_class.new(tables) }.to raise_error(
        ArgumentError,
        "Missing required table: hhea",
      )
    end

    it "raises error for missing required maxp table" do
      tables = minimal_tables.dup
      tables.delete("maxp")
      expect { described_class.new(tables) }.to raise_error(
        ArgumentError,
        "Missing required table: maxp",
      )
    end
  end

  describe "#write" do
    let(:writer) { described_class.new(minimal_tables) }

    it "writes TTF format by default" do
      Tempfile.create(["test", ".ttf"]) do |file|
        bytes = writer.write(file.path)
        expect(bytes).to be > 0
      end
    end

    it "writes OTF format" do
      writer = described_class.new(cff_tables)
      Tempfile.create(["test", ".otf"]) do |file|
        bytes = writer.write(file.path)
        expect(bytes).to be > 0
      end
    end

    it "raises error for unsupported extension" do
      writer = described_class.new(minimal_tables)
      expect { writer.write("test.xyz") }.to raise_error(
        ArgumentError,
        /Cannot determine format from extension/,
      )
    end

    it "raises error for unsupported format" do
      writer = described_class.new(minimal_tables, format: :invalid)
      Tempfile.create(["test", ".bin"]) do |file|
        expect { writer.write(file.path) }.to raise_error(
          ArgumentError,
          /Unsupported format: invalid/,
        )
      end
    end
  end

  describe "format detection" do
    it "detects TTF format from glyf table" do
      writer = described_class.new(minimal_tables)
      Tempfile.create(["test", ".ttf"]) do |file|
        writer.write(file.path)
        data = File.binread(file.path)
        sfnt_version = data[0, 4].unpack1("N")
        expect(sfnt_version).to eq(0x00010000)
      end
    end

    it "detects OTF format from CFF table" do
      writer = described_class.new(cff_tables)
      Tempfile.create(["test", ".otf"]) do |file|
        writer.write(file.path)
        data = File.binread(file.path)
        sfnt_version = data[0, 4].unpack1("N")
        expect(sfnt_version).to eq(0x4F54544F)
      end
    end

    it "detects OTF format from CFF2 table" do
      cff2_tables = minimal_tables.dup
      cff2_tables.delete("glyf")
      cff2_tables["CFF2"] = "\x02\x00\x05\x00"
      writer = described_class.new(cff2_tables)
      Tempfile.create(["test", ".otf"]) do |file|
        writer.write(file.path)
        data = File.binread(file.path)
        sfnt_version = data[0, 4].unpack1("N")
        expect(sfnt_version).to eq(0x4F54544F)
      end
    end

    it "uses source_format option when no outline tables present" do
      tables = {
        "head" => "\x00" * 54,
        "hhea" => "\x00" * 36,
        "maxp" => [0x00010000, 1].pack("Nn"),
      }
      writer = described_class.new(tables, source_format: :otf)
      Tempfile.create(["test", ".otf"]) do |file|
        writer.write(file.path)
        expect(File.exist?(file.path)).to be true
      end
    end
  end

  describe "WOFF output" do
    it "writes WOFF format" do
      writer = described_class.new(minimal_tables)
      Tempfile.create(["test", ".woff"]) do |file|
        bytes = writer.write(file.path)
        expect(bytes).to be > 0

        # Verify WOFF signature
        data = File.binread(file.path)
        signature = data[0, 4].unpack1("N")
        expect(signature).to eq(0x774F4646) # 'wOFF'
      end
    end

    it "writes WOFF from CFF tables" do
      writer = described_class.new(cff_tables)
      Tempfile.create(["test", ".woff"]) do |file|
        bytes = writer.write(file.path)
        expect(bytes).to be > 0

        data = File.binread(file.path)
        signature = data[0, 4].unpack1("N")
        expect(signature).to eq(0x774F4646)
      end
    end
  end

  describe "WOFF2 output" do
    it "raises error for WOFF2 (not yet implemented)" do
      writer = described_class.new(minimal_tables)
      Tempfile.create(["test", ".woff2"]) do |file|
        expect { writer.write(file.path) }.to raise_error(
          Fontisan::Error,
          /WOFF2 output not yet implemented/,
        )
      end
    end
  end

  describe "SFNT version selection" do
    it "uses TRUETYPE version for TTF" do
      writer = described_class.new(minimal_tables)
      Tempfile.create(["test", ".ttf"]) do |file|
        writer.write(file.path)
        data = File.binread(file.path)
        sfnt_version = data[0, 4].unpack1("N")
        expect(sfnt_version).to eq(0x00010000)
      end
    end

    it "uses CFF version for OTF" do
      writer = described_class.new(cff_tables)
      Tempfile.create(["test", ".otf"]) do |file|
        writer.write(file.path)
        data = File.binread(file.path)
        sfnt_version = data[0, 4].unpack1("N")
        expect(sfnt_version).to eq(0x4F54544F)
      end
    end

    it "allows SFNT version override" do
      custom_version = 0x12345678
      writer = described_class.new(minimal_tables,
                                   sfnt_version: custom_version)
      Tempfile.create(["test", ".ttf"]) do |file|
        writer.write(file.path)
        data = File.binread(file.path)
        sfnt_version = data[0, 4].unpack1("N")
        expect(sfnt_version).to eq(custom_version)
      end
    end
  end

  describe "format conversion" do
    it "does not convert for same format (TTF → TTF)" do
      writer = described_class.new(minimal_tables)
      Tempfile.create(["test", ".ttf"]) do |file|
        writer.write(file.path)
        expect(File.exist?(file.path)).to be true
      end
    end

    it "does not convert for same format (OTF → OTF)" do
      writer = described_class.new(cff_tables)
      Tempfile.create(["test", ".otf"]) do |file|
        writer.write(file.path)
        expect(File.exist?(file.path)).to be true
      end
    end

    it "does not convert for WOFF output" do
      writer = described_class.new(minimal_tables)
      Tempfile.create(["test", ".woff"]) do |file|
        writer.write(file.path)
        expect(File.exist?(file.path)).to be true
      end
    end
  end

  describe "integration with components" do
    it "uses FontWriter for TTF output" do
      expect(Fontisan::FontWriter).to receive(:write_to_file).and_call_original
      writer = described_class.new(minimal_tables)
      Tempfile.create(["test", ".ttf"]) do |file|
        writer.write(file.path)
      end
    end

    it "uses FontWriter for OTF output" do
      expect(Fontisan::FontWriter).to receive(:write_to_file).and_call_original
      writer = described_class.new(cff_tables)
      Tempfile.create(["test", ".otf"]) do |file|
        writer.write(file.path)
      end
    end

    it "uses WoffWriter for WOFF output" do
      expect_any_instance_of(
        Fontisan::Converters::WoffWriter,
      ).to receive(:convert).and_call_original

      writer = described_class.new(minimal_tables)
      Tempfile.create(["test", ".woff"]) do |file|
        writer.write(file.path)
      end
    end
  end
end
