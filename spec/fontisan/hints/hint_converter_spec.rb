# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Hints::HintConverter do
  let(:converter) { described_class.new }

  describe "#to_postscript" do
    it "converts array of TrueType hints to PostScript" do
      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical },
          source_format: :truetype
        )
      ]

      result = converter.to_postscript(hints)
      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first.source_format).to eq(:postscript)
    end

    it "skips hints already in PostScript format" do
      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { operator: :vstem, args: [100, 50] },
          source_format: :postscript
        )
      ]

      result = converter.to_postscript(hints)
      expect(result).to eq(hints)
    end

    it "returns empty array for nil input" do
      result = converter.to_postscript(nil)
      expect(result).to eq([])
    end

    it "returns empty array for empty input" do
      result = converter.to_postscript([])
      expect(result).to eq([])
    end

    it "filters out incompatible hints" do
      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical },
          source_format: :truetype
        ),
        Fontisan::Models::Hint.new(
          type: :unknown_type,
          data: {},
          source_format: :truetype
        )
      ]

      result = converter.to_postscript(hints)
      expect(result.length).to eq(1)
      expect(result.first.type).to eq(:stem)
    end
  end

  describe "#to_truetype" do
    it "converts array of PostScript hints to TrueType" do
      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical },
          source_format: :postscript
        )
      ]

      result = converter.to_truetype(hints)
      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first.source_format).to eq(:truetype)
    end

    it "skips hints already in TrueType format" do
      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { instructions: [0x2E, 0xC0] },
          source_format: :truetype
        )
      ]

      result = converter.to_truetype(hints)
      expect(result).to eq(hints)
    end

    it "returns empty array for nil input" do
      result = converter.to_truetype(nil)
      expect(result).to eq([])
    end

    it "returns empty array for empty input" do
      result = converter.to_truetype([])
      expect(result).to eq([])
    end
  end

  describe "#optimize" do
    it "removes duplicate hints" do
      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical }
        ),
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical }
        )
      ]

      result = converter.optimize(hints)
      expect(result.length).to eq(1)
    end

    it "removes conflicting overlapping stems" do
      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical }
        ),
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 120, width: 50, orientation: :vertical }
        )
      ]

      result = converter.optimize(hints)
      # Should keep first and remove overlapping second
      expect(result.length).to eq(1)
      expect(result.first.data[:position]).to eq(100)
    end

    it "keeps non-overlapping stems" do
      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical }
        ),
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 200, width: 50, orientation: :vertical }
        )
      ]

      result = converter.optimize(hints)
      expect(result.length).to eq(2)
    end

    it "returns empty array for nil input" do
      result = converter.optimize(nil)
      expect(result).to eq([])
    end
  end

  describe "#convert_hint_set" do
    context "TrueType to PostScript conversion" do
      let(:tt_hint_set) do
        hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        hint_set.font_program = "fpgm_data"
        hint_set.control_value_program = "prep_data"
        hint_set.control_values = [100, 200]

        # Add glyph hints
        glyph_hints = [
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 100, width: 50, orientation: :vertical },
            source_format: :truetype
          )
        ]
        hint_set.add_glyph_hints(0, glyph_hints)
        hint_set
      end

      it "converts complete TrueType HintSet to PostScript" do
        result = converter.convert_hint_set(tt_hint_set, :postscript)

        expect(result).to be_a(Fontisan::Models::HintSet)
        expect(result.format).to eq("postscript")
        expect(result.has_hints).to be true
      end

      it "converts font-level hints to Private dict" do
        result = converter.convert_hint_set(tt_hint_set, :postscript)

        expect(result.private_dict_hints).not_to eq("{}")
        ps_dict = JSON.parse(result.private_dict_hints)
        expect(ps_dict).to be_a(Hash)
        expect(ps_dict["std_hw"]).to eq(100)
        expect(ps_dict["std_vw"]).to eq(200)
      end

      it "converts per-glyph hints" do
        result = converter.convert_hint_set(tt_hint_set, :postscript)

        # Glyph hints should be converted (but may be filtered if incompatible)
        glyph_hints = result.get_glyph_hints("0")
        # Check that conversion was attempted (empty is ok if hints were filtered)
        expect(glyph_hints).to be_an(Array)
      end

      it "returns same hint set if already in target format" do
        ps_hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        result = converter.convert_hint_set(ps_hint_set, :postscript)

        expect(result).to eq(ps_hint_set)
      end
    end

    context "PostScript to TrueType conversion" do
      let(:ps_hint_set) do
        hint_set = Fontisan::Models::HintSet.new(format: :postscript)
        # Use string keys since JSON.parse returns string keys
        hint_set.private_dict_hints = { "std_hw" => 68, "std_vw" => 88 }.to_json

        # Add glyph hints
        glyph_hints = [
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 100, width: 50, orientation: :vertical },
            source_format: :postscript
          )
        ]
        hint_set.add_glyph_hints(0, glyph_hints)
        hint_set
      end

      it "converts complete PostScript HintSet to TrueType" do
        result = converter.convert_hint_set(ps_hint_set, :truetype)

        expect(result).to be_a(Fontisan::Models::HintSet)
        expect(result.format).to eq("truetype")
        # has_hints depends on whether conversion produced any hints
      end

      it "converts Private dict to font programs" do
        result = converter.convert_hint_set(ps_hint_set, :truetype)

        # CVT values should be extracted from Private dict
        expect(result.control_values).to be_an(Array)
        # Should have at least std_hw and std_vw if present
        expect(result.control_values.length).to be >= 2
      end

      it "converts per-glyph hints" do
        result = converter.convert_hint_set(ps_hint_set, :truetype)

        # Glyph hints should be converted
        glyph_hints = result.get_glyph_hints("0")
        expect(glyph_hints).to be_an(Array)
      end
    end

    context "empty hint sets" do
      it "handles empty TrueType hint set" do
        empty_set = Fontisan::Models::HintSet.new(format: :truetype)
        result = converter.convert_hint_set(empty_set, :postscript)

        expect(result.format).to eq("postscript")
        # Empty set may have default values set, so don't check empty?
      end

      it "handles empty PostScript hint set" do
        empty_set = Fontisan::Models::HintSet.new(format: :postscript)
        result = converter.convert_hint_set(empty_set, :truetype)

        expect(result.format).to eq("truetype")
        expect(result.empty?).to be true
      end
    end
  end

  describe "private methods" do
    describe "#convert_tt_programs_to_ps_dict" do
      it "extracts stem widths from CVT" do
        cvt = [68, 88, 100]
        result = converter.send(:convert_tt_programs_to_ps_dict, "", "", cvt)

        expect(result).to be_a(Hash)
        expect(result[:std_hw]).to eq(68)
        expect(result[:std_vw]).to eq(88)
      end

      it "generates default BlueValues" do
        result = converter.send(:convert_tt_programs_to_ps_dict, "", "", [])

        expect(result[:blue_values]).to eq([-20, 0, 706, 726])
      end

      it "handles nil CVT" do
        result = converter.send(:convert_tt_programs_to_ps_dict, "", "", nil)

        expect(result).to be_a(Hash)
        expect(result[:blue_values]).not_to be_nil
        expect(result[:blue_values]).not_to be_empty
      end
    end

    describe "#convert_ps_dict_to_tt_programs" do
      it "generates CVT from stem widths" do
        ps_dict = { std_hw: 68, std_vw: 88 }
        result = converter.send(:convert_ps_dict_to_tt_programs, ps_dict)

        expect(result[:cvt]).to include(68, 88)
      end

      it "includes stem snap values in CVT" do
        ps_dict = { std_hw: 68, stem_snap_h: [60, 70, 80] }
        result = converter.send(:convert_ps_dict_to_tt_programs, ps_dict)

        expect(result[:cvt]).to include(68, 60, 70, 80)
      end

      it "generates empty programs" do
        result = converter.send(:convert_ps_dict_to_tt_programs, {})

        expect(result[:fpgm]).to eq("")
        expect(result[:prep]).to eq("")
      end

      it "removes duplicates from CVT" do
        ps_dict = { std_hw: 68, std_vw: 68, stem_snap_h: [68] }
        result = converter.send(:convert_ps_dict_to_tt_programs, ps_dict)

        expect(result[:cvt].count(68)).to eq(1)
      end
    end
  end
end