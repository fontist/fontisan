# frozen_string_literal: true

require "spec_helper"
require "fontisan/parsers/dfont_parser"

RSpec.describe Fontisan::Parsers::DfontParser do
  let(:dfont_path) { font_fixture_path("Tamsyn", "Tamsyn7x13.dfont") }
  let(:valid_sfnt_signatures) { ["\x00\x01\x00\x00", "true", "OTTO"] }

  describe ".dfont?" do
    context "with valid dfont file" do
      it "returns true for valid dfont resource fork" do
        File.open(dfont_path, "rb") do |io|
          expect(described_class.dfont?(io)).to be true
        end
      end

      it "rewinds IO after checking" do
        File.open(dfont_path, "rb") do |io|
          described_class.dfont?(io)
          expect(io.pos).to eq(0)
        end
      end
    end

    context "with invalid files" do
      it "returns false for too-short file" do
        io = StringIO.new("short")
        expect(described_class.dfont?(io)).to be false
      end

      it "returns false for empty file" do
        io = StringIO.new("")
        expect(described_class.dfont?(io)).to be false
      end
    end
  end

  describe ".sfnt_count" do
    it "returns number of sfnt resources in dfont" do
      File.open(dfont_path, "rb") do |io|
        count = described_class.sfnt_count(io)
        expect(count).to be >= 1
        expect(count).to be_a(Integer)
      end
    end
  end

  describe ".extract_sfnt" do
    context "with valid dfont" do
      it "extracts SFNT data successfully" do
        File.open(dfont_path, "rb") do |io|
          sfnt_data = described_class.extract_sfnt(io)

          expect(sfnt_data).to be_a(String)
          expect(sfnt_data.length).to be > 0

          # Check for valid SFNT signature (true or 0x00010000)
          signature = sfnt_data[0..3]
          expect(valid_sfnt_signatures).to include(signature)
        end
      end

      it "extracts first font by default" do
        File.open(dfont_path, "rb") do |io|
          sfnt_data = described_class.extract_sfnt(io)
          sfnt_data_index_0 = described_class.extract_sfnt(io, index: 0)

          expect(sfnt_data).to eq(sfnt_data_index_0)
        end
      end

      it "does not close the IO after extraction" do
        File.open(dfont_path, "rb") do |io|
          described_class.extract_sfnt(io)
          expect(io).not_to be_closed
        end
      end
    end

    context "with invalid parameters" do
      it "raises error for out of range index" do
        File.open(dfont_path, "rb") do |io|
          expect do
            described_class.extract_sfnt(io, index: 999)
          end.to raise_error(Fontisan::InvalidFontError, /out of range/)
        end
      end
    end
  end

  describe ".parse_header" do
    it "parses resource fork header correctly" do
      File.open(dfont_path, "rb") do |io|
        header = described_class.send(:parse_header, io)

        expect(header).to be_a(Fontisan::Parsers::DfontParser::ResourceHeader)
        expect(header.resource_data_offset).to be > 0
        expect(header.resource_map_offset).to be > header.resource_data_offset
        expect(header.resource_data_length).to be > 0
        expect(header.resource_map_length).to be > 0
      end
    end
  end

  describe ".find_sfnt_resources" do
    it "finds sfnt resources in resource map" do
      File.open(dfont_path, "rb") do |io|
        header = described_class.send(:parse_header, io)
        resources = described_class.send(:find_sfnt_resources, io, header)

        expect(resources).to be_an(Array)
        expect(resources).not_to be_empty

        resources.each do |resource|
          expect(resource).to have_key(:id)
          expect(resource).to have_key(:offset)
          expect(resource[:offset]).to be >= 0
        end
      end
    end
  end

  describe ".extract_resource_data" do
    it "extracts resource data at specific offset" do
      File.open(dfont_path, "rb") do |io|
        header = described_class.send(:parse_header, io)
        resources = described_class.send(:find_sfnt_resources, io, header)

        resource_info = resources.first
        data = described_class.send(:extract_resource_data, io, header, resource_info)

        expect(data).to be_a(String)
        expect(data.length).to be > 0
      end
    end
  end
end
