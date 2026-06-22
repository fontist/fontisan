# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Fontisan::Converters::WoffWriter do
  let(:writer) { described_class.new }
  let(:fixture_path) { File.join(__dir__, "../../fixtures/fonts") }

  describe "#convert" do
    context "with TrueType font" do
      it "converts TTF to WOFF successfully" do
        ttf_path = File.join(fixture_path, "NotoSans/NotoSans-Regular.ttf")
        font = Fontisan::FontLoader.load(ttf_path)

        result = writer.convert(font)

        expect(result).to be_a(String)
        expect(result.bytesize).to be > 0

        # Check WOFF signature
        signature = result[0..3].unpack1("N")
        expect(signature).to eq(0x774F4646) # 'wOFF'
      end

      it "produces valid WOFF that can be read back" do
        ttf_path = File.join(fixture_path, "NotoSans/NotoSans-Regular.ttf")
        font = Fontisan::FontLoader.load(ttf_path)

        woff_data = writer.convert(font)

        # Write to temp file and read back
        Tempfile.create(["test", ".woff"]) do |f|
          f.binmode
          f.write(woff_data)
          f.close

          # Read back as WOFF
          woff_font = Fontisan::WoffFont.from_file(f.path)

          expect(woff_font).to be_valid
          expect(woff_font.truetype?).to be true
          expect(woff_font.table_names.sort).to eq(font.table_names.sort)
        end
      end
    end

    context "with OpenType/CFF font" do
      it "converts OTF to WOFF successfully" do
        otf_path = File.join(fixture_path,
                             "MonaSans/mona-sans-2.0.8/fonts/static/otf/MonaSans-Regular.otf")

        font = Fontisan::FontLoader.load(otf_path)
        result = writer.convert(font)

        expect(result).to be_a(String)
        expect(result.bytesize).to be > 0

        # Check WOFF signature
        signature = result[0..3].unpack1("N")
        expect(signature).to eq(0x774F4646) # 'wOFF'

        # Check flavor is 'OTTO' for CFF
        flavor = result[4..7].unpack1("N")
        expect(flavor).to eq(0x4F54544F) # 'OTTO'
      end
    end

    context "with compression options" do
      it "respects zlib_level per call" do
        ttf_path = File.join(fixture_path, "NotoSans/NotoSans-Regular.ttf")
        font = Fontisan::FontLoader.load(ttf_path)

        result_max = writer.convert(font, zlib_level: 9)
        result_min = writer.convert(font, zlib_level: 1)

        # Higher compression should produce smaller file
        expect(result_max.bytesize).to be < result_min.bytesize
      end
    end
  end

  describe "#convert with new options DSL" do
    let(:ttf_path) { File.join(fixture_path, "NotoSans/NotoSans-Regular.ttf") }
    let(:font) { Fontisan::FontLoader.load(ttf_path) }

    it "accepts zlib_level: 9 and produces a valid WOFF" do
      result = writer.convert(font, zlib_level: 9)

      expect(result).to be_a(String)
      signature = result[0..3].unpack1("N")
      expect(signature).to eq(0x774F4646) # 'wOFF'
    end

    it "rejects out-of-range zlib_level (ArgumentError before writing)" do
      expect do
        writer.convert(font, zlib_level: 99)
      end.to raise_error(ArgumentError, /zlib_level/)
    end

    context "with uncompressed: true" do
      it "produces WOFF where every table entry has compLength == origLength" do
        woff_data = writer.convert(font, uncompressed: true)

        # Parse the table directory (starts at offset 44, 20 bytes per entry)
        num_tables = woff_data[12..13].unpack1("n")
        directory_offset = 44
        entries = (0...num_tables).map do |i|
          offset = directory_offset + (i * 20)
          {
            tag: woff_data[offset, 4],
            offset_val: woff_data[offset + 4, 4].unpack1("N"),
            comp_length: woff_data[offset + 8, 4].unpack1("N"),
            orig_length: woff_data[offset + 12, 4].unpack1("N"),
          }
        end

        entries.each do |e|
          expect(e[:comp_length]).to eq(e[:orig_length]),
                                     "table #{e[:tag]} should have compLength == origLength"
        end
      end
    end

    context "with compression_threshold higher than any table" do
      it "keeps every table entry's compLength == origLength" do
        # Threshold is inclusive lower bound: tables with size >= threshold
        # are compressed. A threshold larger than any table means nothing
        # gets compressed.
        woff_data = writer.convert(font, compression_threshold: 10_000_000)

        num_tables = woff_data[12..13].unpack1("n")
        directory_offset = 44
        entries = (0...num_tables).map do |i|
          offset = directory_offset + (i * 20)
          {
            tag: woff_data[offset, 4],
            comp_length: woff_data[offset + 8, 4].unpack1("N"),
            orig_length: woff_data[offset + 12, 4].unpack1("N"),
          }
        end

        entries.each do |e|
          expect(e[:comp_length]).to eq(e[:orig_length])
        end
      end
    end
  end

  describe "#supported_conversions" do
    it "returns TTF to WOFF" do
      expect(writer.supported_conversions).to include(%i[ttf woff])
    end

    it "returns OTF to WOFF" do
      expect(writer.supported_conversions).to include(%i[otf woff])
    end
  end

  describe "offset calculation bug" do
    it "correctly sets metadata_offset when no metadata present" do
      ttf_path = File.join(fixture_path, "NotoSans/NotoSans-Regular.ttf")
      font = Fontisan::FontLoader.load(ttf_path)

      woff_data = writer.convert(font)

      # Parse header
      header_data = woff_data[0..43]
      meta_offset = header_data[28..31].unpack1("N")
      meta_length = header_data[32..35].unpack1("N")

      # When no metadata, both should be 0
      expect(meta_offset).to eq(0)
      expect(meta_length).to eq(0)
    end

    it "correctly sets private_offset when no private data present" do
      ttf_path = File.join(fixture_path, "NotoSans/NotoSans-Regular.ttf")
      font = Fontisan::FontLoader.load(ttf_path)

      woff_data = writer.convert(font)

      # Parse header
      header_data = woff_data[0..43]
      priv_offset = header_data[40..43].unpack1("N")

      # When no private data, offset should be 0
      expect(priv_offset).to eq(0)
    end
  end
end
