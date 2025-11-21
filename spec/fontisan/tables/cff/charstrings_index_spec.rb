# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff::CharstringsIndex do
  # Helper to create a mock PrivateDict
  def mock_private_dict(default_width: 0, nominal_width: 0)
    double(
      "PrivateDict",
      default_width_x: default_width,
      nominal_width_x: nominal_width,
    )
  end

  # Helper to create an empty INDEX
  def empty_index
    data = [0].pack("n") # count = 0
    Fontisan::Tables::Cff::Index.new(data)
  end

  # Helper to build CharString binary data
  def build_charstring(*bytes)
    bytes.flatten.pack("C*")
  end

  # Helper to encode integer for CharString
  def encode_int(value)
    case value
    when -107..107
      [value + 139]
    when 108..1131
      b0 = ((value - 108) / 256) + 247
      b1 = (value - 108) % 256
      [b0, b1]
    when -1131..-108
      abs_val = -value
      b0 = ((abs_val - 108) / 256) + 251
      b1 = (abs_val - 108) % 256
      [b0, b1]
    else
      [28, (value >> 8) & 0xFF, value & 0xFF]
    end
  end

  let(:private_dict) { mock_private_dict(default_width: 500) }
  let(:global_subrs) { empty_index }
  let(:local_subrs) { nil }

  describe "initialization" do
    it "inherits from Index" do
      expect(described_class).to be < Fontisan::Tables::Cff::Index
    end
  end

  describe "#charstring_at" do
    context "with valid CharStrings INDEX" do
      let(:charstrings_data) do
        # Create INDEX with 3 CharStrings
        # CS 0: 0 0 rmoveto endchar
        # CS 1: 100 100 rmoveto endchar
        # CS 2: 200 200 rmoveto endchar

        cs0 = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          14 # endchar
        )
        cs1 = build_charstring(
          encode_int(100), encode_int(100), 21, # rmoveto
          14 # endchar
        )
        cs2 = build_charstring(
          encode_int(200), encode_int(200), 21, # rmoveto
          14 # endchar
        )

        parts = []
        parts << [3].pack("n") # count = 3
        parts << [1].pack("C") # offSize = 1

        # Calculate offsets
        offset = 1
        offsets = [offset]
        [cs0, cs1, cs2].each do |cs|
          offset += cs.bytesize
          offsets << offset
        end
        parts << offsets.pack("C#{offsets.size}")

        # Add data
        parts << cs0 << cs1 << cs2

        parts.join
      end

      let(:charstrings_index) { described_class.new(charstrings_data) }

      it "returns CharString object at valid index" do
        cs = charstrings_index.charstring_at(0, private_dict, global_subrs,
                                             local_subrs)

        expect(cs).to be_a(Fontisan::Tables::Cff::CharString)
        expect(cs.path.size).to eq(1)
        expect(cs.path[0]).to eq(type: :move_to, x: 0.0, y: 0.0)
      end

      it "returns different CharStrings for different indices" do
        cs0 = charstrings_index.charstring_at(0, private_dict, global_subrs,
                                              local_subrs)
        cs1 = charstrings_index.charstring_at(1, private_dict, global_subrs,
                                              local_subrs)
        cs2 = charstrings_index.charstring_at(2, private_dict, global_subrs,
                                              local_subrs)

        expect(cs0.path[0][:x]).to eq(0.0)
        expect(cs1.path[0][:x]).to eq(100.0)
        expect(cs2.path[0][:x]).to eq(200.0)
      end

      it "returns nil for out of bounds index" do
        cs = charstrings_index.charstring_at(10, private_dict, global_subrs,
                                             local_subrs)

        expect(cs).to be_nil
      end

      it "returns nil for negative index" do
        cs = charstrings_index.charstring_at(-1, private_dict, global_subrs,
                                             local_subrs)

        expect(cs).to be_nil
      end

      it "passes private_dict to CharString" do
        custom_private_dict = mock_private_dict(default_width: 600)

        cs = charstrings_index.charstring_at(0, custom_private_dict,
                                             global_subrs, local_subrs)

        expect(cs.width).to eq(600)
      end

      it "passes subroutines to CharString" do
        # This is tested indirectly - just verify no error
        cs = charstrings_index.charstring_at(0, private_dict, global_subrs,
                                             local_subrs)

        expect(cs).to be_a(Fontisan::Tables::Cff::CharString)
      end
    end

    context "with empty INDEX" do
      let(:empty_data) { [0].pack("n") }
      let(:charstrings_index) { described_class.new(empty_data) }

      it "returns nil for any index" do
        cs = charstrings_index.charstring_at(0, private_dict, global_subrs,
                                             local_subrs)

        expect(cs).to be_nil
      end
    end
  end

  describe "#all_charstrings" do
    let(:charstrings_data) do
      # Create INDEX with 2 simple CharStrings
      cs0 = build_charstring(
        encode_int(0), encode_int(0), 21, # rmoveto
        14 # endchar
      )
      cs1 = build_charstring(
        encode_int(50), encode_int(50), 21, # rmoveto
        14 # endchar
      )

      parts = []
      parts << [2].pack("n")
      parts << [1].pack("C")
      parts << [1, 1 + cs0.bytesize, 1 + cs0.bytesize + cs1.bytesize].pack("C3")
      parts << cs0 << cs1

      parts.join
    end

    let(:charstrings_index) { described_class.new(charstrings_data) }

    it "returns array of all CharStrings" do
      charstrings = charstrings_index.all_charstrings(private_dict,
                                                      global_subrs,
                                                      local_subrs)

      expect(charstrings).to be_an(Array)
      expect(charstrings.size).to eq(2)
      expect(charstrings[0]).to be_a(Fontisan::Tables::Cff::CharString)
      expect(charstrings[1]).to be_a(Fontisan::Tables::Cff::CharString)
    end

    it "interprets all CharStrings correctly" do
      charstrings = charstrings_index.all_charstrings(private_dict,
                                                      global_subrs,
                                                      local_subrs)

      expect(charstrings[0].path[0][:x]).to eq(0.0)
      expect(charstrings[1].path[0][:x]).to eq(50.0)
    end

    it "returns empty array for empty INDEX" do
      empty_data = [0].pack("n")
      empty_charstrings_index = described_class.new(empty_data)

      charstrings = empty_charstrings_index.all_charstrings(private_dict,
                                                            global_subrs,
                                                            local_subrs)

      expect(charstrings).to eq([])
    end
  end

  describe "#each_charstring" do
    let(:charstrings_data) do
      # Create INDEX with 3 CharStrings
      charstrings = [0, 100, 200].map do |offset|
        build_charstring(
          encode_int(offset), encode_int(offset), 21, # rmoveto
          14 # endchar
        )
      end

      parts = []
      parts << [3].pack("n")
      parts << [1].pack("C")

      offset = 1
      offsets = [offset]
      charstrings.each do |cs|
        offset += cs.bytesize
        offsets << offset
      end
      parts << offsets.pack("C#{offsets.size}")
      parts << charstrings.join

      parts.join
    end

    let(:charstrings_index) { described_class.new(charstrings_data) }

    it "iterates over each CharString" do
      collected = []
      charstrings_index.each_charstring(private_dict, global_subrs,
                                        local_subrs) do |cs, index|
        collected << [cs, index]
      end

      expect(collected.size).to eq(3)
      expect(collected[0][0]).to be_a(Fontisan::Tables::Cff::CharString)
      expect(collected[0][1]).to eq(0)
      expect(collected[1][1]).to eq(1)
      expect(collected[2][1]).to eq(2)
    end

    it "yields correct CharStrings" do
      x_values = []
      charstrings_index.each_charstring(private_dict, global_subrs,
                                        local_subrs) do |cs, _index|
        x_values << cs.path[0][:x]
      end

      expect(x_values).to eq([0.0, 100.0, 200.0])
    end

    it "returns enumerator when no block given" do
      enum = charstrings_index.each_charstring(private_dict, global_subrs,
                                               local_subrs)

      expect(enum).to be_an(Enumerator)
      expect(enum.to_a.size).to eq(3)
    end

    it "does not iterate if empty" do
      empty_data = [0].pack("n")
      empty_charstrings_index = described_class.new(empty_data)

      count = 0
      empty_charstrings_index.each_charstring(private_dict, global_subrs,
                                              local_subrs) { count += 1 }

      expect(count).to eq(0)
    end
  end

  describe "#glyph_count" do
    it "returns number of glyphs" do
      # Create INDEX with 5 glyphs
      charstrings = Array.new(5) do
        build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          14 # endchar
        )
      end

      parts = []
      parts << [5].pack("n")
      parts << [1].pack("C")

      offset = 1
      offsets = [offset]
      charstrings.each do |cs|
        offset += cs.bytesize
        offsets << offset
      end
      parts << offsets.pack("C#{offsets.size}")
      parts << charstrings.join

      data = parts.join
      charstrings_index = described_class.new(data)

      expect(charstrings_index.glyph_count).to eq(5)
    end

    it "returns 0 for empty INDEX" do
      empty_data = [0].pack("n")
      charstrings_index = described_class.new(empty_data)

      expect(charstrings_index.glyph_count).to eq(0)
    end
  end

  describe "#valid_glyph_index?" do
    let(:charstrings_data) do
      charstrings = Array.new(3) do
        build_charstring(encode_int(0), encode_int(0), 21, 14)
      end

      parts = []
      parts << [3].pack("n")
      parts << [1].pack("C")

      offset = 1
      offsets = [offset]
      charstrings.each do |cs|
        offset += cs.bytesize
        offsets << offset
      end
      parts << offsets.pack("C#{offsets.size}")
      parts << charstrings.join

      parts.join
    end

    let(:charstrings_index) { described_class.new(charstrings_data) }

    it "returns true for valid indices" do
      expect(charstrings_index.valid_glyph_index?(0)).to be true
      expect(charstrings_index.valid_glyph_index?(1)).to be true
      expect(charstrings_index.valid_glyph_index?(2)).to be true
    end

    it "returns false for out of bounds indices" do
      expect(charstrings_index.valid_glyph_index?(3)).to be false
      expect(charstrings_index.valid_glyph_index?(10)).to be false
    end

    it "returns false for negative indices" do
      expect(charstrings_index.valid_glyph_index?(-1)).to be false
    end
  end

  describe "#charstring_size" do
    let(:charstrings_data) do
      # Create CharStrings of different sizes
      cs0 = build_charstring(encode_int(0), encode_int(0), 21, 14) # 4 bytes
      cs1 = build_charstring(
        encode_int(100), encode_int(100), 21,
        encode_int(50), encode_int(50), 5,
        14
      ) # 7 bytes

      parts = []
      parts << [2].pack("n")
      parts << [1].pack("C")
      parts << [1, 1 + cs0.bytesize, 1 + cs0.bytesize + cs1.bytesize].pack("C3")
      parts << cs0 << cs1

      parts.join
    end

    let(:charstrings_index) { described_class.new(charstrings_data) }

    it "returns size of CharString without interpreting" do
      size0 = charstrings_index.charstring_size(0)
      size1 = charstrings_index.charstring_size(1)

      expect(size0).to eq(4)
      expect(size1).to eq(7)
    end

    it "returns nil for invalid index" do
      size = charstrings_index.charstring_size(10)

      expect(size).to be_nil
    end
  end

  describe "integration with CharString" do
    let(:charstrings_data) do
      # Create a more complex CharString with width and path
      cs = build_charstring(
        encode_int(50), # width delta (odd number of args before move)
        encode_int(100), encode_int(200), 21, # rmoveto
        encode_int(50), encode_int(0), 5, # rlineto
        encode_int(0), encode_int(-200), 5, # rlineto
        14 # endchar
      )

      parts = []
      parts << [1].pack("n")
      parts << [1].pack("C")
      parts << [1, 1 + cs.bytesize].pack("C2")
      parts << cs

      parts.join
    end

    let(:private_dict) do
      mock_private_dict(default_width: 500, nominal_width: 600)
    end
    let(:charstrings_index) { described_class.new(charstrings_data) }

    it "correctly interprets complex CharString" do
      cs = charstrings_index.charstring_at(0, private_dict, global_subrs,
                                           local_subrs)

      expect(cs.width).to eq(650) # 600 + 50
      expect(cs.path.size).to eq(3)
      expect(cs.path[0][:type]).to eq(:move_to)
      expect(cs.path[1][:type]).to eq(:line_to)
      expect(cs.path[2][:type]).to eq(:line_to)
    end

    it "calculates bounding box correctly" do
      cs = charstrings_index.charstring_at(0, private_dict, global_subrs,
                                           local_subrs)

      bbox = cs.bounding_box
      expect(bbox).to eq([100.0, 0.0, 150.0, 200.0])
    end

    it "converts to commands correctly" do
      cs = charstrings_index.charstring_at(0, private_dict, global_subrs,
                                           local_subrs)

      commands = cs.to_commands
      expect(commands.size).to eq(3)
      expect(commands[0]).to eq([:move_to, 100.0, 200.0])
      expect(commands[1]).to eq([:line_to, 150.0, 200.0])
      expect(commands[2]).to eq([:line_to, 150.0, 0.0])
    end
  end

  describe "memory efficiency" do
    it "does not store all CharStrings in memory" do
      # Create INDEX with many CharStrings
      charstrings = Array.new(100) do |i|
        build_charstring(
          encode_int(i), encode_int(i), 21, # rmoveto
          14 # endchar
        )
      end

      parts = []
      parts << [100].pack("n")
      parts << [2].pack("C") # Use 2-byte offsets

      offset = 1
      offsets = [offset]
      charstrings.each do |cs|
        offset += cs.bytesize
        offsets << offset
      end
      parts << offsets.pack("n#{offsets.size}")
      parts << charstrings.join

      data = parts.join
      charstrings_index = described_class.new(data)

      # Access just one CharString
      cs = charstrings_index.charstring_at(42, private_dict, global_subrs,
                                           local_subrs)

      # Verify it works without loading all
      expect(cs.path[0][:x]).to eq(42.0)
      expect(charstrings_index.glyph_count).to eq(100)
    end
  end
end
