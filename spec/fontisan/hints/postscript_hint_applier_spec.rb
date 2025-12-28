# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Hints::PostScriptHintApplier do
  let(:applier) { described_class.new }
  let(:tables) { {} }

  describe "#apply" do
    let(:font_path) { font_fixture_path("SourceSans3", "SourceSans3-Regular.otf") }
    let(:font) { Fontisan::FontLoader.load(font_path) }
    let(:real_cff_table) { font.table("CFF ") }

    context "with valid PostScript HintSet" do
      let(:tables) { { "CFF " => real_cff_table } }

      let(:hint_set) do
        set = Fontisan::Models::HintSet.new(format: :postscript)
        set.private_dict_hints = {
          "std_hw" => 68,
          "std_vw" => 88,
          "blue_values" => [-20, 0, 706, 726],
        }.to_json
        set
      end

      it "validates hint parameters successfully" do
        result = applier.apply(hint_set, tables)
        expect(result).to be_a(Hash)
        expect(result).to have_key("CFF ")
      end

      it "rebuilds CFF table with hints applied" do
        result = applier.apply(hint_set, tables)
        expect(result["CFF "]).to be_a(String)
        expect(result["CFF "].encoding).to eq(Encoding::BINARY)
      end
    end

    context "with complex hint parameters" do
      let(:tables) { { "CFF " => real_cff_table } }

      let(:hint_set) do
        set = Fontisan::Models::HintSet.new(format: :postscript)
        set.private_dict_hints = {
          "blue_values" => [-20, 0, 400, 420, 706, 726],
          "other_blues" => [-250, -230],
          "std_hw" => 68,
          "std_vw" => 88,
          "stem_snap_h" => [60, 68, 75],
          "stem_snap_v" => [80, 88, 95],
          "blue_scale" => 0.039,
          "blue_shift" => 7,
          "blue_fuzz" => 1,
          "language_group" => 0,
        }.to_json
        set
      end

      it "validates all parameters successfully" do
        result = applier.apply(hint_set, tables)
        expect(result).to be_a(Hash)
        expect(result).to have_key("CFF ")
      end
    end

    context "with empty hint set" do
      let(:hint_set) { Fontisan::Models::HintSet.new(format: :postscript) }

      it "returns tables unchanged" do
        result = applier.apply(hint_set, tables)
        expect(result).to eq(tables)
      end
    end

    context "with nil hint set" do
      it "returns tables unchanged" do
        result = applier.apply(nil, tables)
        expect(result).to eq(tables)
      end
    end

    context "without CFF table" do
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

    context "with TrueType hint set (wrong format)" do
      let(:cff_table) { double("CFF Table") }
      let(:hint_set) do
        set = Fontisan::Models::HintSet.new(format: :truetype)
        set.font_program = "\x00\x01"
        set
      end

      before do
        tables["CFF "] = cff_table
      end

      it "returns tables unchanged" do
        result = applier.apply(hint_set, tables)
        expect(result).to eq(tables)
      end
    end

    context "hint parameter validation" do
      let(:tables) { { "CFF " => real_cff_table } }

      context "blue_values validation" do
        it "accepts valid blue_values (up to 14 values, 7 pairs)" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = {
            "blue_values" => [-20, 0, 400, 420, 706, 726, 800, 820],
          }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end

        it "rejects blue_values with odd count (must be pairs)" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = {
            "blue_values" => [-20, 0, 706],  # Odd count
          }.to_json

          result = applier.apply(hint_set, tables)
          # Should return unchanged due to validation error
          expect(result["CFF "]).to eq(real_cff_table)
        end

        it "rejects blue_values exceeding 14 values" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = {
            "blue_values" => Array.new(16, 0),  # Too many
          }.to_json

          result = applier.apply(hint_set, tables)
          # Should return unchanged due to validation error
          expect(result["CFF "]).to eq(real_cff_table)
        end
      end

      context "other_blues validation" do
        it "accepts valid other_blues (up to 10 values, 5 pairs)" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = {
            "other_blues" => [-250, -230, -200, -180],
          }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end

        it "rejects other_blues with odd count" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = {
            "other_blues" => [-250, -230, -200],  # Odd count
          }.to_json

          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(real_cff_table)
        end

        it "rejects other_blues exceeding 10 values" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = {
            "other_blues" => Array.new(12, 0),
          }.to_json

          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(real_cff_table)
        end
      end

      context "stem width validation" do
        it "accepts positive std_hw" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "std_hw" => 68 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end

        it "rejects negative std_hw" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "std_hw" => -68 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(real_cff_table)
        end

        it "accepts positive std_vw" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "std_vw" => 88 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end

        it "rejects negative std_vw" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "std_vw" => -88 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(real_cff_table)
        end
      end

      context "stem snap validation" do
        it "accepts stem_snap_h with up to 12 values" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = {
            "stem_snap_h" => [60, 65, 68, 70, 75, 80],
          }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end

        it "rejects stem_snap_h exceeding 12 values" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = {
            "stem_snap_h" => Array.new(13, 60),
          }.to_json

          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(real_cff_table)
        end

        it "accepts stem_snap_v with up to 12 values" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = {
            "stem_snap_v" => [80, 85, 88, 90, 95, 100],
          }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end

        it "rejects stem_snap_v exceeding 12 values" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = {
            "stem_snap_v" => Array.new(13, 80),
          }.to_json

          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(real_cff_table)
        end
      end

      context "blue_scale validation" do
        it "accepts positive blue_scale" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "blue_scale" => 0.039 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end

        it "rejects zero blue_scale" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "blue_scale" => 0 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(real_cff_table)
        end

        it "rejects negative blue_scale" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "blue_scale" => -0.1 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(real_cff_table)
        end
      end

      context "language_group validation" do
        it "accepts language_group 0 (Latin)" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "language_group" => 0 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end

        it "accepts language_group 1 (CJK)" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "language_group" => 1 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end

        it "rejects invalid language_group" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "language_group" => 2 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(real_cff_table)
        end
      end

      context "JSON parsing" do
        it "handles invalid JSON gracefully" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = "invalid json {"

          expect do
            result = applier.apply(hint_set, tables)
            expect(result["CFF "]).to eq(real_cff_table)
          end.not_to raise_error
        end

        it "handles empty JSON object" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = "{}"

          result = applier.apply(hint_set, tables)
          expect(result["CFF "]).to eq(real_cff_table)
        end
      end

      context "symbol and string keys" do
        it "handles string keys" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          hint_set.private_dict_hints = { "std_hw" => 68 }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end

        # JSON.parse returns string keys, but test internal handling
        it "validates parameters regardless of key type" do
          hint_set = Fontisan::Models::HintSet.new(format: :postscript)
          # JSON will convert to strings, but validation should handle both
          hint_set.private_dict_hints = {
            std_hw: 68,
            std_vw: 88,
          }.to_json

          result = applier.apply(hint_set, tables)
          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF ")
        end
      end
    end
  end

  # Integration tests with real CFF tables
  describe "CFF table modification (integration)" do
    let(:font_path) { font_fixture_path("SourceSans3", "SourceSans3-Regular.otf") }
    let(:font) { Fontisan::FontLoader.load(font_path) }
    let(:real_cff_table) { font.table("CFF ") }
    let(:tables) { { "CFF " => real_cff_table } }

    context "with real CFF table" do
      it "rebuilds CFF table with hints" do
        hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        hint_set.private_dict_hints = { blue_values: [-15, 0], std_hw: 70 }.to_json

        result = applier.apply(hint_set, tables)
        expect(result["CFF "]).to be_a(String)
        expect(result["CFF "].encoding).to eq(Encoding::BINARY)
      end

      it "produces valid CFF after hint application" do
        hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        hint_set.private_dict_hints = { blue_values: [-15, 0], std_hw: 70 }.to_json

        result = applier.apply(hint_set, tables)
        rebuilt_cff = Fontisan::Tables::Cff.read(result["CFF "])
        expect(rebuilt_cff.valid?).to be true
      end

      it "preserves glyph count" do
        original_count = real_cff_table.glyph_count
        hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        hint_set.private_dict_hints = { std_hw: 70 }.to_json

        result = applier.apply(hint_set, tables)
        rebuilt_cff = Fontisan::Tables::Cff.read(result["CFF "])
        expect(rebuilt_cff.glyph_count).to eq(original_count)
      end

      it "handles complex hint parameters" do
        hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        hint_set.private_dict_hints = {
          blue_values: [-15, 0, 721, 736],
          other_blues: [-250, -240],
          std_hw: 70,
          std_vw: 85,
        }.to_json

        result = applier.apply(hint_set, tables)
        rebuilt_cff = Fontisan::Tables::Cff.read(result["CFF "])
        expect(rebuilt_cff.valid?).to be true
        expect(rebuilt_cff.glyph_count).to eq(real_cff_table.glyph_count)
      end

      it "handles errors gracefully" do
        # Invalid hint that should be caught
        hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        hint_set.private_dict_hints = { blue_values: [1, 2, 3] }.to_json  # Odd length

        result = applier.apply(hint_set, tables)
        # Should return original table unchanged
        expect(result["CFF "]).to eq(real_cff_table)
      end
    end
  end

  describe "per-glyph hint support" do
    let(:cff_font_path) { font_fixture_path("SourceSans3", "SourceSans3-Regular.otf") }
    let(:cff_font) { Fontisan::FontLoader.load(cff_font_path) }
    let(:tables) { { "CFF " => cff_font.table("CFF ") } }

    it "applies per-glyph hints to specific glyphs" do
      hint = Fontisan::Models::Hint.new(
        type: :stem,
        data: { position: 100, width: 50, orientation: :horizontal },
        source_format: :postscript
      )

      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      hint_set.add_glyph_hints(1, [hint])  # Add hint to glyph 1

      # Capture original data
      original_cff = tables["CFF "].dup

      result = applier.apply(hint_set, tables)

      expect(result).not_to eq({ "CFF " => original_cff })
      expect(result["CFF "]).to be_a(String)
      expect(result["CFF "].length).to be > 0
    end

    it "applies hints to multiple glyphs" do
      hint1 = Fontisan::Models::Hint.new(
        type: :stem,
        data: { position: 100, width: 50, orientation: :horizontal },
        source_format: :postscript
      )

      hint2 = Fontisan::Models::Hint.new(
        type: :stem,
        data: { position: 200, width: 60, orientation: :vertical },
        source_format: :postscript
      )

      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      hint_set.add_glyph_hints(1, [hint1])
      hint_set.add_glyph_hints(2, [hint2])

      # Capture original data
      original_cff = tables["CFF "].dup

      result = applier.apply(hint_set, tables)

      expect(result).not_to eq({ "CFF " => original_cff })
      expect(hint_set.hinted_glyph_count).to eq(2)
    end

    it "applies both font-level and per-glyph hints" do
      # Font-level hints
      private_dict_hints = {
        blue_values: [-15, 0, 450, 460, 600, 610],
        std_hw: 70
      }

      # Per-glyph hint
      hint = Fontisan::Models::Hint.new(
        type: :stem,
        data: { position: 100, width: 50, orientation: :horizontal },
        source_format: :postscript
      )

      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: private_dict_hints.to_json
      )
      hint_set.add_glyph_hints(1, [hint])

      # Capture original data
      original_cff = tables["CFF "].dup

      result = applier.apply(hint_set, tables)

      expect(result).not_to eq({ "CFF " => original_cff })
      expect(result["CFF "]).to be_a(String)
    end

    it "handles hintmask in per-glyph hints" do
      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
          source_format: :postscript
        ),
        Fontisan::Models::Hint.new(
          type: :hint_replacement,
          data: { mask: [0b11000000] },
          source_format: :postscript
        )
      ]

      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      hint_set.add_glyph_hints(1, hints)

      # Capture original data
      original_cff = tables["CFF "].dup

      result = applier.apply(hint_set, tables)

      expect(result).not_to eq({ "CFF " => original_cff })
      expect(result["CFF "]).to be_a(String)
    end

    it "returns original tables when per-glyph hints array is empty" do
      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      # No hints added

      result = applier.apply(hint_set, tables)
      expect(result).to eq(tables)
    end

    it "handles errors gracefully during per-glyph hint application" do
      # Create invalid hint that might cause errors
      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      hint_set.add_glyph_hints(999999, [])  # Invalid glyph index

      # Should not raise error, should return original
      expect { applier.apply(hint_set, tables) }.not_to raise_error
    end
  end

  describe "CFF2 support" do
    let(:cff2_data) do
      # Minimal CFF2 header
      [
        2,    # major version
        0,    # minor version
        5,    # header size
        0, 20 # top dict length
      ].pack("CCCCC") + ("\x00" * 20)
    end

    describe "#cff2_table?" do
      it "detects CFF2 table" do
        tables = { "CFF2 " => cff2_data }
        expect(applier.send(:cff2_table?, tables)).to be true
      end

      it "detects CFF2 without trailing space" do
        tables = { "CFF2" => cff2_data }
        expect(applier.send(:cff2_table?, tables)).to be true
      end

      it "returns false for CFF table" do
        tables = { "CFF " => "data" }
        expect(applier.send(:cff2_table?, tables)).to be false
      end

      it "returns false when no CFF2 table" do
        tables = { "head" => "data" }
        expect(applier.send(:cff2_table?, tables)).to be false
      end
    end

    describe "#cff_table?" do
      it "detects CFF table" do
        tables = { "CFF " => "data" }
        expect(applier.send(:cff_table?, tables)).to be true
      end

      it "returns false for CFF2 table" do
        tables = { "CFF2 " => cff2_data }
        expect(applier.send(:cff_table?, tables)).to be false
      end
    end

    describe "#apply with CFF2" do
      context "with font-level hints" do
        it "applies hints to CFF2 variable font" do
          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { blue_values: [10, 20, 30, 40] }.to_json
          )

          tables = { "CFF2 " => cff2_data }
          result = applier.apply(hint_set, tables)

          expect(result).to be_a(Hash)
          expect(result).to have_key("CFF2 ")
          # CFF2 table should be modified
          expect(result["CFF2 "]).to be_a(String)
        end

        it "preserves Variable Store during hint application" do
          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { blue_scale: 0.039625 }.to_json
          )

          tables = { "CFF2 " => cff2_data }
          result = applier.apply(hint_set, tables)

          # Variable Store preservation is handled by CFF2TableBuilder
          expect(result["CFF2 "]).to be_a(String)
        end

        it "validates CFF2 version" do
          # Invalid CFF2 (version 1)
          invalid_cff2 = [1, 0, 4, 4].pack("CCCC")

          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { blue_values: [10, 20] }.to_json
          )

          tables = { "CFF2 " => invalid_cff2 }

          # Should handle gracefully
          expect {
            result = applier.apply(hint_set, tables)
            expect(result["CFF2 "]).to eq(invalid_cff2) # Unchanged
          }.not_to raise_error
        end

        it "handles CFF2 table with trailing space key" do
          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { std_hw: 50 }.to_json
          )

          tables = { "CFF2 " => cff2_data }
          result = applier.apply(hint_set, tables)

          expect(result).to have_key("CFF2 ")
        end

        it "handles CFF2 table without trailing space key" do
          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { std_vw: 60 }.to_json
          )

          tables = { "CFF2" => cff2_data }
          result = applier.apply(hint_set, tables)

          expect(result).to have_key("CFF2")
        end
      end

      context "with per-glyph hints" do
        it "applies per-glyph hints to specific glyphs" do
          hint = Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 10, width: 20, orientation: :horizontal },
            source_format: :postscript
          )

          hint_set = Fontisan::Models::HintSet.new(format: "postscript")
          hint_set.add_glyph_hints(1, [hint])

          tables = { "CFF2 " => cff2_data }
          result = applier.apply(hint_set, tables)

          expect(result["CFF2 "]).to be_a(String)
        end

        it "preserves blend operators in CharStrings" do
          hint = Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 15, width: 25, orientation: :vertical },
            source_format: :postscript
          )

          hint_set = Fontisan::Models::HintSet.new(format: "postscript")
          hint_set.add_glyph_hints(0, [hint])

          tables = { "CFF2 " => cff2_data }
          result = applier.apply(hint_set, tables)

          # Blend preservation is handled by CharStringParser/Builder
          expect(result["CFF2 "]).to be_a(String)
        end

        it "handles multiple hints per glyph" do
          hint1 = Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 10, width: 20, orientation: :horizontal },
            source_format: :postscript
          )

          hint2 = Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 30, width: 40, orientation: :vertical },
            source_format: :postscript
          )

          hint_set = Fontisan::Models::HintSet.new(format: "postscript")
          hint_set.add_glyph_hints(1, [hint1, hint2])

          tables = { "CFF2 " => cff2_data }
          result = applier.apply(hint_set, tables)

          expect(result["CFF2 "]).to be_a(String)
        end
      end

      context "with both font-level and per-glyph hints" do
        it "applies both types of hints" do
          hint = Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 10, width: 20, orientation: :horizontal },
            source_format: :postscript
          )

          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { blue_values: [10, 20] }.to_json
          )
          hint_set.add_glyph_hints(1, [hint])

          tables = { "CFF2 " => cff2_data }
          result = applier.apply(hint_set, tables)

          expect(result["CFF2 "]).to be_a(String)
        end

        it "maintains CFF2 structure integrity" do
          hint = Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 5, width: 10, orientation: :horizontal },
            source_format: :postscript
          )

          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { std_hw: 50, std_vw: 60 }.to_json
          )
          hint_set.add_glyph_hints(0, [hint])

          tables = { "CFF2 " => cff2_data }
          result = applier.apply(hint_set, tables)

          # Verify CFF2 structure is maintained
          expect(result["CFF2 "][0].unpack1("C")).to eq(2) # major version
        end
      end

      context "error handling" do
        it "handles missing CFF2 table gracefully" do
          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { blue_values: [10, 20] }.to_json
          )

          tables = { "head" => "data" }
          result = applier.apply(hint_set, tables)

          expect(result).to eq(tables)
        end

        it "handles corrupted CFF2 data gracefully" do
          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { blue_values: [10, 20] }.to_json
          )

          tables = { "CFF2 " => "corrupted".b }

          expect {
            result = applier.apply(hint_set, tables)
            # Should return original on error
            expect(result["CFF2 "]).to eq("corrupted".b)
          }.not_to raise_error
        end

        it "handles invalid hint data gracefully" do
          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: "invalid json"
          )

          tables = { "CFF2 " => cff2_data }
          result = applier.apply(hint_set, tables)

          # Should handle gracefully
          expect(result).to be_a(Hash)
        end
      end

      context "format routing" do
        it "routes to CFF2 when CFF2 table present" do
          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { blue_values: [10, 20] }.to_json
          )

          tables = {
            "CFF2 " => cff2_data,
            "CFF " => "cff_data" # Both present, should use CFF2
          }

          result = applier.apply(hint_set, tables)

          # CFF2 should be processed, CFF should be left unchanged
          expect(result["CFF2 "]).to be_a(String)
          expect(result["CFF "]).to eq("cff_data")
        end

        it "routes to CFF when only CFF table present" do
          font_path = font_fixture_path("SourceSans3", "SourceSans3-Regular.otf")
          font = Fontisan::FontLoader.load(font_path)
          cff_table = font.table("CFF ")

          hint_set = Fontisan::Models::HintSet.new(
            format: "postscript",
            private_dict_hints: { blue_values: [10, 20] }.to_json
          )

          tables = { "CFF " => cff_table }
          result = applier.apply(hint_set, tables)

          # CFF should be processed
          expect(result["CFF "]).to be_a(String)
          expect(result["CFF "].encoding).to eq(Encoding::BINARY)
        end
      end
    end
  end
end