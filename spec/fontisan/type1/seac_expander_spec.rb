# frozen_string_literal: true

RSpec.describe Fontisan::Type1::SeacExpander, "seac composite decomposition" do
  subject(:expander) { described_class.new(charstrings, private_dict) }

  let(:private_dict) { Fontisan::Type1::PrivateDict.new }

  describe "#composite?" do
    let(:charstrings) do
      Fontisan::Type1::CharStrings.from_hash(
        {
          "B" => build_charstring([[:hsbw, 100, 0], [:endchar]]),
          "Agrave" => build_seac_charstring(100, 200, 50, 65, 96),
        },
        encoding: { 65 => "A", 96 => "grave" },
      )
    end

    it "returns false for non-composite glyphs" do
      expect(expander.composite?("B")).to be false
    end

    it "returns true for seac composite glyphs" do
      expect(expander.composite?("Agrave")).to be true
    end

    it "returns false when glyph doesn't exist" do
      expect(expander.composite?("NonExistent")).to be false
    end
  end

  describe "#decompose — single-level seac" do
    let(:charstrings) do
      Fontisan::Type1::CharStrings.from_hash(
        {
          "Agrave" => build_seac_charstring(100, 200, 50, 65, 96),
          "A" => build_charstring([[:hsbw, 100, 0], [:endchar]]),
          "grave" => build_charstring([[:hsbw, 50, 100], [:endchar]]),
        },
        encoding: { 65 => "A", 96 => "grave" },
      )
    end

    it "decomposes a seac composite into merged CharString" do
      result = expander.decompose("Agrave")
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "returns nil for non-composite glyphs" do
      expect(expander.decompose("A")).to be_nil
    end

    it "returns nil for non-existent glyphs" do
      expect(expander.decompose("NonExistent")).to be_nil
    end
  end

  describe "#decompose — nested seac" do
    # Agrave = base=A (bchar=65), accent=grave (achar=96) → 1 level
    # Adieresis = base=Agrave (bchar=66), accent=dieresis (achar=97) → 2 levels
    let(:charstrings) do
      Fontisan::Type1::CharStrings.from_hash(
        {
          "A" => build_charstring([[:hsbw, 100, 0], [:endchar]]),
          "grave" => build_charstring([[:hsbw, 50, 100], [:endchar]]),
          "dieresis" => build_charstring([[:hsbw, 50, 200], [:endchar]]),
          "Agrave" => build_seac_charstring(100, 200, 50, 65, 96),
          "Adieresis" => build_seac_charstring(100, 0, 300, 66, 97),
        },
        encoding: { 65 => "A", 66 => "Agrave", 96 => "grave", 97 => "dieresis" },
      )
    end

    it "recursively expands nested seac in the base glyph" do
      # Adieresis references Agrave (bchar=66) which is itself a seac composite
      result = expander.decompose("Adieresis")
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end

  describe "#decompose — error handling" do
    context "when base glyph is not in encoding" do
      let(:charstrings) do
        Fontisan::Type1::CharStrings.from_hash(
          { "Agrave" => build_seac_charstring(100, 200, 50, 65, 96) },
          encoding: { 96 => "grave" },
        )
      end

      it "raises SeacReferenceError" do
        expect do
          expander.decompose("Agrave")
        end.to raise_error(Fontisan::Type1::SeacReferenceError, /base.*not found/i)
      end
    end

    context "when accent glyph is not in encoding" do
      let(:charstrings) do
        Fontisan::Type1::CharStrings.from_hash(
          {
            "Agrave" => build_seac_charstring(100, 200, 50, 65, 96),
            "A" => build_charstring([[:hsbw, 100, 0], [:endchar]]),
          },
          encoding: { 65 => "A" },
        )
      end

      it "raises SeacReferenceError" do
        expect do
          expander.decompose("Agrave")
        end.to raise_error(Fontisan::Type1::SeacReferenceError, /accent.*not found/i)
      end
    end

    context "when charstring data is missing for a resolved glyph" do
      let(:charstrings) do
        Fontisan::Type1::CharStrings.from_hash(
          { "Agrave" => build_seac_charstring(100, 200, 50, 65, 96) },
          encoding: { 65 => "A", 96 => "grave" },
        )
      end

      it "raises SeacReferenceError" do
        expect do
          expander.decompose("Agrave")
        end.to raise_error(Fontisan::Type1::SeacReferenceError, /CharString not found/i)
      end
    end
  end

  describe "#composite_glyphs" do
    let(:charstrings) do
      Fontisan::Type1::CharStrings.from_hash(
        {
          "Agrave" => build_seac_charstring(100, 200, 50, 65, 96),
          "Eacute" => build_seac_charstring(100, 200, 30, 69, 39),
          "B" => build_charstring([[:hsbw, 100, 0], [:endchar]]),
        },
        encoding: {},
      )
    end

    it "returns list of composite glyph names" do
      composites = expander.composite_glyphs
      expect(composites).to include("Agrave", "Eacute")
      expect(composites).not_to include("B")
    end

    it "returns empty array when no composites exist" do
      cs = Fontisan::Type1::CharStrings.from_hash(
        { "B" => build_charstring([[:hsbw, 100, 0], [:endchar]]) },
      )
      exp = described_class.new(cs, private_dict)
      expect(exp.composite_glyphs).to eq([])
    end
  end

  # ---- helpers ----
  # Commands are arrays of [operator, *args]. e.g. [[:hsbw, 100, 0], [:endchar]]

  def build_charstring(commands)
    s = String.new(encoding: Encoding::ASCII_8BIT)
    commands.each do |cmd|
      op = cmd[0]
      case op
      when :hsbw
        s << encode_number(cmd[1])
        s << encode_number(cmd[2])
        s << 12
        s << 34
      when :endchar
        s << 14
      end
    end
    s
  end

  def build_seac_charstring(asb, adx, ady, bchar, achar)
    s = String.new(encoding: Encoding::ASCII_8BIT)
    s << encode_number(asb)
    s << encode_number(adx)
    s << encode_number(ady)
    s << encode_number(bchar)
    s << encode_number(achar)
    s << 12
    s << 6
    s
  end

  def encode_number(num)
    if num >= -107 && num <= 107
      [num + 139].pack("C")
    else
      num += 32_768 if num.negative?
      [255, num % 256, num >> 8].pack("C*")
    end
  end
end
