# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Head do
  # Helper to build valid head table binary data
  def build_head_table(
    version: 1.0,
    font_revision: 1.0,
    checksum_adjustment: 0x12345678,
    magic_number: 0x5F0F3CF5,
    flags: 0x0001,
    units_per_em: 1000,
    created: Time.utc(2020, 1, 1),
    modified: Time.utc(2024, 1, 1),
    x_min: -100,
    y_min: -200,
    x_max: 1000,
    y_max: 800,
    mac_style: 0,
    lowest_rec_ppem: 8,
    font_direction_hint: 2,
    index_to_loc_format: 0,
    glyph_data_format: 0
  )
    data = (+"").b

    # Version (Fixed 16.16) - stored as int32
    integer_part = version.to_i
    fractional_part = ((version - integer_part) * 65_536).to_i
    version_raw = (integer_part << 16) | fractional_part
    data << [version_raw].pack("N")

    # Font Revision (Fixed 16.16) - stored as int32
    integer_part = font_revision.to_i
    fractional_part = ((font_revision - integer_part) * 65_536).to_i
    font_revision_raw = (integer_part << 16) | fractional_part
    data << [font_revision_raw].pack("N")

    # Checksum Adjustment (uint32)
    data << [checksum_adjustment].pack("N")

    # Magic Number (uint32)
    data << [magic_number].pack("N")

    # Flags (uint16)
    data << [flags].pack("n")

    # Units Per Em (uint16)
    data << [units_per_em].pack("n")

    # Created (LONGDATETIME - 64-bit signed int)
    # Convert from Ruby Time to 1904-based seconds
    created_seconds = created.to_i + 2_082_844_800
    data << [created_seconds].pack("Q>") # Big-endian 64-bit signed

    # Modified (LONGDATETIME)
    modified_seconds = modified.to_i + 2_082_844_800
    data << [modified_seconds].pack("Q>") # Big-endian 64-bit signed

    # Bounding box (4 x int16)
    data << [x_min].pack("s>")
    data << [y_min].pack("s>")
    data << [x_max].pack("s>")
    data << [y_max].pack("s>")

    # Mac Style (uint16)
    data << [mac_style].pack("n")

    # Lowest Rec PPEM (uint16)
    data << [lowest_rec_ppem].pack("n")

    # Font Direction Hint (int16)
    data << [font_direction_hint].pack("s>")

    # Index To Loc Format (int16)
    data << [index_to_loc_format].pack("s>")

    # Glyph Data Format (int16)
    data << [glyph_data_format].pack("s>")

    data
  end

  describe ".read" do
    context "with valid head table data" do
      let(:data) { build_head_table }
      let(:head) { described_class.read(data) }

      it "parses version correctly" do
        expect(head.version).to be_within(0.001).of(1.0)
      end

      it "parses font_revision correctly" do
        expect(head.font_revision).to be_within(0.001).of(1.0)
      end

      it "parses checksum_adjustment correctly" do
        expect(head.checksum_adjustment).to eq(0x12345678)
      end

      it "parses magic_number correctly" do
        expect(head.magic_number).to eq(0x5F0F3CF5)
      end

      it "parses flags correctly" do
        expect(head.flags).to eq(0x0001)
      end

      it "parses units_per_em correctly" do
        expect(head.units_per_em).to eq(1000)
      end

      it "parses created date correctly" do
        expect(head.created).to be_within(1).of(Time.utc(2020, 1, 1))
      end

      it "parses modified date correctly" do
        expect(head.modified).to be_within(1).of(Time.utc(2024, 1, 1))
      end

      it "parses bounding box correctly" do
        expect(head.x_min).to eq(-100)
        expect(head.y_min).to eq(-200)
        expect(head.x_max).to eq(1000)
        expect(head.y_max).to eq(800)
      end

      it "parses mac_style correctly" do
        expect(head.mac_style).to eq(0)
      end

      it "parses lowest_rec_ppem correctly" do
        expect(head.lowest_rec_ppem).to eq(8)
      end

      it "parses font_direction_hint correctly" do
        expect(head.font_direction_hint).to eq(2)
      end

      it "parses index_to_loc_format correctly" do
        expect(head.index_to_loc_format).to eq(0)
      end

      it "parses glyph_data_format correctly" do
        expect(head.glyph_data_format).to eq(0)
      end
    end

    context "with typical values" do
      it "handles version 1.0" do
        data = build_head_table(version: 1.0)
        head = described_class.read(data)
        expect(head.version).to be_within(0.001).of(1.0)
      end

      it "handles version 2.5" do
        data = build_head_table(version: 2.5)
        head = described_class.read(data)
        expect(head.version).to be_within(0.001).of(2.5)
      end

      it "handles units_per_em of 1000" do
        data = build_head_table(units_per_em: 1000)
        head = described_class.read(data)
        expect(head.units_per_em).to eq(1000)
      end

      it "handles units_per_em of 2048" do
        data = build_head_table(units_per_em: 2048)
        head = described_class.read(data)
        expect(head.units_per_em).to eq(2048)
      end

      it "handles index_to_loc_format short (0)" do
        data = build_head_table(index_to_loc_format: 0)
        head = described_class.read(data)
        expect(head.index_to_loc_format).to eq(0)
      end

      it "handles index_to_loc_format long (1)" do
        data = build_head_table(index_to_loc_format: 1)
        head = described_class.read(data)
        expect(head.index_to_loc_format).to eq(1)
      end
    end

    context "with negative bounding box values" do
      it "handles negative x_min" do
        data = build_head_table(x_min: -500)
        head = described_class.read(data)
        expect(head.x_min).to eq(-500)
      end

      it "handles negative y_min" do
        data = build_head_table(y_min: -1000)
        head = described_class.read(data)
        expect(head.y_min).to eq(-1000)
      end
    end

    context "with various datetime values" do
      it "handles epoch time" do
        epoch = Time.utc(1970, 1, 1)
        data = build_head_table(created: epoch, modified: epoch)
        head = described_class.read(data)
        expect(head.created).to be_within(1).of(epoch)
        expect(head.modified).to be_within(1).of(epoch)
      end

      it "handles recent dates" do
        recent = Time.utc(2024, 3, 15, 10, 30, 45)
        data = build_head_table(created: recent, modified: recent)
        head = described_class.read(data)
        expect(head.created).to be_within(1).of(recent)
        expect(head.modified).to be_within(1).of(recent)
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid magic number" do
      data = build_head_table
      head = described_class.read(data)
      expect(head).to be_valid
    end

    it "returns false for invalid magic number" do
      data = build_head_table(magic_number: 0xDEADBEEF)
      head = described_class.read(data)
      expect(head).not_to be_valid
    end
  end
end
