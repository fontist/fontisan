# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff/table_builder"

RSpec.describe Fontisan::Tables::Cff::TableBuilder do
  let(:font_path) { font_fixture_path("SourceSans3", "SourceSans3-Regular.otf") }
  let(:font) { Fontisan::FontLoader.load(font_path) }
  let(:source_cff) { font.table("CFF ") }

  describe ".rebuild" do
    context "without modifications" do
      it "rebuilds CFF table" do
        result = described_class.rebuild(source_cff)
        expect(result).to be_a(String)
        expect(result.encoding).to eq(Encoding::BINARY)
      end

      it "produces valid CFF structure" do
        result = described_class.rebuild(source_cff)
        rebuilt = Fontisan::Tables::Cff.read(result)
        expect(rebuilt.valid?).to be true
      end

      it "preserves glyph count" do
        result = described_class.rebuild(source_cff)
        rebuilt = Fontisan::Tables::Cff.read(result)
        expect(rebuilt.glyph_count).to eq(source_cff.glyph_count)
      end

      it "preserves font name" do
        result = described_class.rebuild(source_cff)
        rebuilt = Fontisan::Tables::Cff.read(result)
        expect(rebuilt.font_name).to eq(source_cff.font_name)
      end

      it "produces non-empty output" do
        result = described_class.rebuild(source_cff)
        expect(result.bytesize).to be > 1000
      end
    end

    context "with hint modifications" do
      let(:hint_mods) do
        {
          private_dict_hints: {
            blue_values: [-15, 0, 721, 736],
            std_hw: 70,
          },
        }
      end

      it "rebuilds with hints" do
        result = described_class.rebuild(source_cff, hint_mods)
        expect(result).to be_a(String)
        expect(result.bytesize).to be > 0
      end

      it "produces valid CFF" do
        result = described_class.rebuild(source_cff, hint_mods)
        rebuilt = Fontisan::Tables::Cff.read(result)
        expect(rebuilt.valid?).to be true
      end

      it "preserves glyph count with hints" do
        result = described_class.rebuild(source_cff, hint_mods)
        rebuilt = Fontisan::Tables::Cff.read(result)
        expect(rebuilt.glyph_count).to eq(source_cff.glyph_count)
      end

      it "handles hints without breaking structure" do
        without_hints = described_class.rebuild(source_cff)
        with_hints = described_class.rebuild(source_cff, hint_mods)

        # Both should be valid
        expect(Fontisan::Tables::Cff.read(without_hints).valid?).to be true
        expect(Fontisan::Tables::Cff.read(with_hints).valid?).to be true

        # Size should be similar (within 10%)
        expect(with_hints.bytesize).to be_within(without_hints.bytesize * 0.1).of(without_hints.bytesize)
      end
    end

    context "with multiple hint parameters" do
      let(:complex_hints) do
        {
          private_dict_hints: {
            blue_values: [-15, 0, 721, 736, 470, 485],
            other_blues: [-250, -240],
            std_hw: 70,
            std_vw: 85,
            stem_snap_h: [70, 75, 80],
            blue_scale: 0.039625,
          },
        }
      end

      it "handles complex hint params" do
        result = described_class.rebuild(source_cff, complex_hints)
        rebuilt = Fontisan::Tables::Cff.read(result)
        expect(rebuilt.valid?).to be true
      end

      it "preserves structure with complex hints" do
        result = described_class.rebuild(source_cff, complex_hints)
        rebuilt = Fontisan::Tables::Cff.read(result)
        expect(rebuilt.glyph_count).to eq(source_cff.glyph_count)
        expect(rebuilt.font_name).to eq(source_cff.font_name)
      end
    end
  end

  describe "#initialize" do
    it "initializes with source CFF" do
      builder = described_class.new(source_cff)
      expect(builder).to be_a(described_class)
    end

    it "extracts sections on init" do
      builder = described_class.new(source_cff)
      sections = builder.instance_variable_get(:@sections)
      expect(sections).to be_a(Hash)
      expect(sections.keys).to include(
        :header, :name_index, :top_dict_index,
        :string_index, :global_subr_index,
        :charstrings_index, :private_dict
      )
    end
  end

  describe "#serialize" do
    it "produces binary output" do
      builder = described_class.new(source_cff)
      result = builder.serialize
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "produces parseable CFF" do
      builder = described_class.new(source_cff)
      result = builder.serialize
      rebuilt = Fontisan::Tables::Cff.read(result)
      expect(rebuilt.valid?).to be true
    end
  end

  describe "offset recalculation" do
    it "recalculates offsets correctly" do
      hint_mods = {
        private_dict_hints: { std_hw: 70 },
      }
      result = described_class.rebuild(source_cff, hint_mods)
      rebuilt = Fontisan::Tables::Cff.read(result)

      # Verify structure is intact
      expect(rebuilt.top_dict(0)).not_to be_nil
      expect(rebuilt.charstrings_index(0)).not_to be_nil
      expect(rebuilt.private_dict(0)).not_to be_nil
    end

    it "handles private dict size changes" do
      small_hints = {
        private_dict_hints: { std_hw: 70 },
      }
      large_hints = {
        private_dict_hints: {
          blue_values: [-15, 0, 721, 736, 470, 485, 520, 535],
          other_blues: [-250, -240],
          std_hw: 70,
          std_vw: 85,
        },
      }

      result1 = described_class.rebuild(source_cff, small_hints)
      result2 = described_class.rebuild(source_cff, large_hints)

      # Larger hints should produce larger table
      expect(result2.bytesize).to be > result1.bytesize

      # Both should be valid
      expect(Fontisan::Tables::Cff.read(result1).valid?).to be true
      expect(Fontisan::Tables::Cff.read(result2).valid?).to be true
    end
  end

  describe "section extraction" do
    it "extracts all required sections" do
      builder = described_class.new(source_cff)
      sections = builder.instance_variable_get(:@sections)

      expect(sections[:header]).not_to be_empty
      expect(sections[:name_index]).not_to be_empty
      expect(sections[:top_dict_index]).not_to be_empty
      expect(sections[:charstrings_index]).not_to be_empty
    end

    it "preserves section integrity" do
      builder = described_class.new(source_cff)
      result = builder.serialize
      rebuilt = Fontisan::Tables::Cff.read(result)

      # Check that key sections are preserved
      expect(rebuilt.font_count).to eq(source_cff.font_count)
      expect(rebuilt.glyph_count).to eq(source_cff.glyph_count)
      expect(rebuilt.custom_string_count).to eq(source_cff.custom_string_count)
    end
  end

  describe "error handling" do
    it "handles empty modifications" do
      result = described_class.rebuild(source_cff, {})
      rebuilt = Fontisan::Tables::Cff.read(result)
      expect(rebuilt.valid?).to be true
    end

    it "handles nil modifications" do
      result = described_class.rebuild(source_cff)
      rebuilt = Fontisan::Tables::Cff.read(result)
      expect(rebuilt.valid?).to be true
    end
  end

  describe "integration with other components" do
    it "works with PrivateDictWriter" do
      hint_mods = {
        private_dict_hints: {
          blue_values: [-15, 0],
          std_hw: 70,
        },
      }
      result = described_class.rebuild(source_cff, hint_mods)
      expect(result).not_to be_empty
    end

    it "works with OffsetRecalculator" do
      result = described_class.rebuild(source_cff)
      rebuilt = Fontisan::Tables::Cff.read(result)

      # Verify offsets are correct by checking structure
      expect(rebuilt.charstrings_index(0)).not_to be_nil
      expect(rebuilt.private_dict(0)).not_to be_nil
    end

    it "produces CFF readable by CFF parser" do
      hint_mods = {
        private_dict_hints: { std_hw: 70 },
      }
      result = described_class.rebuild(source_cff, hint_mods)
      rebuilt = Fontisan::Tables::Cff.read(result)

      # Full parsing check
      expect(rebuilt.font_name).to eq(source_cff.font_name)
      expect(rebuilt.version).to eq(source_cff.version)
      expect(rebuilt.glyph_count).to eq(source_cff.glyph_count)
    end
  end
end