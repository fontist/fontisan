# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Hints::TrueTypeHintApplier do
  let(:applier) { described_class.new }
  let(:tables) { {} }

  describe "#apply" do
    context "with TrueType HintSet containing all font-level hints" do
      let(:hint_set) do
        set = Fontisan::Models::HintSet.new(format: :truetype)
        set.font_program = "\x00\x01\x02\x03" # Sample fpgm bytecode
        set.control_value_program = "\x10\x11\x12" # Sample prep bytecode
        set.control_values = [100, 200, 300, 400] # Sample cvt values
        set
      end

      it "writes fpgm table" do
        result = applier.apply(hint_set, tables)
        expect(result["fpgm"]).not_to be_nil
        expect(result["fpgm"][:tag]).to eq("fpgm")
        expect(result["fpgm"][:data]).to eq("\x00\x01\x02\x03")
      end

      it "writes prep table" do
        result = applier.apply(hint_set, tables)
        expect(result["prep"]).not_to be_nil
        expect(result["prep"][:tag]).to eq("prep")
        expect(result["prep"][:data]).to eq("\x10\x11\x12")
      end

      it "writes cvt table" do
        result = applier.apply(hint_set, tables)
        expect(result["cvt "]).not_to be_nil
        expect(result["cvt "][:tag]).to eq("cvt ")

        # cvt values are packed as 16-bit big-endian signed integers
        expected_data = [100, 200, 300, 400].pack("n*")
        expect(result["cvt "][:data]).to eq(expected_data)
      end

      it "calculates checksums correctly for all tables" do
        result = applier.apply(hint_set, tables)

        expect(result["fpgm"][:checksum]).to be_a(Integer)
        expect(result["fpgm"][:checksum]).to be > 0

        expect(result["prep"][:checksum]).to be_a(Integer)
        expect(result["prep"][:checksum]).to be > 0

        expect(result["cvt "][:checksum]).to be_a(Integer)
        expect(result["cvt "][:checksum]).to be > 0
      end

      it "writes all three tables together" do
        result = applier.apply(hint_set, tables)

        expect(result.keys).to include("fpgm", "prep", "cvt ")
        expect(result.size).to eq(3)
      end
    end

    context "with HintSet containing only fpgm" do
      let(:hint_set) do
        set = Fontisan::Models::HintSet.new(format: :truetype)
        set.font_program = "\xB0\x01\xB8" # Sample fpgm bytecode
        set
      end

      it "writes only fpgm table" do
        result = applier.apply(hint_set, tables)

        expect(result["fpgm"]).not_to be_nil
        expect(result["prep"]).to be_nil
        expect(result["cvt "]).to be_nil
      end

      it "calculates fpgm checksum correctly" do
        result = applier.apply(hint_set, tables)

        expect(result["fpgm"][:checksum]).to be_a(Integer)
      end
    end

    context "with HintSet containing only prep" do
      let(:hint_set) do
        set = Fontisan::Models::HintSet.new(format: :truetype)
        set.control_value_program = "\x20\x21\x22\x23"
        set
      end

      it "writes only prep table" do
        result = applier.apply(hint_set, tables)

        expect(result["fpgm"]).to be_nil
        expect(result["prep"]).not_to be_nil
        expect(result["cvt "]).to be_nil
      end
    end

    context "with HintSet containing only cvt" do
      let(:hint_set) do
        set = Fontisan::Models::HintSet.new(format: :truetype)
        set.control_values = [50, 100, 150]
        set
      end

      it "writes only cvt table" do
        result = applier.apply(hint_set, tables)

        expect(result["fpgm"]).to be_nil
        expect(result["prep"]).to be_nil
        expect(result["cvt "]).not_to be_nil
      end

      it "packs cvt values correctly" do
        result = applier.apply(hint_set, tables)

        # Unpack to verify correct encoding (signed 16-bit big-endian)
        cvt_data = result["cvt "][:data]
        values = cvt_data.unpack("s>*")
        expect(values).to eq([50, 100, 150])
      end
    end

    context "with empty hint set" do
      let(:hint_set) { Fontisan::Models::HintSet.new(format: :truetype) }

      it "returns tables unchanged" do
        result = applier.apply(hint_set, tables)
        expect(result).to eq(tables)
        expect(result).to be_empty
      end
    end

    context "with nil hint set" do
      it "returns tables unchanged" do
        result = applier.apply(nil, tables)
        expect(result).to eq(tables)
      end
    end

    context "with PostScript hint set (wrong format)" do
      let(:hint_set) do
        set = Fontisan::Models::HintSet.new(format: :postscript)
        set.private_dict_hints = { "std_hw" => 68 }.to_json
        set
      end

      it "returns tables unchanged" do
        result = applier.apply(hint_set, tables)
        expect(result).to eq(tables)
      end
    end

    context "with existing tables" do
      let(:existing_tables) do
        {
          "head" => { tag: "head", data: "...", checksum: 12345 },
          "name" => { tag: "name", data: "...", checksum: 67890 },
        }
      end

      let(:hint_set) do
        set = Fontisan::Models::HintSet.new(format: :truetype)
        set.font_program = "\x00\x01"
        set
      end

      it "preserves existing tables while adding hint tables" do
        result = applier.apply(hint_set, existing_tables)

        expect(result["head"]).to eq(existing_tables["head"])
        expect(result["name"]).to eq(existing_tables["name"])
        expect(result["fpgm"]).not_to be_nil
      end
    end

    context "checksum calculation" do
      it "handles data requiring padding" do
        # Test with 1-byte data (needs 3 bytes padding)
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.font_program = "\x00"

        result = applier.apply(hint_set, tables)
        expect(result["fpgm"][:checksum]).to be_a(Integer)
      end

      it "handles data requiring 2 bytes padding" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.font_program = "\x00\x01"

        result = applier.apply(hint_set, tables)
        expect(result["fpgm"][:checksum]).to be_a(Integer)
      end

      it "handles data requiring 3 bytes padding" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.font_program = "\x00\x01\x02"

        result = applier.apply(hint_set, tables)
        expect(result["fpgm"][:checksum]).to be_a(Integer)
      end

      it "handles data already aligned to 4 bytes" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.font_program = "\x00\x01\x02\x03"

        result = applier.apply(hint_set, tables)
        expect(result["fpgm"][:checksum]).to be_a(Integer)
      end

      it "produces consistent checksums for identical data" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.font_program = "\xB0\x01\xB8\x02"

        result1 = applier.apply(hint_set, {})
        result2 = applier.apply(hint_set, {})

        expect(result1["fpgm"][:checksum]).to eq(result2["fpgm"][:checksum])
      end
    end

    context "cvt value encoding" do
      it "handles positive values" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.control_values = [100, 200, 500, 1000]

        result = applier.apply(hint_set, tables)
        values = result["cvt "][:data].unpack("s>*")
        expect(values).to eq([100, 200, 500, 1000])
      end

      it "handles small values" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.control_values = [0, 1, 5, 10]

        result = applier.apply(hint_set, tables)
        values = result["cvt "][:data].unpack("s>*")
        expect(values).to eq([0, 1, 5, 10])
      end

      it "handles large positive values" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.control_values = [10000, 20000, 30000]

        result = applier.apply(hint_set, tables)
        values = result["cvt "][:data].unpack("s>*")
        expect(values).to eq([10000, 20000, 30000])
      end

      it "handles single value" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.control_values = [512]

        result = applier.apply(hint_set, tables)
        values = result["cvt "][:data].unpack("s>*")
        expect(values).to eq([512])
      end

      it "handles many values" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.control_values = (1..100).to_a

        result = applier.apply(hint_set, tables)
        values = result["cvt "][:data].unpack("s>*")
        expect(values).to eq((1..100).to_a)
      end
    end
  end
end
