# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Hhea do
  # Test fixtures acknowledgment:
  # Using Libertinus fonts (OFL licensed) from:
  # https://github.com/alerque/libertinus
  # Copyright © 2012-2023 The Libertinus Project Authors
  # Helper to build valid hhea table binary data
  #
  # Based on OpenType specification for hhea table structure:
  # https://docs.microsoft.com/en-us/typography/opentype/spec/hhea
  #
  # Reference implementations:
  # - ttfunk: https://github.com/prawnpdf/ttfunk
  # - fonttools: https://github.com/fonttools/fonttools
  def build_hhea_table(
    version: 1.0,
    ascent: 2048,
    descent: -512,
    line_gap: 0,
    advance_width_max: 3000,
    min_left_side_bearing: -200,
    min_right_side_bearing: -100,
    x_max_extent: 2800,
    caret_slope_rise: 1,
    caret_slope_run: 0,
    caret_offset: 0,
    metric_data_format: 0,
    number_of_h_metrics: 256
  )
    data = (+"").b

    # Version (Fixed 16.16) - stored as int32
    integer_part = version.to_i
    fractional_part = ((version - integer_part) * 65_536).to_i
    version_raw = (integer_part << 16) | fractional_part
    data << [version_raw].pack("N")

    # Ascent (int16)
    data << [ascent].pack("s>")

    # Descent (int16)
    data << [descent].pack("s>")

    # Line Gap (int16)
    data << [line_gap].pack("s>")

    # Advance Width Max (uint16)
    data << [advance_width_max].pack("n")

    # Min Left Side Bearing (int16)
    data << [min_left_side_bearing].pack("s>")

    # Min Right Side Bearing (int16)
    data << [min_right_side_bearing].pack("s>")

    # X Max Extent (int16)
    data << [x_max_extent].pack("s>")

    # Caret Slope Rise (int16)
    data << [caret_slope_rise].pack("s>")

    # Caret Slope Run (int16)
    data << [caret_slope_run].pack("s>")

    # Caret Offset (int16)
    data << [caret_offset].pack("s>")

    # Reserved (4 x int16 = 8 bytes)
    data << [0, 0, 0, 0].pack("s>4")

    # Metric Data Format (int16)
    data << [metric_data_format].pack("s>")

    # Number of H Metrics (uint16)
    data << [number_of_h_metrics].pack("n")

    data
  end

  describe ".read" do
    context "with valid hhea table data" do
      let(:data) { build_hhea_table }
      let(:hhea) { described_class.read(data) }

      it "parses version correctly" do
        expect(hhea.version).to be_within(0.001).of(1.0)
      end

      it "parses ascent correctly" do
        expect(hhea.ascent).to eq(2048)
      end

      it "parses descent correctly" do
        expect(hhea.descent).to eq(-512)
      end

      it "parses line_gap correctly" do
        expect(hhea.line_gap).to eq(0)
      end

      it "parses advance_width_max correctly" do
        expect(hhea.advance_width_max).to eq(3000)
      end

      it "parses min_left_side_bearing correctly" do
        expect(hhea.min_left_side_bearing).to eq(-200)
      end

      it "parses min_right_side_bearing correctly" do
        expect(hhea.min_right_side_bearing).to eq(-100)
      end

      it "parses x_max_extent correctly" do
        expect(hhea.x_max_extent).to eq(2800)
      end

      it "parses caret_slope_rise correctly" do
        expect(hhea.caret_slope_rise).to eq(1)
      end

      it "parses caret_slope_run correctly" do
        expect(hhea.caret_slope_run).to eq(0)
      end

      it "parses caret_offset correctly" do
        expect(hhea.caret_offset).to eq(0)
      end

      it "parses metric_data_format correctly" do
        expect(hhea.metric_data_format).to eq(0)
      end

      it "parses number_of_h_metrics correctly" do
        expect(hhea.number_of_h_metrics).to eq(256)
      end
    end

    context "with typical font values" do
      it "handles typical TrueType metrics (2048 upem)" do
        data = build_hhea_table(
          ascent: 1900,
          descent: -400,
          line_gap: 0,
          advance_width_max: 2500,
        )
        hhea = described_class.read(data)

        expect(hhea.ascent).to eq(1900)
        expect(hhea.descent).to eq(-400)
        expect(hhea.line_gap).to eq(0)
        expect(hhea.advance_width_max).to eq(2500)
      end

      it "handles typical PostScript metrics (1000 upem)" do
        data = build_hhea_table(
          ascent: 850,
          descent: -250,
          line_gap: 100,
          advance_width_max: 1200,
        )
        hhea = described_class.read(data)

        expect(hhea.ascent).to eq(850)
        expect(hhea.descent).to eq(-250)
        expect(hhea.line_gap).to eq(100)
        expect(hhea.advance_width_max).to eq(1200)
      end

      it "handles vertical text (caret slope)" do
        data = build_hhea_table(
          caret_slope_rise: 1,
          caret_slope_run: 0,
        )
        hhea = described_class.read(data)

        expect(hhea.caret_slope_rise).to eq(1)
        expect(hhea.caret_slope_run).to eq(0)
      end

      it "handles italic text (caret slope)" do
        data = build_hhea_table(
          caret_slope_rise: 1,
          caret_slope_run: 3,
        )
        hhea = described_class.read(data)

        expect(hhea.caret_slope_rise).to eq(1)
        expect(hhea.caret_slope_run).to eq(3)
      end
    end

    context "with edge case values" do
      it "handles maximum positive ascent" do
        data = build_hhea_table(ascent: 32767) # Max int16
        hhea = described_class.read(data)
        expect(hhea.ascent).to eq(32767)
      end

      it "handles maximum negative descent" do
        data = build_hhea_table(descent: -32768) # Min int16
        hhea = described_class.read(data)
        expect(hhea.descent).to eq(-32768)
      end

      it "handles zero line gap" do
        data = build_hhea_table(line_gap: 0)
        hhea = described_class.read(data)
        expect(hhea.line_gap).to eq(0)
      end

      it "handles positive line gap" do
        data = build_hhea_table(line_gap: 200)
        hhea = described_class.read(data)
        expect(hhea.line_gap).to eq(200)
      end

      it "handles minimum number of h metrics (1)" do
        data = build_hhea_table(number_of_h_metrics: 1)
        hhea = described_class.read(data)
        expect(hhea.number_of_h_metrics).to eq(1)
      end

      it "handles large number of h metrics" do
        data = build_hhea_table(number_of_h_metrics: 65535) # Max uint16
        hhea = described_class.read(data)
        expect(hhea.number_of_h_metrics).to eq(65535)
      end
    end

    context "with negative sidebearing values" do
      it "handles negative min_left_side_bearing" do
        data = build_hhea_table(min_left_side_bearing: -500)
        hhea = described_class.read(data)
        expect(hhea.min_left_side_bearing).to eq(-500)
      end

      it "handles negative min_right_side_bearing" do
        data = build_hhea_table(min_right_side_bearing: -300)
        hhea = described_class.read(data)
        expect(hhea.min_right_side_bearing).to eq(-300)
      end

      it "handles positive sidebearings" do
        data = build_hhea_table(
          min_left_side_bearing: 50,
          min_right_side_bearing: 100,
        )
        hhea = described_class.read(data)

        expect(hhea.min_left_side_bearing).to eq(50)
        expect(hhea.min_right_side_bearing).to eq(100)
      end
    end

    context "with different version values" do
      it "handles version 1.0" do
        data = build_hhea_table(version: 1.0)
        hhea = described_class.read(data)
        expect(hhea.version).to be_within(0.001).of(1.0)
      end

      it "stores version as raw int32 correctly" do
        data = build_hhea_table(version: 1.0)
        hhea = described_class.read(data)
        expect(hhea.version_raw).to eq(0x00010000)
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
    it "returns true for valid hhea table" do
      data = build_hhea_table
      hhea = described_class.read(data)
      expect(hhea).to be_valid
    end

    it "returns false for invalid version" do
      data = build_hhea_table(version: 2.0)
      hhea = described_class.read(data)
      expect(hhea).not_to be_valid
    end

    it "returns false for invalid metric data format" do
      data = build_hhea_table(metric_data_format: 1)
      hhea = described_class.read(data)
      expect(hhea).not_to be_valid
    end

    it "returns false for zero h metrics" do
      data = build_hhea_table(number_of_h_metrics: 0)
      hhea = described_class.read(data)
      expect(hhea).not_to be_valid
    end
  end

  describe "#validate!" do
    it "does not raise error for valid table" do
      data = build_hhea_table
      hhea = described_class.read(data)
      expect { hhea.validate! }.not_to raise_error
    end

    it "raises CorruptedTableError for invalid version" do
      data = build_hhea_table(version: 2.0)
      hhea = described_class.read(data)

      expect { hhea.validate! }.to raise_error(
        Fontisan::CorruptedTableError,
        /Invalid hhea version/,
      )
    end

    it "raises CorruptedTableError for invalid metric data format" do
      data = build_hhea_table(metric_data_format: 1)
      hhea = described_class.read(data)

      expect { hhea.validate! }.to raise_error(
        Fontisan::CorruptedTableError,
        /Invalid metric data format/,
      )
    end

    it "raises CorruptedTableError for zero h metrics" do
      data = build_hhea_table(number_of_h_metrics: 0)
      hhea = described_class.read(data)

      expect { hhea.validate! }.to raise_error(
        Fontisan::CorruptedTableError,
        /Invalid number of h metrics/,
      )
    end
  end

  describe "::TABLE_SIZE" do
    it "defines correct table size" do
      expect(described_class::TABLE_SIZE).to eq(36)
    end

    it "matches actual parsed data size" do
      data = build_hhea_table
      expect(data.bytesize).to eq(described_class::TABLE_SIZE)
    end
  end

  describe "integration with real fonts" do
    let(:libertinus_serif_path) do
      font_fixture_path("Libertinus", "static/TTF/LibertinusSerif-Regular.ttf")
    end

    context "when reading from TrueType font" do
      it "successfully parses hhea table from Libertinus Serif" do
        font = Fontisan::TrueTypeFont.from_file(libertinus_serif_path)
        hhea = font.table("hhea")

        # hhea table is required and should exist
        expect(hhea).not_to be_nil, "hhea table should exist in Libertinus font"

        # Verify basic structure
        expect(hhea.version).to be_within(0.001).of(1.0)
        expect(hhea).to be_valid

        # Verify metrics are reasonable
        expect(hhea.ascent).to be > 0
        expect(hhea.descent).to be < 0
        expect(hhea.number_of_h_metrics).to be >= 1

        # Verify no errors during validation
        expect { hhea.validate! }.not_to raise_error
      end
    end

    context "when reading from OpenType/CFF font" do
      let(:libertinus_serif_otf_path) do
        font_fixture_path("Libertinus",
                          "static/OTF/LibertinusSerif-Regular.otf")
      end

      it "successfully parses hhea table from Libertinus Serif OTF" do
        font = Fontisan::OpenTypeFont.from_file(libertinus_serif_otf_path)
        hhea = font.table("hhea")

        # hhea table is required and should exist
        expect(hhea).not_to be_nil, "hhea table should exist in Libertinus font"

        # CFF fonts also have hhea tables
        expect(hhea.version).to be_within(0.001).of(1.0)
        expect(hhea).to be_valid
        expect(hhea.number_of_h_metrics).to be >= 1
      end
    end
  end
end
