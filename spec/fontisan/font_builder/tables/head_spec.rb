# frozen_string_literal: true

require "spec_helper"
require "fontisan/font_builder"

RSpec.describe Fontisan::FontBuilder::Tables::Head do
  let(:model) { Fontisan::FontBuilder::FontModel.new }
  let(:head) { described_class.new(model) }

  describe "#bytes" do
    it "returns exactly 54 bytes (per OpenType spec)" do
      expect(head.bytes.bytesize).to eq(54)
    end

    it "embeds the OpenType magic number at offset 12" do
      magic = head.bytes.unpack1("@12 N")
      expect(magic).to eq(0x5F0F3CF5)
    end

    it "embeds the configured unitsPerEm at offset 18" do
      model.units_per_em = 2048
      upem = head.bytes.unpack1("@18 n")
      expect(upem).to eq(2048)
    end

    it "zeroes checkSumAdjustment (Assembler patches it later)" do
      csa = head.bytes.unpack1("@8 N")
      expect(csa).to eq(0)
    end

    it "encodes the font version as Fixed 16.16" do
      model.font_version = "Version 17.0"
      revision = head.bytes.unpack1("@4 N")
      expect(revision).to eq(0x00110000)
    end

    it "falls back to 1.0 when the version string is unparseable" do
      model.font_version = "garbage"
      revision = head.bytes.unpack1("@4 N")
      expect(revision).to eq(0x00010000)
    end
  end
end

RSpec.describe Fontisan::FontBuilder::Tables::Assembler do
  let(:model) { Fontisan::FontBuilder::FontModel.new }
  let(:assembler) { described_class.new(model, format: :ttf) }

  describe "#write" do
    let(:tmpdir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

    it "writes a file at the given path" do
      path = File.join(tmpdir, "test.ttf")
      assembler.write(path)
      expect(File.exist?(path)).to be(true)
    end

    it "creates parent directories if missing" do
      path = File.join(tmpdir, "nested", "deep", "test.ttf")
      assembler.write(path)
      expect(File.exist?(path)).to be(true)
    end

    it "writes the TrueType sfnt version as the first uint32" do
      path = File.join(tmpdir, "test.ttf")
      assembler.write(path)
      sfnt = File.binread(path, 4).unpack1("N")
      expect(sfnt).to eq(0x00010000)
    end

    it "writes num_tables matching TABLE_ORDER length" do
      path = File.join(tmpdir, "test.ttf")
      assembler.write(path)
      num_tables = File.binread(path, 2, 4).unpack1("n")
      expect(num_tables).to eq(described_class::TABLE_ORDER.length)
    end

    it "writes a table directory entry for the head table" do
      path = File.join(tmpdir, "test.ttf")
      assembler.write(path)
      tag = File.binread(path, 4, 12)
      expect(tag).to eq("head")
    end
  end
end
