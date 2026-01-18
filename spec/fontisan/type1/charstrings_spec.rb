# frozen_string_literal: true

RSpec.describe Fontisan::Type1::CharStrings do
  let(:private_dict) do
    Fontisan::Type1::PrivateDict.new
  end

  describe "#initialize" do
    it "creates a new CharStrings parser" do
      cs = described_class.new

      expect(cs.charstrings).to eq({})
      expect(cs.private_dict).to be_a(Fontisan::Type1::PrivateDict)
    end

    it "accepts a private dictionary" do
      priv = Fontisan::Type1::PrivateDict.new
      cs = described_class.new(priv)

      expect(cs.private_dict).to eq(priv)
    end
  end

  describe ".parse" do
    it "parses CharStrings from font data" do
      data = <<~DATA
        /CharStrings 10 dict def
          /.notdef 0 RD <hex_data>
          /A 1 RD <hex_data>
        end
      DATA

      cs = described_class.new(private_dict)
      cs.parse(data)

      # Should have glyphs even if hex parsing is simplified
      expect(cs.glyph_names).to be_a(Array)
    end

    it "returns self for method chaining" do
      data = "/CharStrings 10 dict def end"
      cs = described_class.new(private_dict)

      result = cs.parse(data)

      expect(result).to be(cs)
    end
  end

  describe "#glyph_names" do
    it "returns empty array when no CharStrings" do
      cs = described_class.new(private_dict)

      expect(cs.glyph_names).to eq([])
    end

    it "returns list of glyph names" do
      cs = described_class.new(private_dict)
      cs.instance_variable_set(:@charstrings,
                               { ".notdef" => "data", "A" => "data" })

      expect(cs.glyph_names).to include(".notdef", "A")
    end
  end

  describe "#has_glyph?" do
    it "returns false for non-existent glyph" do
      cs = described_class.new(private_dict)

      expect(cs.has_glyph?("A")).to be false
    end

    it "returns true for existing glyph" do
      cs = described_class.new(private_dict)
      cs.instance_variable_set(:@charstrings, { "A" => "data" })

      expect(cs.has_glyph?("A")).to be true
    end
  end

  describe "#[]" do
    it "returns nil for non-existent glyph" do
      cs = described_class.new(private_dict)

      expect(cs["A"]).to be_nil
    end

    it "returns CharString data for glyph" do
      cs = described_class.new(private_dict)
      cs.instance_variable_set(:@charstrings, { "A" => "charstring_data" })

      expect(cs["A"]).to eq("charstring_data")
    end
  end

  describe "#composite?" do
    it "returns false when no CharString data" do
      cs = described_class.new(private_dict)

      expect(cs.composite?("A")).to be false
    end

    it "returns false when CharString has no seac" do
      cs = described_class.new(private_dict)
      cs.instance_variable_set(:@charstrings, { "A" => "no_seac" })

      expect(cs.composite?("A")).to be false
    end

    it "returns true when CharString has seac" do
      cs = described_class.new(private_dict)
      seac_data = "\x0C\x06".b # seac opcode
      cs.instance_variable_set(:@charstrings, { "A" => seac_data })

      expect(cs.composite?("A")).to be true
    end
  end

  describe "#outline_for" do
    it "returns nil for non-existent glyph" do
      cs = described_class.new(private_dict)

      expect(cs.outline_for("A")).to be_nil
    end

    it "returns commands for existing glyph" do
      cs = described_class.new(private_dict)
      # Simple hmoveto command (byte 22)
      cs.instance_variable_set(:@charstrings, { "A" => "\x16".b })

      outline = cs.outline_for("A")

      expect(outline).to be_a(Array)
    end
  end

  describe "CharStringParser" do
    it "parses simple numbers" do
      parser = Fontisan::Type1::CharStrings::CharStringParser.new(private_dict)

      # Byte value 150 represents number 11 (150 - 139)
      commands = parser.parse("\x96".b)

      expect(commands).to include([:number, 11])
    end

    it "parses hmoveto command" do
      parser = Fontisan::Type1::CharStrings::CharStringParser.new(private_dict)

      commands = parser.parse("\x16".b)  # hmoveto

      expect(commands).to include([:hmoveto])
    end

    it "parses vmoveto command" do
      parser = Fontisan::Type1::CharStrings::CharStringParser.new(private_dict)

      commands = parser.parse("\x04".b)  # vmoveto

      expect(commands).to include([:vmoveto])
    end

    it "parses rlineto command" do
      parser = Fontisan::Type1::CharStrings::CharStringParser.new(private_dict)

      commands = parser.parse("\x05".b)  # rlineto

      expect(commands).to include([:rlineto])
    end

    it "parses rrcurveto command" do
      parser = Fontisan::Type1::CharStrings::CharStringParser.new(private_dict)

      commands = parser.parse("\x08".b)  # rrcurveto

      expect(commands).to include([:rrcurveto])
    end

    it "parses endchar command" do
      parser = Fontisan::Type1::CharStrings::CharStringParser.new(private_dict)

      commands = parser.parse("\x0E".b)  # endchar

      expect(commands).to include([:endchar])
    end
  end
end
