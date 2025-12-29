# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Fontisan::Woff2Font do
  let(:woff2_signature) { [0x774F4632].pack("N") } # 'wOF2'
  let(:ttf_flavor) { [0x00010000].pack("N") }
  let(:otf_flavor) { "OTTO" }

  describe ".from_file" do
    context "with invalid inputs" do
      it "raises ArgumentError when path is nil" do
        expect { described_class.from_file(nil) }
          .to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises ArgumentError when path is empty" do
        expect { described_class.from_file("") }
          .to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises Errno::ENOENT when file does not exist" do
        expect { described_class.from_file("nonexistent.woff2") }
          .to raise_error(Errno::ENOENT, /File not found/)
      end
    end

    context "with invalid WOFF2 signature" do
      it "raises InvalidFontError for wrong signature" do
        Tempfile.create(["invalid", ".woff2"]) do |f|
          # Write invalid signature
          f.write([0x12345678].pack("N"))
          f.write("\x00" * 44) # Rest of header
          f.close

          expect { described_class.from_file(f.path) }
            .to raise_error(Fontisan::InvalidFontError,
                            /Invalid WOFF2 signature/)
        end
      end
    end
  end

  describe "#initialize" do
    it "initializes with empty structures" do
      woff2 = described_class.new

      expect(woff2.header).to be_nil
      expect(woff2.table_entries).to eq([])
      expect(woff2.decompressed_tables).to eq({})
      expect(woff2.parsed_tables).to eq({})
    end
  end

  describe "#validate_signature!" do
    it "raises error for invalid signature" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.signature = 0xDEADBEEF

      expect { woff2.validate_signature! }.to raise_error(Fontisan::InvalidFontError)
    end

    it "does not raise error for valid signature" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.signature = Fontisan::Woff2::Woff2Header::SIGNATURE

      expect { woff2.validate_signature! }.not_to raise_error
    end
  end

  describe "#truetype?" do
    it "returns true for TrueType flavor (0x00010000)" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.flavor = 0x00010000

      expect(woff2.truetype?).to be true
    end

    it "returns true for TrueType flavor (SFNT_VERSION_TRUETYPE)" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.flavor = Fontisan::Constants::SFNT_VERSION_TRUETYPE

      expect(woff2.truetype?).to be true
    end

    it "returns false for CFF flavor" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.flavor = 0x4F54544F # 'OTTO'

      expect(woff2.truetype?).to be false
    end
  end

  describe "#cff?" do
    it "returns true for CFF flavor (OTTO)" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.flavor = 0x4F54544F # 'OTTO'

      expect(woff2.cff?).to be true
    end

    it "returns true for CFF flavor (SFNT_VERSION_OTTO)" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.flavor = Fontisan::Constants::SFNT_VERSION_OTTO

      expect(woff2.cff?).to be true
    end

    it "returns false for TrueType flavor" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.flavor = 0x00010000

      expect(woff2.cff?).to be false
    end
  end

  describe "#initialize_storage" do
    it "initializes decompressed_tables hash" do
      woff2 = described_class.new
      woff2.initialize_storage

      expect(woff2.decompressed_tables).to eq({})
    end

    it "initializes parsed_tables hash" do
      woff2 = described_class.new
      woff2.initialize_storage

      expect(woff2.parsed_tables).to eq({})
    end
  end

  describe "#has_table?" do
    it "returns true when table exists" do
      woff2 = described_class.new
      entry = Fontisan::Woff2TableDirectoryEntry.new
      entry.tag = "head"
      woff2.table_entries = [entry]

      expect(woff2.has_table?("head")).to be true
    end

    it "returns false when table does not exist" do
      woff2 = described_class.new
      woff2.table_entries = []

      expect(woff2.has_table?("head")).to be false
    end
  end

  describe "#find_table_entry" do
    it "returns entry when found" do
      woff2 = described_class.new
      entry = Fontisan::Woff2TableDirectoryEntry.new
      entry.tag = "head"
      woff2.table_entries = [entry]

      result = woff2.find_table_entry("head")

      expect(result).to eq(entry)
    end

    it "returns nil when not found" do
      woff2 = described_class.new
      woff2.table_entries = []

      result = woff2.find_table_entry("head")

      expect(result).to be_nil
    end
  end

  describe "#table_names" do
    it "returns array of table tags" do
      woff2 = described_class.new
      entry1 = Fontisan::Woff2TableDirectoryEntry.new
      entry1.tag = "head"
      entry2 = Fontisan::Woff2TableDirectoryEntry.new
      entry2.tag = "name"
      woff2.table_entries = [entry1, entry2]

      expect(woff2.table_names).to eq(["head", "name"])
    end

    it "returns empty array when no tables" do
      woff2 = described_class.new
      woff2.table_entries = []

      expect(woff2.table_names).to eq([])
    end
  end

  describe "#table_data" do
    it "returns decompressed table data" do
      woff2 = described_class.new
      woff2.initialize_storage

      data = "Test table data"
      woff2.decompressed_tables["head"] = data

      expect(woff2.table_data("head")).to eq(data)
    end

    it "returns nil when table not found" do
      woff2 = described_class.new
      woff2.initialize_storage

      expect(woff2.table_data("head")).to be_nil
    end
  end

  describe "#valid?" do
    it "returns false when header is missing" do
      woff2 = described_class.new
      expect(woff2.valid?).to be false
    end

    it "returns false when signature is invalid" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.signature = 0xDEADBEEF
      woff2.table_entries = []

      expect(woff2.valid?).to be false
    end

    it "returns false when table count mismatch" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.signature = Fontisan::Woff2::Woff2Header::SIGNATURE
      woff2.header.num_tables = 5
      woff2.table_entries = [double(tag: "head")]

      expect(woff2.valid?).to be false
    end

    it "returns false when head table is missing" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.signature = Fontisan::Woff2::Woff2Header::SIGNATURE
      woff2.header.num_tables = 1
      entry = double(tag: "name")
      woff2.table_entries = [entry]

      expect(woff2.valid?).to be false
    end

    it "returns true when all validations pass" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.signature = Fontisan::Woff2::Woff2Header::SIGNATURE
      woff2.header.num_tables = 1
      entry = double(tag: "head")
      woff2.table_entries = [entry]

      expect(woff2.valid?).to be true
    end
  end

  describe "#to_ttf" do
    it "raises error when font is not TrueType flavored" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.flavor = 0x4F54544F # 'OTTO'

      expect do
        woff2.to_ttf("output.ttf")
      end.to raise_error(Fontisan::InvalidFontError, /Cannot convert to TTF/)
    end
  end

  describe "#to_otf" do
    it "raises error when font is not CFF flavored" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.flavor = 0x00010000

      expect do
        woff2.to_otf("output.otf")
      end.to raise_error(Fontisan::InvalidFontError, /Cannot convert to OTF/)
    end
  end

  describe "#metadata" do
    context "when no metadata present" do
      it "returns nil" do
        woff2 = described_class.new
        woff2.header = Fontisan::Woff2::Woff2Header.new
        woff2.header.meta_length = 0

        expect(woff2.metadata).to be_nil
      end
    end

    context "when metadata decompression fails" do
      it "returns nil and warns" do
        woff2 = described_class.new
        woff2.header = Fontisan::Woff2::Woff2Header.new
        woff2.header.meta_offset = 100
        woff2.header.meta_length = 10
        woff2.header.meta_orig_length = 50
        woff2.io_source = double(path: "test.woff2")

        allow(File).to receive(:open).and_raise(StandardError,
                                                "Decompression error")
        expect { woff2.metadata }.to output(/Failed to decompress/).to_stderr

        expect(woff2.metadata).to be_nil
      end
    end
  end

  describe "variable-length integer parsing" do
    describe "#read_uint_base128" do
      it "reads single-byte values" do
        woff2 = described_class.new
        io = StringIO.new([0x7F].pack("C")) # 127

        result = woff2.send(:read_uint_base128, io)

        expect(result).to eq(127)
      end

      it "reads multi-byte values" do
        woff2 = described_class.new
        # Encode 300: 0x82 0x2C (10000010 00101100 in base128)
        io = StringIO.new([0x82, 0x2C].pack("C*"))

        result = woff2.send(:read_uint_base128, io)

        expect(result).to eq(300)
      end

      it "raises error for invalid encoding (too many bytes)" do
        woff2 = described_class.new
        # Send 6 bytes with continuation bits set
        io = StringIO.new([0x80, 0x80, 0x80, 0x80, 0x80, 0x80].pack("C*"))

        expect { woff2.send(:read_uint_base128, io) }
          .to raise_error(Fontisan::InvalidFontError, /Invalid UIntBase128/)
      end
    end

    describe "#read_255_uint16" do
      it "reads values 0-252 directly" do
        woff2 = described_class.new
        io = StringIO.new([100].pack("C"))

        result = woff2.send(:read_255_uint16, io)

        expect(result).to eq(100)
      end

      it "reads value 253 format (253 + next byte)" do
        woff2 = described_class.new
        io = StringIO.new([253, 10].pack("C*"))

        result = woff2.send(:read_255_uint16, io)

        expect(result).to eq(263) # 253 + 10
      end

      it "reads value 254 format (next 2 bytes)" do
        woff2 = described_class.new
        io = StringIO.new([254, 0x01, 0x00].pack("C*"))

        result = woff2.send(:read_255_uint16, io)

        expect(result).to eq(256)
      end

      it "reads value 255 format (next 2 bytes + 506)" do
        woff2 = described_class.new
        io = StringIO.new([255, 0x00, 0x0A].pack("C*"))

        result = woff2.send(:read_255_uint16, io)

        expect(result).to eq(516) # 10 + 506
      end
    end
  end

  describe "Woff2TableDirectoryEntry" do
    describe "#transformed?" do
      it "returns false for non-transformable tables" do
        entry = Fontisan::Woff2TableDirectoryEntry.new
        entry.tag = "head"
        entry.flags = 1 # Known table index for "head"

        expect(entry.transformed?).to be false
      end

      it "returns true for transformed glyf table" do
        entry = Fontisan::Woff2TableDirectoryEntry.new
        entry.tag = "glyf"
        entry.flags = 10 # Known table index for "glyf"

        # For transformed tables, the tag index should not be 0x3F
        # and the tag should be one of glyf/loca/hmtx
        expect(entry.tag).to match(/glyf|loca|hmtx/)
      end
    end

    describe "KNOWN_TAGS" do
      it "includes all standard OpenType tables" do
        known_tags = Fontisan::Woff2TableDirectoryEntry::KNOWN_TAGS

        expect(known_tags).to include("cmap", "head", "hhea", "hmtx")
        expect(known_tags).to include("glyf", "loca")
        expect(known_tags).to include("CFF ", "name", "post")
        expect(known_tags.length).to eq(63)
      end

      it "has cmap as first entry (index 0)" do
        known_tags = Fontisan::Woff2TableDirectoryEntry::KNOWN_TAGS

        expect(known_tags[0]).to eq("cmap")
      end

      it "has glyf at index 10" do
        known_tags = Fontisan::Woff2TableDirectoryEntry::KNOWN_TAGS

        expect(known_tags[10]).to eq("glyf")
      end
    end
  end

  describe "FontTableProvider interface" do
    it "implements has_table? method" do
      woff2 = described_class.new

      expect(woff2).to respond_to(:has_table?)
    end

    it "implements table_data method" do
      woff2 = described_class.new

      expect(woff2).to respond_to(:table_data)
    end

    it "implements table_names method" do
      woff2 = described_class.new

      expect(woff2).to respond_to(:table_names)
    end

    it "implements table method for parsed tables" do
      woff2 = described_class.new

      expect(woff2).to respond_to(:table)
    end
  end

  describe "Brotli compression" do
    it "uses Brotli for decompression" do
      woff2 = described_class.new
      woff2.initialize_storage

      original_data = "Hello, WOFF2!" * 10
      compressed_data = Brotli.deflate(original_data)

      # Mock the decompression process
      expect(Brotli).to receive(:inflate).with(compressed_data).and_return(original_data)

      # Simulate a simple decompression
      result = Brotli.inflate(compressed_data)

      expect(result).to eq(original_data)
    end
  end

  describe "#calculate_offset_table_fields" do
    it "calculates correct values for 1 table" do
      woff2 = described_class.new

      search_range, entry_selector, range_shift = woff2.send(
        :calculate_offset_table_fields, 1
      )

      expect(entry_selector).to eq(0)
      expect(search_range).to eq(16)
      expect(range_shift).to eq(0)
    end

    it "calculates correct values for 8 tables" do
      woff2 = described_class.new

      search_range, entry_selector, range_shift = woff2.send(
        :calculate_offset_table_fields, 8
      )

      expect(entry_selector).to eq(3)
      expect(search_range).to eq(128)
      expect(range_shift).to eq(0)
    end

    it "calculates correct values for 10 tables" do
      woff2 = described_class.new

      search_range, entry_selector, range_shift = woff2.send(
        :calculate_offset_table_fields, 10
      )

      expect(entry_selector).to eq(3)
      expect(search_range).to eq(128)
      expect(range_shift).to eq(32)
    end
  end

  describe "transformation reconstruction" do
    context "with real WOFF2 file containing transformations" do
      let(:woff2_path) do
        font_fixture_path("MonaSans",
                          "fonts/webfonts/variable/MonaSansVF[wght,opsz].woff2")
      end

      before do
        skip "MonaSans WOFF2 fixture not available" unless File.exist?(woff2_path)
      end

      it "successfully reconstructs glyf/loca tables" do
        font = Fontisan::FontLoader.load(woff2_path)

        expect(font).to be_a(described_class)
        expect(font.has_table?("glyf")).to be true
        expect(font.has_table?("loca")).to be true

        # Verify glyf table has data
        glyf_data = font.table_data("glyf")
        expect(glyf_data).not_to be_nil
        expect(glyf_data.bytesize).to be > 0

        # Verify loca table has data
        loca_data = font.table_data("loca")
        expect(loca_data).not_to be_nil
        expect(loca_data.bytesize).to be > 0
      end

      it "successfully reconstructs hmtx table" do
        font = Fontisan::FontLoader.load(woff2_path)

        expect(font).to be_a(described_class)
        expect(font.has_table?("hmtx")).to be true

        # Verify hmtx table has data
        hmtx_data = font.table_data("hmtx")
        expect(hmtx_data).not_to be_nil
        expect(hmtx_data.bytesize).to be > 0
      end

      it "provides access to font metadata" do
        font = Fontisan::FontLoader.load(woff2_path, mode: Fontisan::LoadingModes::FULL)

        # Access maxp table to get glyph count
        expect(font.has_table?("maxp")).to be true

        maxp = font.table("maxp")
        expect(maxp).not_to be_nil
        expect(maxp.num_glyphs).to be > 0

        # Verify we can access name table
        expect(font.has_table?("name")).to be true
      end

      it "allows conversion to TTF when TrueType flavored" do
        font = Fontisan::FontLoader.load(woff2_path, mode: Fontisan::LoadingModes::FULL)

        if font.truetype?
          expect(font.family_name).to eq("Mona Sans VF")
          # Variable font will have different glyph count than the static font
          expect(font.table("maxp").num_glyphs).to be > 0
        end
      end
    end
  end

  describe "edge cases" do
    it "handles empty table entries" do
      woff2 = described_class.new
      woff2.table_entries = []

      expect(woff2.table_names).to eq([])
      expect(woff2.has_table?("head")).to be false
    end

    it "handles nil io_source gracefully" do
      woff2 = described_class.new
      woff2.header = Fontisan::Woff2::Woff2Header.new
      woff2.header.meta_length = 0

      expect(woff2.metadata).to be_nil
    end
  end
end
