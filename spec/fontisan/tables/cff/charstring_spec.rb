# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff::CharString do
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

  # Helper to create an INDEX with subroutines
  def create_subr_index(subrs)
    count = subrs.size
    return empty_index if count == 0

    parts = []
    parts << [count].pack("n") # count
    parts << [1].pack("C")     # offSize = 1

    # Calculate offsets
    offsets = [1]
    subrs.each do |subr|
      offsets << (offsets.last + subr.bytesize)
    end
    parts << offsets.pack("C#{offsets.size}") # offsets

    # Add data
    parts << subrs.join

    Fontisan::Tables::Cff::Index.new(parts.join)
  end

  # Helper to build CharString binary data
  def build_charstring(*bytes)
    bytes.flatten.pack("C*")
  end

  # Number encoding helpers
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
    when -32768..32767
      [28, (value >> 8) & 0xFF, value & 0xFF]
    else
      # 32-bit as fixed point 16.16
      fixed = (value * 65536.0).to_i
      [255, (fixed >> 24) & 0xFF, (fixed >> 16) & 0xFF,
       (fixed >> 8) & 0xFF, fixed & 0xFF]
    end
  end

  let(:private_dict) { mock_private_dict }
  let(:global_subrs) { empty_index }
  let(:local_subrs) { nil }

  describe "basic path construction" do
    context "with rmoveto" do
      it "moves to relative position" do
        # 100 200 rmoveto endchar
        data = build_charstring(
          encode_int(100),
          encode_int(200),
          21, # rmoveto
          14, # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(1)
        expect(cs.path[0]).to eq(type: :move_to, x: 100.0, y: 200.0)
      end

      it "handles negative coordinates" do
        # -50 -75 rmoveto endchar
        data = build_charstring(
          encode_int(-50),
          encode_int(-75),
          21, # rmoveto
          14, # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path[0]).to eq(type: :move_to, x: -50.0, y: -75.0)
      end
    end

    context "with hmoveto" do
      it "moves horizontally" do
        # 150 hmoveto endchar
        data = build_charstring(
          encode_int(150),
          22, # hmoveto
          14, # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path[0]).to eq(type: :move_to, x: 150.0, y: 0.0)
      end
    end

    context "with vmoveto" do
      it "moves vertically" do
        # 200 vmoveto endchar
        data = build_charstring(
          encode_int(200),
          4, # vmoveto
          14, # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path[0]).to eq(type: :move_to, x: 0.0, y: 200.0)
      end
    end
  end

  describe "line drawing" do
    context "with rlineto" do
      it "draws single line" do
        # 0 0 rmoveto 100 0 rlineto endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(100), encode_int(0), 5, # rlineto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(2)
        expect(cs.path[0]).to eq(type: :move_to, x: 0.0, y: 0.0)
        expect(cs.path[1]).to eq(type: :line_to, x: 100.0, y: 0.0)
      end

      it "draws multiple lines" do
        # 0 0 rmoveto 50 0 50 100 rlineto endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(50), encode_int(0),
          encode_int(50), encode_int(100),
          5, # rlineto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(3)
        expect(cs.path[1]).to eq(type: :line_to, x: 50.0, y: 0.0)
        expect(cs.path[2]).to eq(type: :line_to, x: 100.0, y: 100.0)
      end
    end

    context "with hlineto" do
      it "alternates horizontal and vertical lines" do
        # 0 0 rmoveto 100 50 hlineto endchar
        # First is horizontal, second is vertical
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(100),
          encode_int(50),
          6, # hlineto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(3)
        expect(cs.path[1]).to eq(type: :line_to, x: 100.0, y: 0.0)
        expect(cs.path[2]).to eq(type: :line_to, x: 100.0, y: 50.0)
      end
    end

    context "with vlineto" do
      it "alternates vertical and horizontal lines" do
        # 0 0 rmoveto 100 50 vlineto endchar
        # First is vertical, second is horizontal
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(100),
          encode_int(50),
          7, # vlineto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(3)
        expect(cs.path[1]).to eq(type: :line_to, x: 0.0, y: 100.0)
        expect(cs.path[2]).to eq(type: :line_to, x: 50.0, y: 100.0)
      end
    end
  end

  describe "curve drawing" do
    context "with rrcurveto" do
      it "draws cubic Bézier curve" do
        # 0 0 rmoveto 10 20 30 40 50 60 rrcurveto endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(10), encode_int(20),
          encode_int(30), encode_int(40),
          encode_int(50), encode_int(60),
          8, # rrcurveto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(2)
        curve = cs.path[1]
        expect(curve[:type]).to eq(:curve_to)
        expect(curve[:x1]).to eq(10.0)
        expect(curve[:y1]).to eq(20.0)
        expect(curve[:x2]).to eq(40.0) # 10 + 30
        expect(curve[:y2]).to eq(60.0) # 20 + 40
        expect(curve[:x]).to eq(90.0)  # 40 + 50
        expect(curve[:y]).to eq(120.0) # 60 + 60
      end

      it "draws multiple curves" do
        # 0 0 rmoveto 10 10 10 10 10 10 20 20 20 20 20 20 rrcurveto endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(10), encode_int(10),
          encode_int(10), encode_int(10),
          encode_int(10), encode_int(10),
          encode_int(20), encode_int(20),
          encode_int(20), encode_int(20),
          encode_int(20), encode_int(20),
          8, # rrcurveto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(3) # move + 2 curves
        expect(cs.path[1][:type]).to eq(:curve_to)
        expect(cs.path[2][:type]).to eq(:curve_to)
      end
    end

    context "with hhcurveto" do
      it "draws horizontal-horizontal curve" do
        # 0 0 rmoveto 10 20 30 40 hhcurveto endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(10), encode_int(20),
          encode_int(30), encode_int(40),
          27, # hhcurveto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(2)
        curve = cs.path[1]
        expect(curve[:type]).to eq(:curve_to)
        expect(curve[:x1]).to eq(10.0)
        expect(curve[:y1]).to eq(0.0)
        expect(curve[:x2]).to eq(30.0)
        expect(curve[:y2]).to eq(30.0)
        expect(curve[:x]).to eq(70.0)
        expect(curve[:y]).to eq(30.0)
      end

      it "handles initial dy value when odd number of args" do
        # 0 0 rmoveto 5 10 20 30 40 hhcurveto endchar
        # 5 is dy1 (odd number of args)
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(5),
          encode_int(10), encode_int(20),
          encode_int(30), encode_int(40),
          27, # hhcurveto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        curve = cs.path[1]
        expect(curve[:y1]).to eq(5.0) # Initial dy applied
      end
    end

    context "with vvcurveto" do
      it "draws vertical-vertical curve" do
        # 0 0 rmoveto 10 20 30 40 vvcurveto endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(10), encode_int(20),
          encode_int(30), encode_int(40),
          26, # vvcurveto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(2)
        curve = cs.path[1]
        expect(curve[:type]).to eq(:curve_to)
        expect(curve[:x1]).to eq(0.0)
        expect(curve[:y1]).to eq(10.0)
      end
    end

    context "with hvcurveto" do
      it "draws horizontal-vertical curve" do
        # 0 0 rmoveto 10 20 30 40 hvcurveto endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(10), encode_int(20),
          encode_int(30), encode_int(40),
          31, # hvcurveto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(2)
        curve = cs.path[1]
        expect(curve[:x1]).to eq(10.0)
        expect(curve[:y1]).to eq(0.0)
      end
    end

    context "with vhcurveto" do
      it "draws vertical-horizontal curve" do
        # 0 0 rmoveto 10 20 30 40 vhcurveto endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(10), encode_int(20),
          encode_int(30), encode_int(40),
          30, # vhcurveto
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(2)
        curve = cs.path[1]
        expect(curve[:x1]).to eq(0.0)
        expect(curve[:y1]).to eq(10.0)
      end
    end

    context "with rcurveline" do
      it "draws curves followed by line" do
        # 0 0 rmoveto 10 20 30 40 50 60 100 200 rcurveline endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(10), encode_int(20),
          encode_int(30), encode_int(40),
          encode_int(50), encode_int(60),
          encode_int(100), encode_int(200),
          24, # rcurveline
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(3)
        expect(cs.path[1][:type]).to eq(:curve_to)
        expect(cs.path[2][:type]).to eq(:line_to)
        expect(cs.path[2][:x]).to eq(190.0)
        expect(cs.path[2][:y]).to eq(320.0)
      end
    end

    context "with rlinecurve" do
      it "draws lines followed by curve" do
        # 0 0 rmoveto 50 50 100 100 10 20 30 40 50 60 rlinecurve endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(50), encode_int(50),
          encode_int(100), encode_int(100),
          encode_int(10), encode_int(20),
          encode_int(30), encode_int(40),
          encode_int(50), encode_int(60),
          25, # rlinecurve
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(4) # move + 2 lines + 1 curve
        expect(cs.path[1][:type]).to eq(:line_to)
        expect(cs.path[2][:type]).to eq(:line_to)
        expect(cs.path[3][:type]).to eq(:curve_to)
      end
    end
  end

  describe "width handling" do
    let(:private_dict) do
      mock_private_dict(default_width: 500, nominal_width: 600)
    end

    it "uses default width when no width specified" do
      # 0 0 rmoveto endchar (even number of operands = use default)
      data = build_charstring(
        encode_int(0), encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.width).to eq(500)
    end

    it "uses nominal + delta when width specified" do
      # 50 0 0 rmoveto endchar (odd number = first is width delta)
      data = build_charstring(
        encode_int(50),
        encode_int(0), encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.width).to eq(650) # 600 + 50
    end

    it "parses width before hmoveto" do
      # 100 50 hmoveto endchar
      data = build_charstring(
        encode_int(100),
        encode_int(50), 22, # hmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.width).to eq(700) # 600 + 100
      expect(cs.path[0][:x]).to eq(50.0)
    end

    it "parses width before vmoveto" do
      # 75 100 vmoveto endchar
      data = build_charstring(
        encode_int(75),
        encode_int(100), 4, # vmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.width).to eq(675) # 600 + 75
      expect(cs.path[0][:y]).to eq(100.0)
    end
  end

  describe "arithmetic operators" do
    it "performs addition" do
      # Build a CharString that uses add in a way we can observe
      # We'll use: 100 50 add 0 rmoveto (result: 150 0 rmoveto)
      data = build_charstring(
        encode_int(100),
        encode_int(50),
        [12, 10], # add
        encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.path[0][:x]).to eq(150.0)
    end

    it "performs subtraction" do
      # 100 50 sub 0 rmoveto (result: 50 0 rmoveto)
      data = build_charstring(
        encode_int(100),
        encode_int(50),
        [12, 11], # sub
        encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.path[0][:x]).to eq(50.0)
    end

    it "performs multiplication" do
      # 10 5 mul 0 rmoveto (result: 50 0 rmoveto)
      data = build_charstring(
        encode_int(10),
        encode_int(5),
        [12, 24], # mul
        encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.path[0][:x]).to eq(50.0)
    end

    it "performs division" do
      # 100 4 div 0 rmoveto (result: 25 0 rmoveto)
      data = build_charstring(
        encode_int(100),
        encode_int(4),
        [12, 12], # div
        encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.path[0][:x]).to eq(25.0)
    end

    it "performs negation" do
      # 100 neg 0 rmoveto (result: -100 0 rmoveto)
      data = build_charstring(
        encode_int(100),
        [12, 14], # neg
        encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.path[0][:x]).to eq(-100.0)
    end

    it "performs absolute value" do
      # -50 abs 0 rmoveto (result: 50 0 rmoveto)
      data = build_charstring(
        encode_int(-50),
        [12, 9], # abs
        encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.path[0][:x]).to eq(50.0)
    end
  end

  describe "subroutine calls" do
    context "with local subroutines" do
      it "calls local subroutine" do
        # Subroutine: 50 50 rlineto return
        subr = build_charstring(
          encode_int(50), encode_int(50), 5, # rlineto
          11 # return
        )
        local_subrs = create_subr_index([subr])

        # Main: 0 0 rmoveto 0 callsubr endchar
        # Bias for 1 subroutine is 107, so callsubr(0) -> index 107
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(0 - 107), 10, # callsubr (index 0)
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(2)
        expect(cs.path[1][:type]).to eq(:line_to)
        expect(cs.path[1][:x]).to eq(50.0)
        expect(cs.path[1][:y]).to eq(50.0)
      end
    end

    context "with global subroutines" do
      it "calls global subroutine" do
        # Global subroutine: 100 100 rlineto return
        gsubr = build_charstring(
          encode_int(100), encode_int(100), 5, # rlineto
          11 # return
        )
        global_subrs = create_subr_index([gsubr])

        # Main: 0 0 rmoveto 0 callgsubr endchar
        data = build_charstring(
          encode_int(0), encode_int(0), 21, # rmoveto
          encode_int(0 - 107), 29, # callgsubr (index 0)
          14 # endchar
        )

        cs = described_class.new(data, private_dict, global_subrs,
                                 local_subrs)

        expect(cs.path.size).to eq(2)
        expect(cs.path[1][:x]).to eq(100.0)
        expect(cs.path[1][:y]).to eq(100.0)
      end
    end
  end

  describe "bounding box calculation" do
    it "calculates bounding box from path" do
      # Rectangle: 0,0 -> 100,0 -> 100,200 -> 0,200
      data = build_charstring(
        encode_int(0), encode_int(0), 21, # rmoveto (0,0)
        encode_int(100), encode_int(0), 5, # rlineto (100,0)
        encode_int(0), encode_int(200), 5, # rlineto (100,200)
        encode_int(-100), encode_int(0), 5, # rlineto (0,200)
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      bbox = cs.bounding_box
      expect(bbox).to eq([0.0, 0.0, 100.0, 200.0])
    end

    it "returns nil for empty path" do
      data = build_charstring(14) # just endchar

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.bounding_box).to be_nil
    end

    it "includes curve control points in bounding box" do
      # Draw a curve that extends beyond end points
      data = build_charstring(
        encode_int(0), encode_int(0), 21, # rmoveto (0,0)
        encode_int(50), encode_int(100), # cp1
        encode_int(50), encode_int(-50), # cp2
        encode_int(50), encode_int(100), # end
        8, # rrcurveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      bbox = cs.bounding_box
      # Should include control points (50,100) and (100,50)
      expect(bbox[3]).to be >= 100.0 # max y includes cp1
    end
  end

  describe "command conversion" do
    it "converts path to drawing commands" do
      # Simple path: move, line, curve
      data = build_charstring(
        encode_int(0), encode_int(0), 21, # rmoveto
        encode_int(100), encode_int(0), 5, # rlineto
        encode_int(10), encode_int(20),
        encode_int(30), encode_int(40),
        encode_int(50), encode_int(60),
        8, # rrcurveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      commands = cs.to_commands
      expect(commands.size).to eq(3)
      expect(commands[0]).to eq([:move_to, 0.0, 0.0])
      expect(commands[1]).to eq([:line_to, 100.0, 0.0])
      expect(commands[2]).to eq([:curve_to, 110.0, 20.0, 140.0, 60.0,
                                 190.0, 120.0])
    end
  end

  describe "number parsing" do
    it "parses small integers" do
      # Values -107 to +107 (single byte encoding)
      data = build_charstring(
        encode_int(0), encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.path[0]).to eq(type: :move_to, x: 0.0, y: 0.0)
    end

    it "parses medium integers" do
      # 16-bit signed integers (operator 28)
      data = build_charstring(
        [28, 0x03, 0xE8], # 1000
        encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.path[0][:x]).to eq(1000.0)
    end

    it "parses large integers as fixed point" do
      # 32-bit fixed point (operator 255)
      # Value 1.5 = 1.5 * 65536 = 98304 = 0x00018000
      data = build_charstring(
        [255, 0x00, 0x01, 0x80, 0x00], # 1.5
        encode_int(0), 21, # rmoveto
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      expect(cs.path[0][:x]).to be_within(0.01).of(1.5)
    end
  end

  describe "hint operators" do
    it "handles hstem without error" do
      # hstem operators clear stack but don't affect path
      data = build_charstring(
        encode_int(10), encode_int(50), 1, # hstem
        encode_int(0), encode_int(0), 21, # rmoveto
        14 # endchar
      )

      expect do
        described_class.new(data, private_dict, global_subrs, local_subrs)
      end.not_to raise_error
    end

    it "handles vstem without error" do
      data = build_charstring(
        encode_int(20), encode_int(60), 3, # vstem
        encode_int(0), encode_int(0), 21, # rmoveto
        14 # endchar
      )

      expect do
        described_class.new(data, private_dict, global_subrs, local_subrs)
      end.not_to raise_error
    end
  end

  describe "error handling" do
    it "raises error on corrupted data" do
      data = "\xFF\xFF\xFF" # Invalid CharString

      expect do
        described_class.new(data, private_dict, global_subrs, local_subrs)
      end.to raise_error(Fontisan::CorruptedTableError)
    end

    it "handles empty CharString" do
      data = "" # Empty data

      expect do
        described_class.new(data, private_dict, global_subrs, local_subrs)
      end.not_to raise_error
    end
  end

  describe "flex operators" do
    it "handles hflex operator" do
      # hflex converts to two curves
      data = build_charstring(
        encode_int(0), encode_int(0), 21, # rmoveto
        encode_int(50), encode_int(0),
        encode_int(50), encode_int(0),
        encode_int(50), encode_int(0),
        encode_int(50),
        [12, 34], # hflex
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      # Should produce move + 2 curves
      expect(cs.path.size).to eq(3)
      expect(cs.path[1][:type]).to eq(:curve_to)
      expect(cs.path[2][:type]).to eq(:curve_to)
    end

    it "handles flex operator" do
      data = build_charstring(
        encode_int(0), encode_int(0), 21, # rmoveto
        encode_int(10), encode_int(20),
        encode_int(30), encode_int(40),
        encode_int(50), encode_int(60),
        encode_int(10), encode_int(20),
        encode_int(30), encode_int(40),
        encode_int(50), encode_int(60),
        encode_int(50), # fd (flex depth)
        [12, 35], # flex
        14 # endchar
      )

      cs = described_class.new(data, private_dict, global_subrs,
                               local_subrs)

      # Should produce move + 2 curves
      expect(cs.path.size).to eq(3)
    end
  end
end
