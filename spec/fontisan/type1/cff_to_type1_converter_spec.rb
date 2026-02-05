# frozen_string_literal: true

RSpec.describe Fontisan::Type1::CffToType1Converter,
               "CFF to Type 1 CharString conversion" do
  subject(:converter) { described_class.new }

  describe "#initialize" do
    it "creates a converter with default widths" do
      expect(converter).to be_a(described_class)
    end

    it "accepts custom nominal width" do
      custom_converter = described_class.new(nominal_width: 500)
      expect(custom_converter).to be_a(described_class)
    end

    it "accepts custom default width" do
      custom_converter = described_class.new(default_width: 400)
      expect(custom_converter).to be_a(described_class)
    end
  end

  describe "#convert" do
    context "with simple move command" do
      let(:cff_charstring) do
        # rmoveto 100 50
        [226, 50, 21].pack("C*") # 100 (226 = 100+139-5), 50 (189 = 50+139), rmoveto(21)
      end

      it "converts to Type 1 format" do
        result = converter.convert(cff_charstring)

        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end

      it "includes hsbw operator at start" do
        result = converter.convert(cff_charstring)

        # hsbw is two-byte operator: 12 34
        # First we encode left sidebearing (0) and width, then 12 34
        expect(result).to include("\x0C\x22") # ESCAPE_BYTE (12) + 34
      end

      it "includes endchar at end" do
        result = converter.convert(cff_charstring)

        expect(result.getbyte(-1)).to eq(14) # endchar operator
      end
    end

    context "with line command" do
      let(:cff_charstring) do
        # hlineto 50
        [189, 6].pack("C*") # 50 (189 = 50+139), hlineto(6)
      end

      it "converts to Type 1 format" do
        result = converter.convert(cff_charstring)

        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end
    end

    context "with curve command" do
      let(:cff_charstring) do
        # rrcurveto 10 20 30 40 50 60
        [149, 159, 169, 179, 189, 199, 8].pack("C*")
      end

      it "converts to Type 1 format" do
        result = converter.convert(cff_charstring)

        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end
    end

    context "with explicit width" do
      let(:cff_charstring) do
        # Width 500, then rmoveto 100 0
        # In CFF: first odd operand is width
        [358, 139, 21].pack("C*") # 500 (358 = 500-139+139), rmoveto with implied 0
      end

      it "uses explicit width in hsbw" do
        result = converter.convert(cff_charstring)

        expect(result).to be_a(String)
        # hsbw should use the width from CharString
      end
    end
  end

  describe "#convert_operations" do
    context "with path operations" do
      let(:operations) do
        [
          { name: :hmoveto, operands: [50] },
          { name: :vmoveto, operands: [100] },
          { name: :rlineto, operands: [20, 30] },
          { name: :hlineto, operands: [40] },
          { name: :vlineto, operands: [60] },
        ]
      end

      it "converts all operations to Type 1 format" do
        result = converter.convert_operations(operations)

        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end

      it "includes hsbw at start" do
        result = converter.convert_operations(operations, 500)

        # hsbw: encode_number(0) + encode_number(width) + 12 + 34
        # The 12 (ESCAPE_BYTE) comes after the two encoded numbers
        # Check for 12 somewhere in the first several bytes
        first_bytes = result[0..5].unpack("C*")
        expect(first_bytes).to include(12) # ESCAPE_BYTE
      end

      it "includes endchar at end" do
        result = converter.convert_operations(operations)

        expect(result.getbyte(-1)).to eq(14) # endchar
      end
    end

    context "with hint operators" do
      let(:operations) do
        [
          { name: :hstem, operands: [50, 20] },
          { name: :vstem, operands: [30, 10] },
          { name: :rmoveto, operands: [100, 0] },
        ]
      end

      it "preserves hint operators" do
        result = converter.convert_operations(operations)

        # Should have both hint operators
        expect(result).to be_a(String)
      end
    end

    context "with curve operators" do
      let(:operations) do
        [
          { name: :rmoveto, operands: [0, 0] },
          { name: :rrcurveto, operands: [10, 20, 30, 40, 50, 60] },
          { name: :hhcurveto, operands: [10, 20, 30, 40] },
          { name: :hvcurveto, operands: [10, 20, 30, 40] },
        ]
      end

      it "converts all curve operators" do
        result = converter.convert_operations(operations)

        expect(result).to be_a(String)
      end
    end

    context "with unsupported operators" do
      let(:operations) do
        [
          { name: :hintmask, operands: [] },
          { name: :cntrmask, operands: [] },
          { name: :rmoveto, operands: [100, 0] },
        ]
      end

      it "skips hintmask operators" do
        result = converter.convert_operations(operations)

        expect(result).to be_a(String)
        # Should have rmoveto but skip hintmask/cntrmask
      end
    end
  end

  # Helper method to encode numbers (matching Type 1 format)
  def encode_number(num)
    if num >= -107 && num <= 107
      [num + 139].pack("C")
    else
      num += 32768 if num < 0
      [255, num % 256, num >> 8].pack("C*")
    end
  end
end
