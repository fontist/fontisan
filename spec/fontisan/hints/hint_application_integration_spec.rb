# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Hint Application Integration" do
  describe "TrueType hint application" do
    context "with font-level hints" do
      it "applies fpgm table without corrupting font structure" do
        # Create hint set with fpgm
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.font_program = "\xB0\x01\xB8\x02\xFF" # Sample bytecode

        # Apply to tables
        applier = Fontisan::Hints::TrueTypeHintApplier.new
        tables = {}
        result = applier.apply(hint_set, tables)

        # Verify table structure
        expect(result["fpgm"]).not_to be_nil
        expect(result["fpgm"][:tag]).to eq("fpgm")
        expect(result["fpgm"][:data]).to eq("\xB0\x01\xB8\x02\xFF")
        expect(result["fpgm"][:checksum]).to be_a(Integer)
        expect(result["fpgm"][:checksum]).to be > 0
      end

      it "applies prep table without corrupting font structure" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.control_value_program = "\x20\x21\x22"

        applier = Fontisan::Hints::TrueTypeHintApplier.new
        tables = {}
        result = applier.apply(hint_set, tables)

        expect(result["prep"]).not_to be_nil
        expect(result["prep"][:data]).to eq("\x20\x21\x22")
        expect(result["prep"][:checksum]).to be_a(Integer)
      end

      it "applies cvt table with correct data encoding" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.control_values = [100, 200, 300, 400, 500]

        applier = Fontisan::Hints::TrueTypeHintApplier.new
        tables = {}
        result = applier.apply(hint_set, tables)

        expect(result["cvt "]).not_to be_nil

        # Verify data integrity by unpacking (signed 16-bit big-endian)
        cvt_data = result["cvt "][:data]
        values = cvt_data.unpack("s>*")
        expect(values).to eq([100, 200, 300, 400, 500])

        # Verify checksum
        expect(result["cvt "][:checksum]).to be_a(Integer)
      end

      it "applies all three tables together coherently" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.font_program = "\xB0\x01"
        hint_set.control_value_program = "\x20"
        hint_set.control_values = [100]

        applier = Fontisan::Hints::TrueTypeHintApplier.new
        tables = {}
        result = applier.apply(hint_set, tables)

        # All three tables should be present
        expect(result.keys).to include("fpgm", "prep", "cvt ")
        expect(result.size).to eq(3)

        # Each should have valid structure
        %w[fpgm prep].each do |tag|
          expect(result[tag][:tag]).to eq(tag)
          expect(result[tag][:data]).to be_a(String)
          expect(result[tag][:checksum]).to be_a(Integer)
        end

        expect(result["cvt "][:tag]).to eq("cvt ")
        expect(result["cvt "][:data]).to be_a(String)
        expect(result["cvt "][:checksum]).to be_a(Integer)
      end
    end

    context "with existing font tables" do
      let(:existing_tables) do
        {
          "head" => { tag: "head", data: "...", checksum: 12345 },
          "maxp" => { tag: "maxp", data: "...", checksum: 67890 },
          "glyf" => { tag: "glyf", data: "...", checksum: 11111 },
        }
      end

      it "preserves existing tables while adding hint tables" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.font_program = "\x00\x01"
        hint_set.control_values = [100, 200]

        applier = Fontisan::Hints::TrueTypeHintApplier.new
        result = applier.apply(hint_set, existing_tables)

        # Existing tables preserved
        expect(result["head"]).to eq(existing_tables["head"])
        expect(result["maxp"]).to eq(existing_tables["maxp"])
        expect(result["glyf"]).to eq(existing_tables["glyf"])

        # New hint tables added
        expect(result["fpgm"]).not_to be_nil
        expect(result["cvt "]).not_to be_nil

        # Total table count
        expect(result.size).to eq(5)
      end
    end

    context "checksum integrity" do
      it "produces valid checksums that survive padding" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)

        # Test various data lengths requiring different padding
        test_cases = [
          "\x01",           # 1 byte (3 bytes padding)
          "\x01\x02",       # 2 bytes (2 bytes padding)
          "\x01\x02\x03",   # 3 bytes (1 byte padding)
          "\x01\x02\x03\x04", # 4 bytes (no padding)
          "\x01\x02\x03\x04\x05", # 5 bytes (3 bytes padding)
        ]

        applier = Fontisan::Hints::TrueTypeHintApplier.new

        test_cases.each do |data|
          hint_set.font_program = data
          tables = {}
          result = applier.apply(hint_set, tables)

          checksum = result["fpgm"][:checksum]
          expect(checksum).to be_a(Integer)
          expect(checksum).to be >= 0
          expect(checksum).to be <= 0xFFFFFFFF
        end
      end

      it "produces consistent checksums for identical data" do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.font_program = "\xB0\x01\xB8\x02"

        applier = Fontisan::Hints::TrueTypeHintApplier.new

        # Apply multiple times
        results = Array.new(3) do
          tables = {}
          applier.apply(hint_set, tables)
        end

        # All checksums should match
        checksums = results.map { |r| r["fpgm"][:checksum] }
        expect(checksums.uniq.size).to eq(1)
      end
    end
  end

  describe "PostScript hint application" do
    context "with valid hint parameters" do
      let(:otf_font_path) do
        font_fixture_path("SourceSans3", "SourceSans3-Regular.otf")
      end
      let(:cff_table) do
        font = Fontisan::FontLoader.load(otf_font_path)
        font.table("CFF ")
      end

      it "validates hint parameters without corrupting CFF table" do
        hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        hint_set.private_dict_hints = {
          "std_hw" => 68,
          "std_vw" => 88,
          "blue_values" => [-20, 0, 706, 726],
        }.to_json

        applier = Fontisan::Hints::PostScriptHintApplier.new
        tables = { "CFF " => cff_table }
        result = applier.apply(hint_set, tables)

        # Result should be a Hash with CFF key
        expect(result).to be_a(Hash)
        expect(result).to have_key("CFF ")
      end

      it "safely handles complex hint parameters" do
        hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        hint_set.private_dict_hints = {
          "blue_values" => [-20, 0, 400, 420, 706, 726],
          "other_blues" => [-250, -230],
          "std_hw" => 68,
          "std_vw" => 88,
          "stem_snap_h" => [60, 68, 75, 80, 85, 90],
          "stem_snap_v" => [80, 88, 95, 100, 105, 110],
          "blue_scale" => 0.039,
          "blue_shift" => 7,
          "blue_fuzz" => 1,
          "force_bold" => false,
          "language_group" => 0,
        }.to_json

        applier = Fontisan::Hints::PostScriptHintApplier.new
        tables = { "CFF " => cff_table }

        # Should not raise error
        expect do
          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
        end.not_to raise_error
      end
    end

    context "validation mode safety" do
      let(:cff_table) { double("CFF Table") }

      it "returns tables unchanged for invalid parameters" do
        applier = Fontisan::Hints::PostScriptHintApplier.new
        tables = { "CFF " => cff_table }

        # Invalid: too many blue_values
        hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        hint_set.private_dict_hints = {
          "blue_values" => Array.new(16, 0), # Max is 14
        }.to_json

        result = applier.apply(hint_set, tables)
        expect(result["CFF "]).to eq(cff_table)
      end

      it "safely handles malformed JSON" do
        hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        hint_set.private_dict_hints = "{ invalid json"

        applier = Fontisan::Hints::PostScriptHintApplier.new
        tables = { "CFF " => cff_table }

        # Should not raise error, should return unchanged
        expect do
          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(cff_table)
        end.not_to raise_error
      end
    end
  end

  describe "Round-trip hint workflow" do
    context "TrueType font with hints" do
      # This test uses actual font if available
      it "extracts and re-applies hints maintaining integrity", :slow do
        font_path = font_fixture_path("NotoSans", "NotoSans-Regular.ttf")

        # Load font with hints
        font = Fontisan::FontLoader.load(font_path)

        # Extract hints
        extractor = Fontisan::Hints::TrueTypeHintExtractor.new
        hint_set = extractor.extract_from_font(font)

        # NotoSans TrueType font should have hints
        expect(hint_set.empty?).to be(false), "NotoSans TrueType font should contain hints"

        # Apply hints to new tables
        applier = Fontisan::Hints::TrueTypeHintApplier.new
        tables = {}
        result = applier.apply(hint_set, tables)

        # Verify hints were written
        if hint_set.font_program && !hint_set.font_program.empty?
          expect(result["fpgm"]).not_to be_nil
          expect(result["fpgm"][:data]).to eq(hint_set.font_program)
        end

        if hint_set.control_value_program && !hint_set.control_value_program.empty?
          expect(result["prep"]).not_to be_nil
          expect(result["prep"][:data]).to eq(hint_set.control_value_program)
        end

        if hint_set.control_values && !hint_set.control_values.empty?
          expect(result["cvt "]).not_to be_nil
          # Verify cvt values round-trip correctly (signed 16-bit)
          cvt_data = result["cvt "][:data]
          values = cvt_data.unpack("s>*")
          expect(values).to eq(hint_set.control_values)
        end
      end
    end
  end

  describe "Cross-format hint conversion workflow" do
    it "converts TrueType hints to semantic format" do
      # Create TrueType hint set
      tt_hint_set = Fontisan::Models::HintSet.new(format: :truetype)
      tt_hint_set.font_program = "\xB0\x01"
      tt_hint_set.control_values = [100, 200]

      # Convert to PostScript (semantic conversion)
      converter = Fontisan::Hints::HintConverter.new
      ps_hint_set = converter.convert_hint_set(tt_hint_set, :postscript)

      # PostScript hint set should be created
      expect(ps_hint_set).to be_a(Fontisan::Models::HintSet)
      expect(ps_hint_set.format).to eq("postscript")

      # Should have Private dict hints (semantic conversion)
      expect(ps_hint_set.private_dict_hints).not_to be_nil
      expect(ps_hint_set.private_dict_hints).not_to eq("{}")
    end

    it "converts PostScript hints to semantic format" do
      # Create PostScript hint set
      ps_hint_set = Fontisan::Models::HintSet.new(format: :postscript)
      ps_hint_set.private_dict_hints = {
        "std_hw" => 68,
        "std_vw" => 88,
        "blue_values" => [-20, 0, 706, 726],
      }.to_json

      # Convert to TrueType (semantic conversion)
      converter = Fontisan::Hints::HintConverter.new
      tt_hint_set = converter.convert_hint_set(ps_hint_set, :truetype)

      # TrueType hint set should be created
      expect(tt_hint_set).to be_a(Fontisan::Models::HintSet)
      expect(tt_hint_set.format).to eq("truetype")

      # Should have cvt values (from semantic conversion)
      expect(tt_hint_set.control_values).not_to be_nil
      expect(tt_hint_set.control_values).not_to be_empty
    end
  end

  describe "Error handling and safety" do
    it "handles nil hint set gracefully" do
      tt_applier = Fontisan::Hints::TrueTypeHintApplier.new
      ps_applier = Fontisan::Hints::PostScriptHintApplier.new

      tables = { "head" => { data: "..." } }

      # Should not raise errors
      expect { tt_applier.apply(nil, tables) }.not_to raise_error
      expect { ps_applier.apply(nil, tables) }.not_to raise_error

      # Should return original tables
      expect(tt_applier.apply(nil, tables)).to eq(tables)
      expect(ps_applier.apply(nil, tables)).to eq(tables)
    end

    it "handles empty tables gracefully" do
      hint_set = Fontisan::Models::HintSet.new(format: :truetype)
      hint_set.font_program = "\x00\x01"

      applier = Fontisan::Hints::TrueTypeHintApplier.new
      tables = {}

      # Should not raise error
      expect { applier.apply(hint_set, tables) }.not_to raise_error

      # Should add hint tables
      result = applier.apply(hint_set, tables)
      expect(result["fpgm"]).not_to be_nil
    end

    it "handles wrong format gracefully" do
      # TrueType hint set applied with PostScript applier
      tt_hint_set = Fontisan::Models::HintSet.new(format: :truetype)
      tt_hint_set.font_program = "\x00\x01"

      ps_applier = Fontisan::Hints::PostScriptHintApplier.new
      tables = { "CFF " => double("CFF Table") }

      expect { ps_applier.apply(tt_hint_set, tables) }.not_to raise_error
      expect(ps_applier.apply(tt_hint_set, tables)).to eq(tables)

      # PostScript hint set applied with TrueType applier
      ps_hint_set = Fontisan::Models::HintSet.new(format: :postscript)
      ps_hint_set.private_dict_hints = { "std_hw" => 68 }.to_json

      tt_applier = Fontisan::Hints::TrueTypeHintApplier.new
      tables = {}

      expect { tt_applier.apply(ps_hint_set, tables) }.not_to raise_error
      expect(tt_applier.apply(ps_hint_set, tables)).to eq(tables)
    end
  end
end
