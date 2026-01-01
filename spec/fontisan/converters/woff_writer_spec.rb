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
        otf_path = File.join(fixture_path, "MonaSans/mona-sans-2.0.8/fonts/static/otf/MonaSans-Regular.otf")
        skip "OTF font not found: #{otf_path}" unless File.exist?(otf_path)

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
      it "respects compression level" do
        ttf_path = File.join(fixture_path, "NotoSans/NotoSans-Regular.ttf")
        font = Fontisan::FontLoader.load(ttf_path)

        writer_level_9 = described_class.new(compression_level: 9)
        writer_level_1 = described_class.new(compression_level: 1)

        result_max = writer_level_9.convert(font)
        result_min = writer_level_1.convert(font)

        # Higher compression should produce smaller file
        expect(result_max.bytesize).to be < result_min.bytesize
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
