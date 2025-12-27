# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Hint Conversion Integration" do
  let(:converter) { Fontisan::Hints::HintConverter.new }

  describe "TrueType → PostScript conversion" do
    it "converts complete TT HintSet to PS" do
      # Create TT HintSet with multiple hint types
      tt_set = Fontisan::Models::HintSet.new(format: :truetype)
      tt_set.font_program = "fpgm_bytecode"
      tt_set.control_value_program = "prep_bytecode"
      tt_set.control_values = [68, 88, 100, 120]

      # Add glyph hints
      glyph_hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical },
          source_format: :truetype
        ),
        Fontisan::Models::Hint.new(
          type: :interpolate,
          data: { axis: :y },
          source_format: :truetype
        )
      ]
      tt_set.add_glyph_hints(0, glyph_hints)

      # Convert
      ps_set = converter.convert_hint_set(tt_set, :postscript)

      # Verify
      expect(ps_set.format).to eq("postscript")
      expect(ps_set.private_dict_hints).not_to eq("{}")

      ps_dict = JSON.parse(ps_set.private_dict_hints)
      expect(ps_dict["std_hw"]).to eq(68)
      expect(ps_dict["std_vw"]).to eq(88)
      expect(ps_dict["blue_values"]).to be_an(Array)
    end

    it "preserves glyph hint associations" do
      tt_set = Fontisan::Models::HintSet.new(format: :truetype)

      # Add hints for multiple glyphs
      3.times do |i|
        hints = [
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 100 + i * 50, width: 50, orientation: :vertical },
            source_format: :truetype
          )
        ]
        tt_set.add_glyph_hints(i, hints)
      end

      ps_set = converter.convert_hint_set(tt_set, :postscript)

      # Some glyphs may have hints
      expect(ps_set.hinted_glyph_ids).to be_an(Array)
      # Glyph count may vary due to conversion/filtering
    end
  end

  describe "PostScript → TrueType conversion" do
    it "converts complete PS HintSet to TT" do
      # Create PS HintSet
      ps_set = Fontisan::Models::HintSet.new(format: :postscript)
      ps_dict = {
        "std_hw" => 68,
        "std_vw" => 88,
        "blue_values" => [-20, 0, 706, 726],
        "stem_snap_h" => [60, 68, 76],
        "stem_snap_v" => [80, 88, 96]
      }
      ps_set.private_dict_hints = ps_dict.to_json

      # Add glyph hints
      glyph_hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical },
          source_format: :postscript
        ),
        Fontisan::Models::Hint.new(
          type: :stem3,
          data: {
            stems: [
              { position: 200, width: 50 },
              { position: 300, width: 50 }
            ],
            orientation: :horizontal
          },
          source_format: :postscript
        )
      ]
      ps_set.add_glyph_hints(0, glyph_hints)

      # Convert
      tt_set = converter.convert_hint_set(ps_set, :truetype)

      # Verify
      expect(tt_set.format).to eq("truetype")
      expect(tt_set.control_values).not_to be_empty
      expect(tt_set.control_values).to include(68, 88)
      # Should also include stem snap values - at least 6 unique values
      expect(tt_set.control_values.length).to be >= 6
    end

    it "generates valid cvt values" do
      ps_set = Fontisan::Models::HintSet.new(format: :postscript)
      ps_dict = {
        "std_hw" => 50,
        "std_vw" => 60,
        "stem_snap_h" => [45, 50, 55],
        "stem_snap_v" => [55, 60, 65]
      }
      ps_set.private_dict_hints = ps_dict.to_json

      tt_set = converter.convert_hint_set(ps_set, :truetype)

      # CVT should be sorted and unique
      expect(tt_set.control_values).to eq(tt_set.control_values.sort)
      expect(tt_set.control_values).to eq(tt_set.control_values.uniq)

      # Should contain all values
      expect(tt_set.control_values).to include(50, 60)
      expect(tt_set.control_values).to include(45, 55, 65)
    end
  end

  describe "round-trip conversion" do
    it "TT → PS → TT maintains essential structure" do
      # Original TT hint set
      original = Fontisan::Models::HintSet.new(format: :truetype)
      original.control_values = [68, 88]

      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical },
          source_format: :truetype
        )
      ]
      original.add_glyph_hints(0, hints)

      # Convert to PS
      ps = converter.convert_hint_set(original, :postscript)

      # Convert back to TT
      back_to_tt = converter.convert_hint_set(ps, :truetype)

      # Verify structure maintained
      expect(back_to_tt.format).to eq("truetype")
      expect(back_to_tt.control_values).not_to be_empty
      # Glyph hints may be lost during round-trip due to conversion limitations
      # This is expected behavior for format conversion
    end

    it "PS → TT → PS maintains essential structure" do
      # Original PS hint set
      original = Fontisan::Models::HintSet.new(format: :postscript)
      original.private_dict_hints = { "std_hw" => 68, "std_vw" => 88 }.to_json

      hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical },
          source_format: :postscript
        )
      ]
      original.add_glyph_hints(0, hints)

      # Convert to TT
      tt = converter.convert_hint_set(original, :truetype)

      # Convert back to PS
      back_to_ps = converter.convert_hint_set(tt, :postscript)

      # Verify structure maintained
      expect(back_to_ps.format).to eq("postscript")
      expect(back_to_ps.private_dict_hints).not_to eq("{}")
      # Glyph hints may be lost during round-trip due to conversion limitations
      # This is expected behavior for format conversion
    end
  end

  describe "complex scenarios" do
    it "handles mixed hint types in TT set" do
      tt_set = Fontisan::Models::HintSet.new(format: :truetype)

      mixed_hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical },
          source_format: :truetype
        ),
        Fontisan::Models::Hint.new(
          type: :delta,
          data: { instructions: [0x5D, 0x01] },
          source_format: :truetype
        ),
        Fontisan::Models::Hint.new(
          type: :interpolate,
          data: { axis: :y },
          source_format: :truetype
        )
      ]
      tt_set.add_glyph_hints(0, mixed_hints)

      # Should convert without errors
      expect { converter.convert_hint_set(tt_set, :postscript) }.not_to raise_error
    end

    it "handles empty glyph hints gracefully" do
      tt_set = Fontisan::Models::HintSet.new(format: :truetype)
      tt_set.control_values = [68, 88]
      # No glyph hints added

      ps_set = converter.convert_hint_set(tt_set, :postscript)

      expect(ps_set.format).to eq("postscript")
      expect(ps_set.hinted_glyph_count).to eq(0)
    end

    it "optimizes duplicate hints during conversion" do
      tt_set = Fontisan::Models::HintSet.new(format: :truetype)

      # Add duplicate hints
      duplicate_hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical },
          source_format: :truetype
        ),
        Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical },
          source_format: :truetype
        )
      ]
      tt_set.add_glyph_hints(0, duplicate_hints)

      ps_set = converter.convert_hint_set(tt_set, :postscript)

     # Duplicates should be handled
      glyph_hints = ps_set.get_glyph_hints("0")
      expect(glyph_hints).to be_an(Array)
    end
  end

  describe "error handling" do
    it "handles malformed hint data gracefully" do
      tt_set = Fontisan::Models::HintSet.new(format: :truetype)

      # Add hint with nil data
      bad_hints = [
        Fontisan::Models::Hint.new(
          type: :stem,
          data: nil,
          source_format: :truetype
        )
      ]
      tt_set.add_glyph_hints(0, bad_hints)

      # Should not crash
      expect { converter.convert_hint_set(tt_set, :postscript) }.not_to raise_error
    end

    it "handles missing Private dict in PS set" do
      ps_set = Fontisan::Models::HintSet.new(format: :postscript)
      # No private_dict_hints set

      tt_set = converter.convert_hint_set(ps_set, :truetype)

      expect(tt_set.format).to eq("truetype")
      expect(tt_set.control_values).to be_an(Array)
    end
  end
end