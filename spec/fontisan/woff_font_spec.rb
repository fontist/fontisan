# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Fontisan::WoffFont do
  let(:woff_signature) { [0x774F4646].pack("N") } # 'wOFF'
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
        expect { described_class.from_file("nonexistent.woff") }
          .to raise_error(Errno::ENOENT, /File not found/)
      end
    end

    context "with invalid WOFF signature" do
      it "raises InvalidFontError for wrong signature" do
        Tempfile.create(["invalid", ".woff"]) do |f|
          # Write invalid signature
          f.write([0x12345678].pack("N"))
          f.write("\x00" * 40) # Rest of header
          f.close

          expect { described_class.from_file(f.path) }
            .to raise_error(Fontisan::InvalidFontError,
                            /Invalid WOFF signature/)
        end
      end
    end
  end

  describe "#validate_signature!" do
    it "raises error for invalid signature" do
      woff = described_class.new
      woff.header.signature = 0x12345678

      expect { woff.validate_signature! }
        .to raise_error(Fontisan::InvalidFontError, /Invalid WOFF signature/)
    end

    it "does not raise error for valid signature" do
      woff = described_class.new
      woff.header.signature = Fontisan::WoffFont::WOFF_SIGNATURE

      expect { woff.validate_signature! }.not_to raise_error
    end
  end

  describe "#truetype?" do
    it "returns true for TrueType flavor (0x00010000)" do
      woff = described_class.new
      woff.header.flavor = 0x00010000

      expect(woff.truetype?).to be true
    end

    it "returns true for TrueType flavor (SFNT_VERSION_TRUETYPE)" do
      woff = described_class.new
      woff.header.flavor = Fontisan::Constants::SFNT_VERSION_TRUETYPE

      expect(woff.truetype?).to be true
    end

    it "returns false for CFF flavor" do
      woff = described_class.new
      woff.header.flavor = 0x4F54544F # 'OTTO'

      expect(woff.truetype?).to be false
    end
  end

  describe "#cff?" do
    it "returns true for CFF flavor (OTTO)" do
      woff = described_class.new
      woff.header.flavor = 0x4F54544F # 'OTTO'

      expect(woff.cff?).to be true
    end

    it "returns true for CFF flavor (SFNT_VERSION_OTTO)" do
      woff = described_class.new
      woff.header.flavor = Fontisan::Constants::SFNT_VERSION_OTTO

      expect(woff.cff?).to be true
    end

    it "returns false for TrueType flavor" do
      woff = described_class.new
      woff.header.flavor = 0x00010000

      expect(woff.cff?).to be false
    end
  end

  describe "#initialize_storage" do
    it "initializes decompressed_tables hash" do
      woff = described_class.new
      woff.initialize_storage

      expect(woff.decompressed_tables).to eq({})
    end

    it "initializes compressed_table_data hash" do
      woff = described_class.new
      woff.initialize_storage

      expect(woff.compressed_table_data).to eq({})
    end

    it "initializes parsed_tables hash" do
      woff = described_class.new
      woff.initialize_storage

      expect(woff.parsed_tables).to eq({})
    end
  end

  describe "#has_table?" do
    it "returns true when table exists" do
      woff = described_class.new
      entry = Fontisan::WoffTableDirectoryEntry.new
      entry.tag = "head"
      woff.table_entries = [entry]

      expect(woff.has_table?("head")).to be true
    end

    it "returns false when table does not exist" do
      woff = described_class.new
      woff.table_entries = []

      expect(woff.has_table?("head")).to be false
    end
  end

  describe "#find_table_entry" do
    it "returns entry when found" do
      woff = described_class.new
      entry = Fontisan::WoffTableDirectoryEntry.new
      entry.tag = "head"
      woff.table_entries = [entry]

      result = woff.find_table_entry("head")

      expect(result).to eq(entry)
    end

    it "returns nil when not found" do
      woff = described_class.new
      woff.table_entries = []

      result = woff.find_table_entry("head")

      expect(result).to be_nil
    end
  end

  describe "#table_names" do
    it "returns array of table tags" do
      woff = described_class.new
      entry1 = Fontisan::WoffTableDirectoryEntry.new
      entry1.tag = "head"
      entry2 = Fontisan::WoffTableDirectoryEntry.new
      entry2.tag = "name"
      woff.table_entries = [entry1, entry2]

      expect(woff.table_names).to eq(["head", "name"])
    end

    it "returns empty array when no tables" do
      woff = described_class.new
      woff.table_entries = []

      expect(woff.table_names).to eq([])
    end
  end

  describe "#table_data" do
    context "with uncompressed table" do
      it "returns table data directly" do
        woff = described_class.new
        woff.initialize_storage

        entry = Fontisan::WoffTableDirectoryEntry.new
        entry.tag = "head"
        entry.comp_length = 10
        entry.orig_length = 10
        woff.table_entries = [entry]

        data = "1234567890"
        woff.compressed_table_data["head"] = data

        expect(woff.table_data("head")).to eq(data)
      end
    end

    context "with compressed table" do
      it "decompresses zlib compressed data" do
        woff = described_class.new
        woff.initialize_storage

        original_data = "Hello, WOFF!" * 10
        compressed_data = Zlib::Deflate.deflate(original_data)

        entry = Fontisan::WoffTableDirectoryEntry.new
        entry.tag = "head"
        entry.comp_length = compressed_data.bytesize
        entry.orig_length = original_data.bytesize
        woff.table_entries = [entry]

        woff.compressed_table_data["head"] = compressed_data

        result = woff.table_data("head")

        expect(result).to eq(original_data)
        expect(result.bytesize).to eq(original_data.bytesize)
      end

      it "caches decompressed data" do
        woff = described_class.new
        woff.initialize_storage

        original_data = "Test data"
        compressed_data = Zlib::Deflate.deflate(original_data)

        entry = Fontisan::WoffTableDirectoryEntry.new
        entry.tag = "head"
        entry.comp_length = compressed_data.bytesize
        entry.orig_length = original_data.bytesize
        woff.table_entries = [entry]

        woff.compressed_table_data["head"] = compressed_data

        # First call decompresses
        result1 = woff.table_data("head")
        # Second call should return cached result
        result2 = woff.table_data("head")

        expect(result1).to eq(result2)
        expect(result1.object_id).to eq(result2.object_id)
      end

      it "raises error when decompressed size does not match" do
        woff = described_class.new
        woff.initialize_storage

        original_data = "Test"
        compressed_data = Zlib::Deflate.deflate(original_data)

        entry = Fontisan::WoffTableDirectoryEntry.new
        entry.tag = "head"
        entry.comp_length = compressed_data.bytesize
        entry.orig_length = 100 # Wrong size
        woff.table_entries = [entry]

        woff.compressed_table_data["head"] = compressed_data

        expect { woff.table_data("head") }
          .to raise_error(Fontisan::InvalidFontError, /size mismatch/)
      end
    end

    context "when table not found" do
      it "returns nil" do
        woff = described_class.new
        woff.initialize_storage
        woff.table_entries = []

        expect(woff.table_data("head")).to be_nil
      end
    end
  end

  describe "#valid?" do
    it "returns false when header is missing" do
      woff = described_class.new
      woff.instance_variable_set(:@header, nil)

      expect(woff.valid?).to be false
    end

    it "returns false when signature is invalid" do
      woff = described_class.new
      woff.header.signature = 0x12345678
      woff.table_entries = []

      expect(woff.valid?).to be false
    end

    it "returns false when table count mismatch" do
      woff = described_class.new
      woff.header.signature = Fontisan::WoffFont::WOFF_SIGNATURE
      woff.header.num_tables = 2
      woff.table_entries = [Fontisan::WoffTableDirectoryEntry.new]

      expect(woff.valid?).to be false
    end

    it "returns false when head table is missing" do
      woff = described_class.new
      woff.header.signature = Fontisan::WoffFont::WOFF_SIGNATURE
      woff.header.num_tables = 1
      entry = Fontisan::WoffTableDirectoryEntry.new
      entry.tag = "name"
      woff.table_entries = [entry]

      expect(woff.valid?).to be false
    end

    it "returns true when all validations pass" do
      woff = described_class.new
      woff.header.signature = Fontisan::WoffFont::WOFF_SIGNATURE
      woff.header.num_tables = 1
      entry = Fontisan::WoffTableDirectoryEntry.new
      entry.tag = "head"
      woff.table_entries = [entry]

      expect(woff.valid?).to be true
    end
  end

  describe "#to_ttf" do
    it "raises error when font is not TrueType flavored" do
      woff = described_class.new
      woff.header.flavor = 0x4F54544F # CFF

      expect { woff.to_ttf("output.ttf") }
        .to raise_error(Fontisan::InvalidFontError, /Cannot convert to TTF/)
    end
  end

  describe "#to_otf" do
    it "raises error when font is not CFF flavored" do
      woff = described_class.new
      woff.header.flavor = 0x00010000 # TrueType

      expect { woff.to_otf("output.otf") }
        .to raise_error(Fontisan::InvalidFontError, /Cannot convert to OTF/)
    end
  end

  describe "#metadata" do
    context "when no metadata present" do
      it "returns nil" do
        woff = described_class.new
        woff.header.meta_length = 0

        expect(woff.metadata).to be_nil
      end
    end

    context "when metadata decompression fails" do
      it "returns nil and warns" do
        woff = described_class.new
        woff.header.meta_offset = 100
        woff.header.meta_length = 10
        woff.header.meta_orig_length = 50

        # Create a temp file with invalid data
        Tempfile.create(["woff", ".woff"]) do |f|
          f.write("\x00" * 200)
          f.close

          woff.io_source = File.open(f.path, "rb")

          expect { woff.metadata }.to output(/Failed to decompress/).to_stderr

          expect(woff.metadata).to be_nil
        ensure
          woff.io_source&.close
        end
      end
    end
  end

  describe "integration with real WOFF structure" do
    it "handles minimal valid WOFF file" do
      Tempfile.create(["minimal", ".woff"]) do |f|
        # Write WOFF header
        f.write([0x774F4646].pack("N"))      # signature
        f.write([0x00010000].pack("N"))      # flavor (TTF)
        f.write([1000].pack("N"))            # length
        f.write([1].pack("n"))               # num_tables
        f.write([0].pack("n"))               # reserved
        f.write([1000].pack("N"))            # total_sfnt_size
        f.write([1, 0].pack("nn"))           # major/minor version
        f.write([0, 0, 0].pack("NNN"))       # meta offset/length/orig_length
        f.write([0, 0].pack("NN"))           # priv offset/length

        # Write one table entry (head)
        table_offset = 44 + 20 # After header and directory
        head_data = "\u0000\u0001\u0000\u0000#{"\x00" * 50}" # Minimal head table
        compressed_head = Zlib::Deflate.deflate(head_data)

        f.write("head")                                  # tag
        f.write([table_offset].pack("N"))                # offset
        f.write([compressed_head.bytesize].pack("N"))    # comp_length
        f.write([head_data.bytesize].pack("N"))          # orig_length
        f.write([0x12345678].pack("N"))                  # orig_checksum

        # Write compressed table data
        f.write(compressed_head)

        f.close

        woff = described_class.from_file(f.path)

        expect(woff).to be_a(described_class)
        expect(woff.header.signature).to eq(0x774F4646)
        expect(woff.header.num_tables).to eq(1)
        expect(woff.table_names).to eq(["head"])
        expect(woff.truetype?).to be true
        expect(woff.cff?).to be false
      end
    end
  end

  describe "FontTableProvider interface" do
    it "implements has_table? method" do
      woff = described_class.new

      expect(woff).to respond_to(:has_table?)
    end

    it "implements table_data method" do
      woff = described_class.new

      expect(woff).to respond_to(:table_data)
    end

    it "implements table_names method" do
      woff = described_class.new

      expect(woff).to respond_to(:table_names)
    end

    it "implements table method for parsed tables" do
      woff = described_class.new

      expect(woff).to respond_to(:table)
    end
  end
end
