# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Maxp do
  # Test fixtures acknowledgment:
  # Using Libertinus fonts (OFL licensed) from:
  # https://github.com/alerque/libertinus
  # Copyright © 2012-2023 The Libertinus Project Authors
  #
  # Additional reference implementations:
  # - ttfunk: https://github.com/prawnpdf/ttfunk/blob/master/lib/ttfunk/table/maxp.rb
  # - fonttools: https://github.com/fonttools/fonttools/blob/main/Lib/fontTools/ttLib/tables/_m_a_x_p.py
  # - Allsorts: https://github.com/yeslogic/allsorts

  # Helper to build valid maxp table binary data for version 0.5 (CFF fonts)
  #
  # Based on OpenType specification for maxp table structure:
  # https://docs.microsoft.com/en-us/typography/opentype/spec/maxp
  #
  # Version 0.5 contains only:
  # - version (Fixed 16.16): 4 bytes
  # - numGlyphs (uint16): 2 bytes
  # Total: 6 bytes
  def build_maxp_table_v0_5(num_glyphs: 256)
    data = (+"").b

    # Version 0.5 as Fixed 16.16 (0x00005000)
    data << [0x00005000].pack("N")

    # Number of glyphs (uint16)
    data << [num_glyphs].pack("n")

    data
  end

  # Helper to build valid maxp table binary data for version 1.0 (TrueType fonts)
  #
  # Version 1.0 contains version + numGlyphs + 13 additional uint16 fields
  # Total: 32 bytes
  def build_maxp_table_v1_0(
    num_glyphs: 256,
    max_points: 100,
    max_contours: 10,
    max_composite_points: 200,
    max_composite_contours: 20,
    max_zones: 2,
    max_twilight_points: 50,
    max_storage: 64,
    max_function_defs: 32,
    max_instruction_defs: 16,
    max_stack_elements: 512,
    max_size_of_instructions: 1000,
    max_component_elements: 10,
    max_component_depth: 5
  )
    data = (+"").b

    # Version 1.0 as Fixed 16.16 (0x00010000)
    data << [0x00010000].pack("N")

    # Number of glyphs (uint16)
    data << [num_glyphs].pack("n")

    # 13 additional uint16 fields for version 1.0
    data << [max_points].pack("n")
    data << [max_contours].pack("n")
    data << [max_composite_points].pack("n")
    data << [max_composite_contours].pack("n")
    data << [max_zones].pack("n")
    data << [max_twilight_points].pack("n")
    data << [max_storage].pack("n")
    data << [max_function_defs].pack("n")
    data << [max_instruction_defs].pack("n")
    data << [max_stack_elements].pack("n")
    data << [max_size_of_instructions].pack("n")
    data << [max_component_elements].pack("n")
    data << [max_component_depth].pack("n")

    data
  end

  describe ".read" do
    context "with version 0.5 (CFF fonts)" do
      let(:data) { build_maxp_table_v0_5 }
      let(:maxp) { described_class.read(data) }

      it "parses version correctly" do
        expect(maxp.version).to be_within(0.001).of(0.5)
      end

      it "parses version_raw correctly" do
        expect(maxp.version_raw).to eq(0x00005000)
      end

      it "parses num_glyphs correctly" do
        expect(maxp.num_glyphs).to eq(256)
      end

      it "identifies as version 0.5" do
        expect(maxp).to be_version_0_5
        expect(maxp).not_to be_version_1_0
      end

      it "identifies as CFF font" do
        expect(maxp).to be_cff
        expect(maxp).not_to be_truetype
      end

      it "does not read version 1.0 fields (remain as default 0)" do
        # BinData's onlyif doesn't make fields nil, just doesn't read them
        # So they remain as their default value (0 for uint16)
        expect(maxp.max_points).to eq(0)
        expect(maxp.max_contours).to eq(0)
        expect(maxp.max_composite_points).to eq(0)
      end

      it "has correct expected size" do
        expect(maxp.expected_size).to eq(described_class::TABLE_SIZE_V0_5)
        expect(maxp.expected_size).to eq(6)
      end
    end

    context "with version 1.0 (TrueType fonts)" do
      let(:data) { build_maxp_table_v1_0 }
      let(:maxp) { described_class.read(data) }

      it "parses version correctly" do
        expect(maxp.version).to be_within(0.001).of(1.0)
      end

      it "parses version_raw correctly" do
        expect(maxp.version_raw).to eq(0x00010000)
      end

      it "parses num_glyphs correctly" do
        expect(maxp.num_glyphs).to eq(256)
      end

      it "parses max_points correctly" do
        expect(maxp.max_points).to eq(100)
      end

      it "parses max_contours correctly" do
        expect(maxp.max_contours).to eq(10)
      end

      it "parses max_composite_points correctly" do
        expect(maxp.max_composite_points).to eq(200)
      end

      it "parses max_composite_contours correctly" do
        expect(maxp.max_composite_contours).to eq(20)
      end

      it "parses max_zones correctly" do
        expect(maxp.max_zones).to eq(2)
      end

      it "parses max_twilight_points correctly" do
        expect(maxp.max_twilight_points).to eq(50)
      end

      it "parses max_storage correctly" do
        expect(maxp.max_storage).to eq(64)
      end

      it "parses max_function_defs correctly" do
        expect(maxp.max_function_defs).to eq(32)
      end

      it "parses max_instruction_defs correctly" do
        expect(maxp.max_instruction_defs).to eq(16)
      end

      it "parses max_stack_elements correctly" do
        expect(maxp.max_stack_elements).to eq(512)
      end

      it "parses max_size_of_instructions correctly" do
        expect(maxp.max_size_of_instructions).to eq(1000)
      end

      it "parses max_component_elements correctly" do
        expect(maxp.max_component_elements).to eq(10)
      end

      it "parses max_component_depth correctly" do
        expect(maxp.max_component_depth).to eq(5)
      end

      it "identifies as version 1.0" do
        expect(maxp).to be_version_1_0
        expect(maxp).not_to be_version_0_5
      end

      it "identifies as TrueType font" do
        expect(maxp).to be_truetype
        expect(maxp).not_to be_cff
      end

      it "has correct expected size" do
        expect(maxp.expected_size).to eq(described_class::TABLE_SIZE_V1_0)
        expect(maxp.expected_size).to eq(32)
      end
    end

    context "with typical TrueType font values" do
      it "handles simple font with few glyphs" do
        data = build_maxp_table_v1_0(
          num_glyphs: 128,
          max_points: 50,
          max_contours: 5,
          max_zones: 1,
        )
        maxp = described_class.read(data)

        expect(maxp.num_glyphs).to eq(128)
        expect(maxp.max_points).to eq(50)
        expect(maxp.max_contours).to eq(5)
        expect(maxp.max_zones).to eq(1)
      end

      it "handles complex font with many glyphs" do
        data = build_maxp_table_v1_0(
          num_glyphs: 65535, # Maximum uint16
          max_points: 1000,
          max_contours: 100,
          max_zones: 2,
        )
        maxp = described_class.read(data)

        expect(maxp.num_glyphs).to eq(65535)
        expect(maxp.max_points).to eq(1000)
        expect(maxp.max_contours).to eq(100)
        expect(maxp.max_zones).to eq(2)
      end

      it "handles font without composite glyphs" do
        data = build_maxp_table_v1_0(
          max_composite_points: 0,
          max_composite_contours: 0,
          max_component_elements: 0,
          max_component_depth: 0,
        )
        maxp = described_class.read(data)

        expect(maxp.max_composite_points).to eq(0)
        expect(maxp.max_composite_contours).to eq(0)
        expect(maxp.max_component_elements).to eq(0)
        expect(maxp.max_component_depth).to eq(0)
      end

      it "handles font with no instructions" do
        data = build_maxp_table_v1_0(
          max_function_defs: 0,
          max_instruction_defs: 0,
          max_stack_elements: 0,
          max_size_of_instructions: 0,
        )
        maxp = described_class.read(data)

        expect(maxp.max_function_defs).to eq(0)
        expect(maxp.max_instruction_defs).to eq(0)
        expect(maxp.max_stack_elements).to eq(0)
        expect(maxp.max_size_of_instructions).to eq(0)
      end
    end

    context "with typical CFF font values" do
      it "handles minimal CFF font" do
        data = build_maxp_table_v0_5(num_glyphs: 1)
        maxp = described_class.read(data)

        expect(maxp.num_glyphs).to eq(1)
        expect(maxp).to be_cff
      end

      it "handles typical CFF font" do
        data = build_maxp_table_v0_5(num_glyphs: 512)
        maxp = described_class.read(data)

        expect(maxp.num_glyphs).to eq(512)
        expect(maxp).to be_cff
      end

      it "handles large CFF font" do
        data = build_maxp_table_v0_5(num_glyphs: 65535)
        maxp = described_class.read(data)

        expect(maxp.num_glyphs).to eq(65535)
        expect(maxp).to be_cff
      end
    end

    context "with edge case values" do
      it "handles minimum number of glyphs (1)" do
        data = build_maxp_table_v1_0(num_glyphs: 1)
        maxp = described_class.read(data)
        expect(maxp.num_glyphs).to eq(1)
      end

      it "handles maximum number of glyphs (65535)" do
        data = build_maxp_table_v1_0(num_glyphs: 65535)
        maxp = described_class.read(data)
        expect(maxp.num_glyphs).to eq(65535)
      end

      it "handles maxZones = 1 (no twilight zone)" do
        data = build_maxp_table_v1_0(max_zones: 1)
        maxp = described_class.read(data)
        expect(maxp.max_zones).to eq(1)
      end

      it "handles maxZones = 2 (twilight zone present)" do
        data = build_maxp_table_v1_0(max_zones: 2)
        maxp = described_class.read(data)
        expect(maxp.max_zones).to eq(2)
      end

      it "handles zero values in optional fields" do
        data = build_maxp_table_v1_0(
          max_points: 0,
          max_contours: 0,
          max_twilight_points: 0,
          max_storage: 0,
        )
        maxp = described_class.read(data)

        expect(maxp.max_points).to eq(0)
        expect(maxp.max_contours).to eq(0)
        expect(maxp.max_twilight_points).to eq(0)
        expect(maxp.max_storage).to eq(0)
      end

      it "handles maximum uint16 values" do
        data = build_maxp_table_v1_0(
          max_points: 65535,
          max_contours: 65535,
          max_stack_elements: 65535,
        )
        maxp = described_class.read(data)

        expect(maxp.max_points).to eq(65535)
        expect(maxp.max_contours).to eq(65535)
        expect(maxp.max_stack_elements).to eq(65535)
      end
    end

    context "with nil or empty data" do
      it "handles nil data gracefully" do
        expect { described_class.read(nil) }.not_to raise_error
      end

      it "handles empty string gracefully" do
        expect { described_class.read("") }.not_to raise_error
      end
    end
  end

  describe "#valid?" do
    context "with version 0.5" do
      it "returns true for valid v0.5 table" do
        data = build_maxp_table_v0_5
        maxp = described_class.read(data)
        expect(maxp).to be_valid
      end

      it "returns true for minimum glyphs (1)" do
        data = build_maxp_table_v0_5(num_glyphs: 1)
        maxp = described_class.read(data)
        expect(maxp).to be_valid
      end
    end

    context "with version 1.0" do
      it "returns true for valid v1.0 table" do
        data = build_maxp_table_v1_0
        maxp = described_class.read(data)
        expect(maxp).to be_valid
      end

      it "returns true with maxZones = 1" do
        data = build_maxp_table_v1_0(max_zones: 1)
        maxp = described_class.read(data)
        expect(maxp).to be_valid
      end

      it "returns true with maxZones = 2" do
        data = build_maxp_table_v1_0(max_zones: 2)
        maxp = described_class.read(data)
        expect(maxp).to be_valid
      end

      it "returns false with invalid maxZones = 0" do
        data = build_maxp_table_v1_0(max_zones: 0)
        maxp = described_class.read(data)
        expect(maxp).not_to be_valid
      end

      it "returns false with invalid maxZones = 3" do
        data = build_maxp_table_v1_0(max_zones: 3)
        maxp = described_class.read(data)
        expect(maxp).not_to be_valid
      end
    end

    context "with invalid data" do
      it "returns false for invalid version" do
        data = (+"").b
        data << [0x00020000].pack("N") # Invalid version 2.0
        data << [256].pack("n")
        maxp = described_class.read(data)
        expect(maxp).not_to be_valid
      end

      it "returns false for zero glyphs" do
        data = build_maxp_table_v1_0(num_glyphs: 0)
        maxp = described_class.read(data)
        expect(maxp).not_to be_valid
      end
    end
  end

  describe "#validate!" do
    context "with valid tables" do
      it "does not raise error for valid v0.5 table" do
        data = build_maxp_table_v0_5
        maxp = described_class.read(data)
        expect { maxp.validate! }.not_to raise_error
      end

      it "does not raise error for valid v1.0 table" do
        data = build_maxp_table_v1_0
        maxp = described_class.read(data)
        expect { maxp.validate! }.not_to raise_error
      end
    end

    context "with invalid tables" do
      # For testing purposes, we'll test the validation logic directly
      it "detects invalid version through valid? method" do
        data = (+"").b
        data << [0x00020000].pack("N") # Invalid version 2.0
        data << [256].pack("n")
        maxp = described_class.read(data)

        # Should be detected as invalid by valid? method
        expect(maxp).not_to be_valid
      end

      it "raises CorruptedTableError for zero glyphs" do
        data = build_maxp_table_v1_0(num_glyphs: 0)
        maxp = described_class.read(data)

        expect { maxp.validate! }.to raise_error(
          Fontisan::CorruptedTableError,
          /Invalid number of glyphs/,
        )
      end

      it "raises CorruptedTableError for invalid maxZones" do
        data = build_maxp_table_v1_0(max_zones: 0)
        maxp = described_class.read(data)

        expect { maxp.validate! }.to raise_error(
          Fontisan::CorruptedTableError,
          /Invalid maxZones/,
        )
      end
    end
  end

  describe "version detection methods" do
    context "with version 0.5" do
      let(:data) { build_maxp_table_v0_5 }
      let(:maxp) { described_class.read(data) }

      it "#version_0_5? returns true" do
        expect(maxp.version_0_5?).to be true
      end

      it "#version_1_0? returns false" do
        expect(maxp.version_1_0?).to be false
      end

      it "#cff? returns true" do
        expect(maxp.cff?).to be true
      end

      it "#truetype? returns false" do
        expect(maxp.truetype?).to be false
      end
    end

    context "with version 1.0" do
      let(:data) { build_maxp_table_v1_0 }
      let(:maxp) { described_class.read(data) }

      it "#version_1_0? returns true" do
        expect(maxp.version_1_0?).to be true
      end

      it "#version_0_5? returns false" do
        expect(maxp.version_0_5?).to be false
      end

      it "#truetype? returns true" do
        expect(maxp.truetype?).to be true
      end

      it "#cff? returns false" do
        expect(maxp.cff?).to be false
      end
    end
  end

  describe "constants" do
    it "defines VERSION_0_5" do
      expect(described_class::VERSION_0_5).to eq(0x00005000)
    end

    it "defines VERSION_1_0" do
      expect(described_class::VERSION_1_0).to eq(0x00010000)
    end

    it "defines TABLE_SIZE_V0_5" do
      expect(described_class::TABLE_SIZE_V0_5).to eq(6)
    end

    it "defines TABLE_SIZE_V1_0" do
      expect(described_class::TABLE_SIZE_V1_0).to eq(32)
    end
  end

  describe "#expected_size" do
    it "returns correct size for version 0.5" do
      data = build_maxp_table_v0_5
      maxp = described_class.read(data)
      expect(maxp.expected_size).to eq(6)
    end

    it "returns correct size for version 1.0" do
      data = build_maxp_table_v1_0
      maxp = described_class.read(data)
      expect(maxp.expected_size).to eq(32)
    end

    it "matches actual data size for version 0.5" do
      data = build_maxp_table_v0_5
      maxp = described_class.read(data)
      expect(data.bytesize).to eq(maxp.expected_size)
    end

    it "matches actual data size for version 1.0" do
      data = build_maxp_table_v1_0
      maxp = described_class.read(data)
      expect(data.bytesize).to eq(maxp.expected_size)
    end
  end

  describe "integration with real fonts" do
    let(:libertinus_serif_ttf_path) do
      font_fixture_path("Libertinus", "static/TTF/LibertinusSerif-Regular.ttf")
    end

    let(:libertinus_serif_otf_path) do
      font_fixture_path("Libertinus", "static/OTF/LibertinusSerif-Regular.otf")
    end

    context "when reading from TrueType font" do
      it "successfully parses maxp table from Libertinus Serif TTF" do
        skip "Font file not available" unless File.exist?(libertinus_serif_ttf_path)

        font = Fontisan::TrueTypeFont.from_file(libertinus_serif_ttf_path)
        maxp = font.table("maxp")
        skip "maxp table not found" if maxp.nil?

        # Verify this is version 1.0 (TrueType)
        expect(maxp).to be_truetype
        expect(maxp).to be_version_1_0
        expect(maxp.version).to be_within(0.001).of(1.0)

        # Verify table is valid
        expect(maxp).to be_valid
        expect { maxp.validate! }.not_to raise_error

        # Verify basic fields are reasonable
        expect(maxp.num_glyphs).to be >= 1
        expect(maxp.max_points).to be >= 0
        expect(maxp.max_contours).to be >= 0
        expect(maxp.max_zones).to be_between(1, 2)

        # Verify all version 1.0 fields are present
        expect(maxp.max_points).not_to be_nil
        expect(maxp.max_contours).not_to be_nil
        expect(maxp.max_composite_points).not_to be_nil
        expect(maxp.max_composite_contours).not_to be_nil
        expect(maxp.max_zones).not_to be_nil
        expect(maxp.max_twilight_points).not_to be_nil
        expect(maxp.max_storage).not_to be_nil
        expect(maxp.max_function_defs).not_to be_nil
        expect(maxp.max_instruction_defs).not_to be_nil
        expect(maxp.max_stack_elements).not_to be_nil
        expect(maxp.max_size_of_instructions).not_to be_nil
        expect(maxp.max_component_elements).not_to be_nil
        expect(maxp.max_component_depth).not_to be_nil
      end
    end

    context "when reading from OpenType/CFF font" do
      it "successfully parses maxp table from Libertinus Serif OTF" do
        skip "Font file not available" unless File.exist?(libertinus_serif_otf_path)

        font = Fontisan::OpenTypeFont.from_file(libertinus_serif_otf_path)
        maxp = font.table("maxp")
        skip "maxp table not found" if maxp.nil?

        # Verify this is version 0.5 (CFF)
        expect(maxp).to be_cff
        expect(maxp).to be_version_0_5
        expect(maxp.version).to be_within(0.001).of(0.5)

        # Verify table is valid
        expect(maxp).to be_valid
        expect { maxp.validate! }.not_to raise_error

        # Verify numGlyphs is present
        expect(maxp.num_glyphs).to be >= 1

        # Verify version 1.0 fields are NOT present (nil or 0 for version 0.5)
        expect(maxp.max_points).to be_nil.or eq(0)
        expect(maxp.max_contours).to be_nil.or eq(0)
        expect(maxp.max_composite_points).to be_nil.or eq(0)
      end
    end

    context "when used with hmtx table" do
      it "provides numGlyphs for hmtx parsing (TTF)" do
        skip "Font file not available" unless File.exist?(libertinus_serif_ttf_path)

        font = Fontisan::TrueTypeFont.from_file(libertinus_serif_ttf_path)
        maxp = font.table("maxp")
        hhea = font.table("hhea")
        skip "Required tables not found" if maxp.nil? || hhea.nil?

        # maxp provides numGlyphs needed for hmtx parsing
        expect(maxp.num_glyphs).to be >= 1
        expect(hhea.number_of_h_metrics).to be >= 1
        expect(hhea.number_of_h_metrics).to be <= maxp.num_glyphs

        # This relationship is crucial for hmtx table parsing
        # hmtx needs: hhea.numberOfHMetrics and maxp.numGlyphs
      end

      it "provides numGlyphs for hmtx parsing (OTF)" do
        skip "Font file not available" unless File.exist?(libertinus_serif_otf_path)

        font = Fontisan::OpenTypeFont.from_file(libertinus_serif_otf_path)
        maxp = font.table("maxp")
        hhea = font.table("hhea")
        skip "Required tables not found" if maxp.nil? || hhea.nil?

        # CFF fonts also have maxp and hmtx tables
        expect(maxp.num_glyphs).to be >= 1
        expect(hhea.number_of_h_metrics).to be >= 1
        expect(hhea.number_of_h_metrics).to be <= maxp.num_glyphs
      end
    end
  end
end
