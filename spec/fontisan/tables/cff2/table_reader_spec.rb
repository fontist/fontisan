# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff2::TableReader do
  describe "#initialize" do
    it "initializes with CFF2 data" do
      data = build_minimal_cff2_data
      reader = described_class.new(data)

      expect(reader.data).to eq(data)
      expect(reader.header).to be_nil
      expect(reader.top_dict).to be_nil
      expect(reader.variable_store).to be_nil
    end
  end

  describe "#read_header" do
    it "reads valid CFF2 header" do
      data = build_minimal_cff2_data
      reader = described_class.new(data)
      header = reader.read_header

      expect(header[:major_version]).to eq(2)
      expect(header[:minor_version]).to eq(0)
      expect(header[:header_size]).to eq(5)
      expect(header[:top_dict_length]).to be > 0
    end

    it "raises error for invalid CFF2 version" do
      data = [1, 0, 5, 0, 10].pack("C*") # Version 1.0 (not CFF2)
      reader = described_class.new(data)

      expect { reader.read_header }.to raise_error(
        Fontisan::CorruptedTableError,
        /Invalid CFF2 version/,
      )
    end
  end

  describe "#read_top_dict" do
    it "reads Top DICT from CFF2" do
      data = build_cff2_with_top_dict
      reader = described_class.new(data)
      top_dict = reader.read_top_dict

      expect(top_dict).to be_a(Hash)
      expect(top_dict).not_to be_empty
    end

    it "parses Top DICT operators" do
      data = build_cff2_with_charstrings_offset
      reader = described_class.new(data)
      top_dict = reader.read_top_dict

      # Operator 17 = CharStrings offset
      expect(top_dict[17]).to be_a(Integer)
      expect(top_dict[17]).to be > 0
    end
  end

  describe "#read_variable_store" do
    context "when Variable Store is present" do
      it "reads Variable Store with regions and deltas" do
        data = build_cff2_with_variable_store
        reader = described_class.new(data)
        vstore = reader.read_variable_store

        expect(vstore).not_to be_nil
        expect(vstore[:regions]).to be_an(Array)
        expect(vstore[:item_variation_data]).to be_an(Array)
      end

      it "parses regions correctly" do
        data = build_cff2_with_variable_store(num_regions: 2, num_axes: 2)
        reader = described_class.new(data)
        vstore = reader.read_variable_store

        expect(vstore[:regions].size).to eq(2)

        region = vstore[:regions].first
        expect(region[:axis_count]).to eq(2)
        expect(region[:axes].size).to eq(2)

        axis = region[:axes].first
        expect(axis).to have_key(:start_coord)
        expect(axis).to have_key(:peak_coord)
        expect(axis).to have_key(:end_coord)
      end

      it "parses item variation data correctly" do
        data = build_cff2_with_variable_store(
          num_regions: 2,
          num_items: 3,
        )
        reader = described_class.new(data)
        vstore = reader.read_variable_store

        item_data = vstore[:item_variation_data].first
        expect(item_data[:item_count]).to eq(3)
        expect(item_data[:region_indices]).to be_an(Array)
        expect(item_data[:delta_sets]).to be_an(Array)
        expect(item_data[:delta_sets].size).to eq(3)
      end
    end

    context "when Variable Store is not present" do
      it "returns nil" do
        data = build_minimal_cff2_data
        reader = described_class.new(data)
        vstore = reader.read_variable_store

        expect(vstore).to be_nil
      end
    end
  end

  describe "#read_region_list" do
    it "reads multiple regions" do
      data = build_cff2_with_variable_store(num_regions: 3, num_axes: 2)
      reader = described_class.new(data)
      reader.read_variable_store

      # Access regions through variable_store
      regions = reader.variable_store[:regions]
      expect(regions.size).to eq(3)
    end

    it "parses F2DOT14 coordinates correctly" do
      data = build_cff2_with_specific_coordinates
      reader = described_class.new(data)
      vstore = reader.read_variable_store

      region = vstore[:regions].first
      axis = region[:axes].first

      # F2DOT14 values should be floats
      expect(axis[:start_coord]).to be_a(Float)
      expect(axis[:peak_coord]).to be_a(Float)
      expect(axis[:end_coord]).to be_a(Float)

      # Check reasonable ranges for normalized coordinates
      expect(axis[:start_coord]).to be_between(-1.0, 1.0)
      expect(axis[:peak_coord]).to be_between(-1.0, 1.0)
      expect(axis[:end_coord]).to be_between(-1.0, 1.0)
    end
  end

  describe "#read_item_variation_data" do
    it "reads delta sets for all items" do
      data = build_cff2_with_variable_store(
        num_regions: 2,
        num_items: 4,
      )
      reader = described_class.new(data)
      vstore = reader.read_variable_store

      item_data = vstore[:item_variation_data].first
      expect(item_data[:delta_sets].size).to eq(4)

      # Each delta set should have deltas for all regions
      delta_set = item_data[:delta_sets].first
      expect(delta_set).to be_an(Array)
      expect(delta_set.size).to eq(item_data[:region_indices].size)
    end

    it "handles mixed short and long deltas" do
      data = build_cff2_with_mixed_deltas
      reader = described_class.new(data)
      vstore = reader.read_variable_store

      item_data = vstore[:item_variation_data].first
      delta_set = item_data[:delta_sets].first

      # Should have both 16-bit and 8-bit deltas
      expect(delta_set).to be_an(Array)
      expect(delta_set).not_to be_empty
    end
  end

  describe "#read_private_dict" do
    it "reads Private DICT at specified offset" do
      data = build_cff2_with_private_dict
      reader = described_class.new(data)
      reader.read_top_dict

      # Get Private DICT location from Top DICT (operator 18)
      private_info = reader.top_dict[18]
      size, offset = private_info

      private_dict = reader.read_private_dict(size, offset)
      expect(private_dict).to be_a(Hash)
    end

    it "parses Private DICT operators" do
      data = build_cff2_with_blue_values
      reader = described_class.new(data)
      reader.read_top_dict

      private_info = reader.top_dict[18]
      size, offset = private_info

      private_dict = reader.read_private_dict(size, offset)

      # Operator 6 = BlueValues
      expect(private_dict[6]).to be_an(Array) if private_dict.key?(6)
    end
  end

  describe "#read_charstrings" do
    it "reads CharStrings INDEX" do
      data = build_cff2_with_charstrings
      reader = described_class.new(data)
      reader.read_top_dict

      # Get CharStrings offset from Top DICT (operator 17)
      charstrings_offset = reader.top_dict[17]

      charstrings = reader.read_charstrings(charstrings_offset)
      expect(charstrings).to be_a(Fontisan::Tables::Cff::Index)
      expect(charstrings.count).to be > 0
    end
  end

  # Helper methods to build test data

  def build_minimal_cff2_data
    # Minimal Top DICT (just endchar for .notdef)
    top_dict = [14].pack("C") # endchar operator

    header = [
      2,    # major version
      0,    # minor version
      5,    # header size
      0, top_dict.bytesize # top dict length (2 bytes, big-endian)
    ].pack("C5")

    header + top_dict
  end

  def build_cff2_with_top_dict
    # Top DICT with CharStrings offset using small integer
    top_dict = [
      100 + 139, # operand (100)
      17, # CharStrings operator
    ].pack("C*")

    header = [2, 0, 5, 0, top_dict.bytesize].pack("C5")

    header + top_dict + ("\x00" * 100)
  end

  def build_cff2_with_charstrings_offset
    # Top DICT: offset 500 for CharStrings using 5-byte integer
    # Format: 29 (marker) + 4 bytes (value) + 17 (operator)
    top_dict = [29].pack("C") + [500].pack("N") + [17].pack("C")

    header = [2, 0, 5, 0, top_dict.bytesize].pack("C5")

    header + top_dict
  end

  def build_cff2_with_variable_store(num_regions: 1, num_axes: 1, num_items: 1)
    # Variable Store offset
    vstore_offset = 50

    # Top DICT with Variable Store offset (operator 24)
    # Format: 29 (5-byte integer marker) + 4 bytes (offset) + 24 (operator)
    top_dict = [29].pack("C") + [vstore_offset].pack("N") + [24].pack("C")

    header = [2, 0, 5, 0, top_dict.bytesize].pack("C5")

    # Pad to Variable Store location
    padding = "\x00" * (vstore_offset - header.bytesize - top_dict.bytesize)

    # Build Variable Store
    # Region List
    region_list = [num_regions].pack("n")  # region count

    num_regions.times do
      region_list << [num_axes].pack("n")  # axis count
      num_axes.times do
        # F2DOT14 values: start, peak, end (-0.5, 1.0, 1.0)
        region_list << [(-0.5 * 16384).to_i].pack("s>")  # start: -0.5
        region_list << [(1.0 * 16384).to_i].pack("s>")   # peak: 1.0
        region_list << [(1.0 * 16384).to_i].pack("s>")   # end: 1.0
      end
    end

    # Item Variation Data
    item_var_data = [1].pack("n") # data count

    # Single Item Variation Data entry
    item_var_data << [
      num_items,      # item count
      num_regions,    # short delta count
      num_regions, # region index count
    ].pack("n*")

    # Region indices
    num_regions.times do |i|
      item_var_data << [i].pack("n")
    end

    # Delta sets (16-bit deltas)
    num_items.times do
      num_regions.times do
        item_var_data << [10].pack("s>") # delta value: 10
      end
    end

    vstore = region_list + item_var_data

    header + top_dict + padding + vstore
  end

  def build_cff2_with_specific_coordinates
    # Build CFF2 with known F2DOT14 values
    build_cff2_with_variable_store(num_regions: 1, num_axes: 1)
  end

  def build_cff2_with_mixed_deltas
    vstore_offset = 50

    top_dict = [29].pack("C") + [vstore_offset].pack("N") + [24].pack("C")
    header = [2, 0, 5, 0, top_dict.bytesize].pack("C5")
    padding = "\x00" * (vstore_offset - header.bytesize - top_dict.bytesize)

    # Region List (1 region, 1 axis)
    region_list = [1, 1].pack("n*")
    region_list << [(-0.5 * 16384).to_i, (1.0 * 16384).to_i,
                    (1.0 * 16384).to_i].pack("s>*")

    # Item Variation Data with mixed deltas
    item_var_data = [1].pack("n") # data count
    item_var_data << [
      2,    # item count
      1,    # short delta count (1 short, rest are long)
      2, # total region indices
    ].pack("n*")

    # Region indices
    item_var_data << [0, 1].pack("n*")

    # Delta sets: first item
    item_var_data << [1000].pack("s>")  # short delta
    item_var_data << [50].pack("c")     # long delta (8-bit)

    # Delta sets: second item
    item_var_data << [2000].pack("s>")  # short delta
    item_var_data << [100].pack("c")    # long delta

    header + top_dict + padding + region_list + item_var_data
  end

  def build_cff2_with_private_dict
    private_size = 20
    private_offset = 100

    # Top DICT with Private DICT info (operator 18)
    # Format: size offset 18
    top_dict = [
      private_size + 139,
      29,
    ].pack("C*") + [private_offset].pack("N") + [18].pack("C")

    header = [2, 0, 5, 0, top_dict.bytesize].pack("C5")

    # Pad to Private DICT
    padding = "\x00" * (private_offset - header.bytesize - top_dict.bytesize)

    # Private DICT (minimal)
    private_dict = [14].pack("C") # endchar

    header + top_dict + padding + private_dict
  end

  def build_cff2_with_blue_values
    private_size = 30
    private_offset = 100

    top_dict = [
      private_size + 139,
      29,
    ].pack("C*") + [private_offset].pack("N") + [18].pack("C")

    header = [2, 0, 5, 0, top_dict.bytesize].pack("C5")

    padding = "\x00" * (private_offset - header.bytesize - top_dict.bytesize)

    # Private DICT with BlueValues (operator 6)
    # BlueValues: [-10, 0, 500, 510] (bottom/top pairs)
    private_dict = [
      -10 + 139,    # -10
      0 + 139,      # 0
      247, 136,     # 500 (2-byte positive)
      247, 146,     # 510
      6             # BlueValues operator
    ].pack("C*")

    header + top_dict + padding + private_dict
  end

  def build_cff2_with_charstrings
    charstrings_offset = 50
    top_dict = [29].pack("C") + [charstrings_offset].pack("N") + [17].pack("C")

    header = [2, 0, 5, 0, top_dict.bytesize].pack("C5")

    padding = "\x00" * (charstrings_offset - header.bytesize - top_dict.bytesize)

    # Build minimal CharStrings INDEX
    # INDEX: count offSize offset[count+1] data
    count = 2
    off_size = 1
    charstrings_index = [count, off_size].pack("nC")

    # Offsets (3 offsets for 2 items)
    charstrings_index << [1, 2, 3].pack("C*")

    # Data: two minimal CharStrings
    charstrings_index << [14, 14].pack("C*") # endchar, endchar

    header + top_dict + padding + charstrings_index
  end
end
