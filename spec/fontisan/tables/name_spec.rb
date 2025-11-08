# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Name do
  # Helper to build valid name table binary data with sample records
  def build_name_table(records: [])
    data = (+"").b

    # Format (uint16)
    format = 0
    data << [format].pack("n")

    # Count (uint16)
    count = records.length
    data << [count].pack("n")

    # String offset (uint16) - offset to start of string storage
    # Each record is 12 bytes, so strings start after header (6 bytes) + records
    string_offset = 6 + (count * 12)
    data << [string_offset].pack("n")

    # Build name records and collect string data
    string_data = (+"").b
    current_string_offset = 0

    records.each do |record|
      # Encode the string based on platform
      encoded_string = case record[:platform_id]
                       when 1 # Mac
                         record[:string].encode("ASCII-8BIT",
                                                invalid: :replace,
                                                undef: :replace)
                       when 3 # Windows
                         record[:string].encode("UTF-16BE",
                                                invalid: :replace,
                                                undef: :replace)
                       else
                         record[:string].encode("UTF-16BE")
                       end

      # Name record (12 bytes)
      data << [record[:platform_id]].pack("n")
      data << [record[:encoding_id]].pack("n")
      data << [record[:language_id]].pack("n")
      data << [record[:name_id]].pack("n")
      data << [encoded_string.bytesize].pack("n")
      data << [current_string_offset].pack("n")

      # Store string data (ensure binary encoding compatibility)
      string_data << encoded_string.b
      current_string_offset += encoded_string.bytesize
    end

    # Append string storage
    data << string_data

    data
  end

  describe "#parse" do
    context "with valid name table data" do
      let(:records) do
        [
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::FAMILY,
            string: "Test Family",
          },
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::SUBFAMILY,
            string: "Regular",
          },
          {
            platform_id: 1,
            encoding_id: 0,
            language_id: 0,
            name_id: described_class::FAMILY,
            string: "Test Family",
          },
        ]
      end
      let(:data) { build_name_table(records: records) }
      let(:name) { described_class.read(data) }

      it "parses format correctly" do
        expect(name.format).to eq(0)
      end

      it "parses count correctly" do
        expect(name.count).to eq(3)
      end

      it "parses string_offset correctly" do
        expected_offset = 6 + (3 * 12) # Header + 3 records
        expect(name.string_offset).to eq(expected_offset)
      end

      it "parses all name records" do
        expect(name.name_records.length).to eq(3)
      end

      it "parses name record attributes correctly" do
        record = name.name_records.first
        expect(record.platform_id).to eq(3)
        expect(record.encoding_id).to eq(1)
        expect(record.language_id).to eq(0x0409)
        expect(record.name_id).to eq(described_class::FAMILY)
      end
    end

    context "with empty name table" do
      let(:data) { build_name_table(records: []) }
      let(:name) { described_class.read(data) }

      it "handles empty name records" do
        expect(name.count).to eq(0)
        expect(name.name_records).to be_empty
      end
    end
  end

  describe "string decoding" do
    context "with Windows UTF-16BE encoding" do
      let(:records) do
        [
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::FAMILY,
            string: "Test Font",
          },
        ]
      end
      let(:data) { build_name_table(records: records) }
      let(:name) { described_class.read(data) }

      it "decodes UTF-16BE strings correctly" do
        record = name.name_records.first
        expect(record.string).to eq("Test Font")
      end

      it "handles Unicode characters" do
        unicode_records = [
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::FAMILY,
            string: "Test Fönt Ñamé",
          },
        ]
        unicode_data = build_name_table(records: unicode_records)
        unicode_name = described_class.read(unicode_data)

        expect(unicode_name.name_records.first.string).to eq("Test Fönt Ñamé")
      end
    end

    context "with Mac ASCII encoding" do
      let(:records) do
        [
          {
            platform_id: 1,
            encoding_id: 0,
            language_id: 0,
            name_id: described_class::FAMILY,
            string: "Test Font",
          },
        ]
      end
      let(:data) { build_name_table(records: records) }
      let(:name) { described_class.read(data) }

      it "decodes ASCII strings correctly" do
        record = name.name_records.first
        expect(record.string).to eq("Test Font")
      end
    end
  end

  describe "#english_name" do
    context "with Windows English records" do
      let(:records) do
        [
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::FAMILY,
            string: "Windows Family",
          },
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::SUBFAMILY,
            string: "Bold",
          },
        ]
      end
      let(:data) { build_name_table(records: records) }
      let(:name) { described_class.read(data) }

      it "returns Windows English family name" do
        expect(name.english_name(described_class::FAMILY)).to eq("Windows Family")
      end

      it "returns Windows English subfamily name" do
        expect(name.english_name(described_class::SUBFAMILY)).to eq("Bold")
      end

      it "returns nil for non-existent name ID" do
        expect(name.english_name(described_class::DESIGNER)).to be_nil
      end
    end

    context "with Mac English fallback" do
      let(:records) do
        [
          {
            platform_id: 1,
            encoding_id: 0,
            language_id: 0,
            name_id: described_class::FAMILY,
            string: "Mac Family",
          },
        ]
      end
      let(:data) { build_name_table(records: records) }
      let(:name) { described_class.read(data) }

      it "falls back to Mac English when Windows not available" do
        expect(name.english_name(described_class::FAMILY)).to eq("Mac Family")
      end
    end

    context "with priority selection" do
      let(:records) do
        [
          {
            platform_id: 1,
            encoding_id: 0,
            language_id: 0,
            name_id: described_class::FAMILY,
            string: "Mac Family",
          },
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::FAMILY,
            string: "Windows Family",
          },
        ]
      end
      let(:data) { build_name_table(records: records) }
      let(:name) { described_class.read(data) }

      it "prioritizes Windows English over Mac English" do
        expect(name.english_name(described_class::FAMILY)).to eq("Windows Family")
      end
    end

    context "with various name IDs" do
      let(:records) do
        [
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::COPYRIGHT,
            string: "Copyright 2024",
          },
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::VERSION,
            string: "Version 1.0",
          },
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::POSTSCRIPT_NAME,
            string: "TestFont-Regular",
          },
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::FULL_NAME,
            string: "Test Font Regular",
          },
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::DESIGNER,
            string: "John Designer",
          },
          {
            platform_id: 3,
            encoding_id: 1,
            language_id: 0x0409,
            name_id: described_class::MANUFACTURER,
            string: "Test Foundry",
          },
        ]
      end
      let(:data) { build_name_table(records: records) }
      let(:name) { described_class.read(data) }

      it "retrieves copyright" do
        expect(name.english_name(described_class::COPYRIGHT)).to eq("Copyright 2024")
      end

      it "retrieves version" do
        expect(name.english_name(described_class::VERSION)).to eq("Version 1.0")
      end

      it "retrieves PostScript name" do
        expect(name.english_name(described_class::POSTSCRIPT_NAME))
          .to eq("TestFont-Regular")
      end

      it "retrieves full name" do
        expect(name.english_name(described_class::FULL_NAME))
          .to eq("Test Font Regular")
      end

      it "retrieves designer" do
        expect(name.english_name(described_class::DESIGNER)).to eq("John Designer")
      end

      it "retrieves manufacturer" do
        expect(name.english_name(described_class::MANUFACTURER))
          .to eq("Test Foundry")
      end
    end
  end

  describe "NameRecord" do
    describe "#decode_string" do
      it "decodes Mac/ASCII strings" do
        record = Fontisan::Tables::NameRecord.read([1, 0, 0, 1, 4,
                                                    0].pack("n6"))
        record.decode_string("Test")
        expect(record.string).to eq("Test")
      end

      it "decodes Windows UTF-16BE strings" do
        record = Fontisan::Tables::NameRecord.read([3, 1, 0x0409, 1, 8,
                                                    0].pack("n6"))
        utf16_data = "Test".encode("UTF-16BE")
        record.decode_string(utf16_data)
        expect(record.string).to eq("Test")
      end

      it "decodes Unicode UTF-16BE strings" do
        record = Fontisan::Tables::NameRecord.read([0, 3, 0, 1, 8,
                                                    0].pack("n6"))
        utf16_data = "Test".encode("UTF-16BE")
        record.decode_string(utf16_data)
        expect(record.string).to eq("Test")
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid data" do
      data = build_name_table(records: [
                                {
                                  platform_id: 3,
                                  encoding_id: 1,
                                  language_id: 0x0409,
                                  name_id: 1,
                                  string: "Test",
                                },
                              ])
      name = described_class.read(data)
      expect(name).to be_valid
    end
  end
end
