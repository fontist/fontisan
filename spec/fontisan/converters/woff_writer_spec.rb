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

  describe "spec §4/§5/§6/§7 compliance" do
    let(:ttf_path) { File.join(fixture_path, "NotoSans/NotoSans-Regular.ttf") }
    let(:font) { Fontisan::FontLoader.load(ttf_path) }

    # Parse the WOFF header — offsets per WOFF 1.0 spec §4.
    def parse_header(woff)
      {
        signature: woff[0, 4].unpack1("N"),
        flavor: woff[4, 4].unpack1("N"),
        length: woff[8, 4].unpack1("N"),
        num_tables: woff[12, 2].unpack1("n"),
        reserved: woff[14, 2].unpack1("n"),
        total_sfnt_size: woff[16, 4].unpack1("N"),
        major_version: woff[20, 2].unpack1("n"),
        minor_version: woff[22, 2].unpack1("n"),
        meta_offset: woff[24, 4].unpack1("N"),
        meta_length: woff[28, 4].unpack1("N"),
        meta_orig_length: woff[32, 4].unpack1("N"),
        priv_offset: woff[36, 4].unpack1("N"),
        priv_length: woff[40, 4].unpack1("N"),
      }
    end

    def parse_table_entries(woff)
      h = parse_header(woff)
      entries = []
      h[:num_tables].times do |i|
        pos = 44 + (i * 20)
        entries << {
          tag: woff[pos, 4],
          offset: woff[pos + 4, 4].unpack1("N"),
          comp_length: woff[pos + 8, 4].unpack1("N"),
          orig_length: woff[pos + 12, 4].unpack1("N"),
          orig_checksum: woff[pos + 16, 4].unpack1("N"),
        }
      end
      [h, entries]
    end

    it "header.signature is 'wOFF' (0x774F4646)" do
      woff = writer.convert(font)
      expect(parse_header(woff)[:signature]).to eq(0x774F4646)
    end

    it "header.reserved is 0 (spec §4: MUST be zero)" do
      woff = writer.convert(font)
      expect(parse_header(woff)[:reserved]).to eq(0)
    end

    it "header.length equals actual file size" do
      woff = writer.convert(font)
      expect(parse_header(woff)[:length]).to eq(woff.bytesize)
    end

    # Regression: metaOffset header field used to point to start of font
    # tables (data_offset) instead of the actual metadata location after
    # the tables. Decoders following the header field got table bytes
    # instead of the metadata XML.
    it "metaOffset points to actual metadata location (not start of tables)" do
      woff = writer.convert(font, metadata_xml: "<metadata>x</metadata>")
      h = parse_header(woff)

      # Metadata must come AFTER all font tables.
      _, entries = parse_table_entries(woff)
      last_table_end = entries.max_by { |e| e[:offset] }[:offset]
      expect(h[:meta_offset]).to be > last_table_end,
                                 "metaOffset (#{h[:meta_offset]}) must point past the last table (ends at #{last_table_end})"

      # And the bytes at metaOffset must zlib-inflate to the metadata XML.
      require "zlib"
      meta_bytes = woff[h[:meta_offset], h[:meta_length]]
      decompressed = Zlib::Inflate.inflate(meta_bytes)
      expect(decompressed).to eq("<metadata>x</metadata>")
    end

    it "metaOffset and metaLength are 0 when no metadata" do
      woff = writer.convert(font)
      h = parse_header(woff)
      expect(h[:meta_offset]).to eq(0)
      expect(h[:meta_length]).to eq(0)
      expect(h[:meta_orig_length]).to eq(0)
    end

    it "privOffset and privLength are 0 when no private data" do
      woff = writer.convert(font)
      h = parse_header(woff)
      expect(h[:priv_offset]).to eq(0)
      expect(h[:priv_length]).to eq(0)
    end

    # Regression: tables used to follow each other contiguously without
    # 4-byte alignment padding. Spec §5/§6: "Font data tables in the WOFF
    # file have the same requirement: they MUST begin on 4-byte boundaries
    # and be zero-padded to the next 4-byte boundary".
    it "every font table starts on a 4-byte boundary" do
      woff = writer.convert(font)
      _, entries = parse_table_entries(woff)
      entries.each do |e|
        expect(e[:offset] % 4).to eq(0),
                                  "table #{e[:tag]} starts at offset #{e[:offset]} (not 4-byte aligned)"
      end
    end

    it "tables are zero-padded to next 4-byte boundary" do
      woff = writer.convert(font)
      _, entries = parse_table_entries(woff)
      entries.each_cons(2) do |cur, nxt|
        end_off = cur[:offset] + cur[:comp_length]
        expected_padding = (4 - (cur[:comp_length] % 4)) % 4
        actual_padding = nxt[:offset] - end_off
        expect(actual_padding).to eq(expected_padding),
                                  "padding after #{cur[:tag]} should be #{expected_padding} bytes, got #{actual_padding}"

        # Padding bytes must all be zero
        woff[end_off, actual_padding].each_byte do |b|
          expect(b).to eq(0), "non-zero padding byte after #{cur[:tag]}"
        end
      end
    end

    # Spec §7: "If present, the metadata MUST be compressed; it is never
    # stored in uncompressed form."
    it "metadata is zlib-compressed even when uncompressed: true" do
      woff = writer.convert(font, uncompressed: true,
                                  metadata_xml: "<metadata>test</metadata>")
      h = parse_header(woff)
      require "zlib"
      meta_bytes = woff[h[:meta_offset], h[:meta_length]]
      expect { Zlib::Inflate.inflate(meta_bytes) }.not_to raise_error,
                                                          "metadata must be zlib-compressed even with uncompressed: true"
    end

    # Spec §4: "totalSfntSize: Total size needed for the uncompressed font
    # data, including the sfnt header, directory, and font tables (including
    # padding)."
    it "totalSfntSize includes per-table 4-byte padding" do
      woff = writer.convert(font)
      h, entries = parse_table_entries(woff)

      sfnt_header_size = 12
      sfnt_dir_size = entries.size * 16
      sfnt_tables_with_padding = entries.sum do |e|
        e[:orig_length] + ((4 - (e[:orig_length] % 4)) % 4)
      end
      expected = sfnt_header_size + sfnt_dir_size + sfnt_tables_with_padding

      expect(h[:total_sfnt_size]).to eq(expected),
                                     "totalSfntSize must include per-table 4-byte padding"
    end

    it "private data is preserved verbatim at privOffset" do
      private_data = "secret bytes \x00\x01\x02".b
      woff = writer.convert(font, private_data:)
      h = parse_header(woff)
      actual = woff[h[:priv_offset], h[:priv_length]]
      expect(actual).to eq(private_data)
    end

    it "preserves input font table order (spec §6)" do
      woff = writer.convert(font)
      _, entries = parse_table_entries(woff)
      actual_order = entries.map { |e| e[:tag].force_encoding("UTF-8") }
      expected_order = font.table_names
      expect(actual_order).to eq(expected_order),
                              "tables must be stored in input font order, not sorted alphabetically"
    end

    # Cross-validation: fontTools can decode our output.
    it "fontTools decodes the WOFF and reads all tables", :python do
      skip "fontTools not available" unless python_fonttools?

      woff = writer.convert(font, metadata_xml: "<metadata>test</metadata>")
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff")
        File.binwrite(path, woff)
        script = File.join(dir, "check.py")
        File.write(script, <<~PY)
          import sys
          from fontTools.ttLib import TTFont
          t = TTFont(sys.argv[1])
          print("OK", sorted(t.keys()))
        PY
        output = `python3 #{script} #{path} 2>&1`
        expect($?).to be_success, "fontTools failed:\n#{output}"
        expect(output).to include("OK")
      end
    end
  end
end
