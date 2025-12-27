# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff::CharStringParser do
  describe "#initialize" do
    it "creates parser with data" do
      data = "\x00".b
      parser = described_class.new(data)
      expect(parser.data).to eq(data)
    end

    it "creates parser with stem count" do
      data = "\x00".b
      parser = described_class.new(data, stem_count: 5)
      expect(parser).to be_a(described_class)
    end
  end

  describe "#parse" do
    context "with simple operators" do
      it "parses endchar operator" do
        # 14 = endchar
        data = [14].pack("C")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:type]).to eq(:operator)
        expect(ops[0][:name]).to eq(:endchar)
        expect(ops[0][:operands]).to eq([])
      end

      it "parses rmoveto operator" do
        # 21 = rmoveto
        data = [21].pack("C")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:rmoveto)
      end

      it "parses rlineto operator" do
        # 5 = rlineto
        data = [5].pack("C")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:rlineto)
      end

      it "parses rrcurveto operator" do
        # 8 = rrcurveto
        data = [8].pack("C")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:rrcurveto)
      end
    end

    context "with two-byte operators" do
      it "parses flex operator" do
        # 12 35 = flex
        data = [12, 35].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:flex)
      end

      it "parses hflex operator" do
        # 12 34 = hflex
        data = [12, 34].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:hflex)
      end

      it "parses add operator" do
        # 12 10 = add
        data = [12, 10].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:add)
      end
    end

    context "with operands" do
      it "parses small integer operands (-107 to +107)" do
        # 139 + 50 = 189 represents +50
        # 139 - 50 = 89 represents -50
        # 21 = rmoveto
        data = [189, 89, 21].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:rmoveto)
        expect(ops[0][:operands]).to eq([50, -50])
      end

      it "parses positive two-byte integers (108 to 1131)" do
        # 247-250 prefix for positive numbers
        # 247 0 108 = 108 (minimum)
        # 21 = rmoveto
        data = [247, 0, 21].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:operands][0]).to eq(108)
      end

      it "parses negative two-byte integers (-108 to -1131)" do
        # 251-254 prefix for negative numbers
        # 251 0 108 = -108 (minimum)
        # 21 = rmoveto
        data = [251, 0, 21].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:operands][0]).to eq(-108)
      end

      it "parses three-byte integers" do
        # 28 = shortint prefix
        # 16-bit signed integer follows
        # 28 0x01 0x00 = 256
        # 21 = rmoveto
        data = [28, 0x01, 0x00, 21].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:operands][0]).to eq(256)
      end

      it "parses five-byte real numbers" do
        # 255 = real number prefix
        # 32-bit signed integer as 16.16 fixed point
        # 255 0x00 0x01 0x00 0x00 = 1.0
        # 21 = rmoveto
        data = [255, 0x00, 0x01, 0x00, 0x00, 21].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:operands][0]).to be_within(0.001).of(1.0)
      end

      it "parses multiple operands" do
        # 100, 200, 300, 400, 500, 600 then rrcurveto (needs 6 operands)
        # 139+100=239, need two-byte for 200-600
        data = [239].pack("C") # 100
        data += [247, 92].pack("C*") # 200: (247-247)*256 + 92 + 108 = 200
        data += [247, 192].pack("C*") # 300: (247-247)*256 + 192 + 108 = 300
        data += [248, 36].pack("C*") # 400: (248-247)*256 + 36 + 108 = 400
        data += [248, 136].pack("C*") # 500: (248-247)*256 + 136 + 108 = 500
        data += [248, 236].pack("C*") # 600: (248-247)*256 + 236 + 108 = 600
        data += [8].pack("C") # rrcurveto
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:operands].length).to eq(6)
        expect(ops[0][:operands][0]).to eq(100)
        expect(ops[0][:operands][1]).to eq(200)
        expect(ops[0][:operands][2]).to eq(300)
        expect(ops[0][:operands][3]).to eq(400)
        expect(ops[0][:operands][4]).to eq(500)
        expect(ops[0][:operands][5]).to eq(600)
      end
    end

    context "with hint operators" do
      it "parses hstem operator" do
        # 1 = hstem
        data = [1].pack("C")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:hstem)
      end

      it "parses vstem operator" do
        # 3 = vstem
        data = [3].pack("C")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:vstem)
      end

      it "parses hstemhm operator" do
        # 18 = hstemhm
        data = [18].pack("C")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:hstemhm)
      end

      it "parses vstemhm operator" do
        # 23 = vstemhm
        data = [23].pack("C")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:vstemhm)
      end
    end

    context "with hintmask operators" do
      it "parses hintmask with no stems" do
        # 19 = hintmask
        data = [19].pack("C")
        parser = described_class.new(data, stem_count: 0)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:hintmask)
        expect(ops[0][:hint_data]).to be_nil
      end

      it "parses hintmask with 8 stems (1 byte)" do
        # 19 = hintmask, followed by 1 byte of mask data
        data = [19, 0xFF].pack("C*")
        parser = described_class.new(data, stem_count: 8)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:hintmask)
        expect(ops[0][:hint_data]).to eq([0xFF].pack("C"))
      end

      it "parses hintmask with 16 stems (2 bytes)" do
        # 19 = hintmask, followed by 2 bytes of mask data
        data = [19, 0xFF, 0xFF].pack("C*")
        parser = described_class.new(data, stem_count: 16)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:hintmask)
        expect(ops[0][:hint_data]).to eq([0xFF, 0xFF].pack("C*"))
      end

      it "parses cntrmask operator" do
        # 20 = cntrmask
        data = [20, 0xAA].pack("C*")
        parser = described_class.new(data, stem_count: 8)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:cntrmask)
        expect(ops[0][:hint_data]).to eq([0xAA].pack("C"))
      end
    end

    context "with multiple operations" do
      it "parses sequence of operations" do
        # 100 hmoveto (dx)
        # 50 vlineto (dy)
        # endchar
        data = []
        data << 239 # 100
        data << 22  # hmoveto
        data << 189 # 50
        data << 7   # vlineto
        data << 14  # endchar
        parser = described_class.new(data.pack("C*"))
        ops = parser.parse

        expect(ops.length).to eq(3)

        expect(ops[0][:name]).to eq(:hmoveto)
        expect(ops[0][:operands]).to eq([100])

        expect(ops[1][:name]).to eq(:vlineto)
        expect(ops[1][:operands]).to eq([50])

        expect(ops[2][:name]).to eq(:endchar)
        expect(ops[2][:operands]).to eq([])
      end

      it "parses complex glyph outline" do
        # rmoveto with 2 operands
        # rlineto with 2 operands
        # rrcurveto with 6 operands
        # endchar
        data = []
        data += [139, 139] # 0, 0
        data << 21         # rmoveto
        data += [239, 139] # 100, 0
        data << 5          # rlineto
        data += [139, 189, 189, 139, 139, 139] # 0,50,50,0,0,0
        data << 8          # rrcurveto
        data << 14         # endchar

        parser = described_class.new(data.pack("C*"))
        ops = parser.parse

        expect(ops.length).to eq(4)
        expect(ops[0][:name]).to eq(:rmoveto)
        expect(ops[1][:name]).to eq(:rlineto)
        expect(ops[2][:name]).to eq(:rrcurveto)
        expect(ops[3][:name]).to eq(:endchar)
      end
    end

    context "with subroutine operators" do
      it "parses callsubr operator" do
        # 10 = callsubr
        data = [139, 10].pack("C*") # 0 (subr index), callsubr
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:callsubr)
        expect(ops[0][:operands]).to eq([0])
      end

      it "parses callgsubr operator" do
        # 29 = callgsubr
        data = [139, 29].pack("C*") # 0 (subr index), callgsubr
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:callgsubr)
        expect(ops[0][:operands]).to eq([0])
      end

      it "parses return operator" do
        # 11 = return
        data = [11].pack("C")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:return)
      end
    end

    context "with arithmetic operators" do
      it "parses add operator with operands" do
        # 10 20 add
        data = [149, 159, 12, 10].pack("C*") # 10, 20, add
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops.length).to eq(1)
        expect(ops[0][:name]).to eq(:add)
        expect(ops[0][:operands]).to eq([10, 20])
      end

      it "parses sub operator" do
        data = [12, 11].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops[0][:name]).to eq(:sub)
      end

      it "parses mul operator" do
        data = [12, 24].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops[0][:name]).to eq(:mul)
      end

      it "parses div operator" do
        data = [12, 12].pack("C*")
        parser = described_class.new(data)
        ops = parser.parse

        expect(ops[0][:name]).to eq(:div)
      end
    end

    context "error handling" do
      it "raises error on corrupted data (unexpected EOF)" do
        # 28 = shortint prefix but missing bytes
        data = [28].pack("C")
        parser = described_class.new(data)

        expect { parser.parse }.to raise_error(
          Fontisan::CorruptedTableError,
          /Failed to parse CharString/
        )
      end

      it "raises error on corrupted two-byte operator" do
        # 12 prefix but missing second byte
        data = [12].pack("C")
        parser = described_class.new(data)

        expect { parser.parse }.to raise_error(
          Fontisan::CorruptedTableError
        )
      end
    end
  end

  describe "#stem_count=" do
    it "updates stem count" do
      parser = described_class.new("\x00".b, stem_count: 0)
      parser.stem_count = 8
      # Verify it works with hintmask
      data = [19, 0xFF].pack("C*")
      parser = described_class.new(data, stem_count: 8)
      ops = parser.parse
      expect(ops[0][:hint_data]).not_to be_nil
    end
  end
end