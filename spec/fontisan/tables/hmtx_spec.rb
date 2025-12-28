# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Hmtx do
  # Test fixtures acknowledgment:
  # Using Libertinus fonts (OFL licensed) from:
  # https://github.com/alerque/libertinus
  # Copyright © 2012-2023 The Libertinus Project Authors
  #
  # Reference implementations:
  # - ttfunk: https://github.com/prawnpdf/ttfunk (lib/ttfunk/table/hmtx.rb)
  # - fonttools: https://github.com/fonttools/fonttools
  # - Allsorts: https://github.com/yeslogic/allsorts

  # Helper to build hmtx table binary data
  #
  # Based on OpenType specification for hmtx table structure:
  # https://docs.microsoft.com/en-us/typography/opentype/spec/hmtx
  #
  # @param h_metrics [Array<Hash>] Array of {advance_width, lsb} hashes
  # @param left_side_bearings [Array<Integer>] Additional LSBs
  # @return [String] Binary data
  def build_hmtx_table(h_metrics:, left_side_bearings: [])
    data = (+"").b

    # Write hMetrics (LongHorMetric records)
    h_metrics.each do |metric|
      data << [metric[:advance_width]].pack("n")  # uint16
      data << [metric[:lsb]].pack("s>")           # int16
    end

    # Write additional left side bearings
    left_side_bearings.each do |lsb|
      data << [lsb].pack("s>") # int16
    end

    data
  end

  describe ".read" do
    it "reads and stores raw data" do
      data = build_hmtx_table(h_metrics: [{ advance_width: 1000, lsb: 50 }])
      hmtx = described_class.read(data)

      expect(hmtx.raw_data).to eq(data)
    end

    it "does not parse data until parse_with_context is called" do
      data = build_hmtx_table(h_metrics: [{ advance_width: 1000, lsb: 50 }])
      hmtx = described_class.read(data)

      expect(hmtx.h_metrics).to be_nil
      expect(hmtx.left_side_bearings).to be_nil
    end

    it "handles nil data" do
      expect { described_class.read(nil) }.not_to raise_error
    end

    it "handles empty string" do
      expect { described_class.read("") }.not_to raise_error
    end
  end

  describe "#parse_with_context" do
    context "with simple font (all glyphs have unique metrics)" do
      let(:h_metrics) do
        [
          { advance_width: 1000, lsb: 50 },
          { advance_width: 800, lsb: 100 },
          { advance_width: 1200, lsb: 75 },
        ]
      end
      let(:data) { build_hmtx_table(h_metrics: h_metrics) }
      let(:hmtx) { described_class.read(data) }

      it "parses all metrics correctly" do
        hmtx.parse_with_context(3, 3)

        expect(hmtx.h_metrics.length).to eq(3)
        expect(hmtx.left_side_bearings.length).to eq(0)

        expect(hmtx.h_metrics[0]).to eq(advance_width: 1000, lsb: 50)
        expect(hmtx.h_metrics[1]).to eq(advance_width: 800, lsb: 100)
        expect(hmtx.h_metrics[2]).to eq(advance_width: 1200, lsb: 75)
      end

      it "sets context parameters" do
        hmtx.parse_with_context(3, 3)

        expect(hmtx.number_of_h_metrics).to eq(3)
        expect(hmtx.num_glyphs).to eq(3)
      end
    end

    context "with monospace font (all glyphs share advance width)" do
      let(:h_metrics) { [{ advance_width: 600, lsb: 50 }] }
      let(:left_side_bearings) { [60, 70, 80, 90] }
      let(:data) do
        build_hmtx_table(
          h_metrics: h_metrics,
          left_side_bearings: left_side_bearings,
        )
      end
      let(:hmtx) { described_class.read(data) }

      it "parses single metric and multiple LSBs" do
        hmtx.parse_with_context(1, 5)

        expect(hmtx.h_metrics.length).to eq(1)
        expect(hmtx.left_side_bearings.length).to eq(4)

        expect(hmtx.h_metrics[0]).to eq(advance_width: 600, lsb: 50)
        expect(hmtx.left_side_bearings).to eq([60, 70, 80, 90])
      end
    end

    context "with typical proportional font" do
      let(:h_metrics) do
        [
          { advance_width: 500, lsb: 0 },    # .notdef
          { advance_width: 600, lsb: 50 },   # space
          { advance_width: 800, lsb: 100 },  # A
          { advance_width: 700, lsb: 80 }, # B
        ]
      end
      let(:left_side_bearings) { [90, 85, 95, 100, 105, 110] }
      let(:data) do
        build_hmtx_table(
          h_metrics: h_metrics,
          left_side_bearings: left_side_bearings,
        )
      end
      let(:hmtx) { described_class.read(data) }

      it "parses metrics and additional LSBs" do
        hmtx.parse_with_context(4, 10)

        expect(hmtx.h_metrics.length).to eq(4)
        expect(hmtx.left_side_bearings.length).to eq(6)
      end
    end

    context "with negative sidebearings" do
      let(:h_metrics) do
        [
          { advance_width: 1000, lsb: -50 },
          { advance_width: 800, lsb: -100 },
        ]
      end
      let(:left_side_bearings) { [-75, -125, -200] }
      let(:data) do
        build_hmtx_table(
          h_metrics: h_metrics,
          left_side_bearings: left_side_bearings,
        )
      end
      let(:hmtx) { described_class.read(data) }

      it "correctly handles negative LSB values" do
        hmtx.parse_with_context(2, 5)

        expect(hmtx.h_metrics[0][:lsb]).to eq(-50)
        expect(hmtx.h_metrics[1][:lsb]).to eq(-100)
        expect(hmtx.left_side_bearings).to eq([-75, -125, -200])
      end
    end

    context "with edge case values" do
      it "handles maximum advance width (65535)" do
        h_metrics = [{ advance_width: 65535, lsb: 0 }]
        data = build_hmtx_table(h_metrics: h_metrics)
        hmtx = described_class.read(data)

        hmtx.parse_with_context(1, 1)
        expect(hmtx.h_metrics[0][:advance_width]).to eq(65535)
      end

      it "handles maximum positive LSB (32767)" do
        h_metrics = [{ advance_width: 1000, lsb: 32767 }]
        data = build_hmtx_table(h_metrics: h_metrics)
        hmtx = described_class.read(data)

        hmtx.parse_with_context(1, 1)
        expect(hmtx.h_metrics[0][:lsb]).to eq(32767)
      end

      it "handles maximum negative LSB (-32768)" do
        h_metrics = [{ advance_width: 1000, lsb: -32768 }]
        data = build_hmtx_table(h_metrics: h_metrics)
        hmtx = described_class.read(data)

        hmtx.parse_with_context(1, 1)
        expect(hmtx.h_metrics[0][:lsb]).to eq(-32768)
      end

      it "handles zero advance width" do
        h_metrics = [{ advance_width: 0, lsb: 0 }]
        data = build_hmtx_table(h_metrics: h_metrics)
        hmtx = described_class.read(data)

        hmtx.parse_with_context(1, 1)
        expect(hmtx.h_metrics[0][:advance_width]).to eq(0)
      end
    end

    context "with invalid context parameters" do
      let(:hmtx) do
        data = build_hmtx_table(h_metrics: [{ advance_width: 1000, lsb: 50 }])
        described_class.read(data)
      end

      it "raises error for nil numberOfHMetrics" do
        expect do
          hmtx.parse_with_context(nil, 10)
        end.to raise_error(ArgumentError, /numberOfHMetrics must be >= 1/)
      end

      it "raises error for zero numberOfHMetrics" do
        expect do
          hmtx.parse_with_context(0, 10)
        end.to raise_error(ArgumentError, /numberOfHMetrics must be >= 1/)
      end

      it "raises error for negative numberOfHMetrics" do
        expect do
          hmtx.parse_with_context(-5, 10)
        end.to raise_error(ArgumentError, /numberOfHMetrics must be >= 1/)
      end

      it "raises error for nil numGlyphs" do
        expect do
          hmtx.parse_with_context(5, nil)
        end.to raise_error(ArgumentError, /numGlyphs must be >= 1/)
      end

      it "raises error for zero numGlyphs" do
        expect do
          hmtx.parse_with_context(5, 0)
        end.to raise_error(ArgumentError, /numGlyphs must be >= 1/)
      end

      it "raises error when numberOfHMetrics > numGlyphs" do
        expect do
          hmtx.parse_with_context(10, 5)
        end.to raise_error(ArgumentError, /cannot exceed numGlyphs/)
      end
    end

    context "with insufficient data" do
      it "raises CorruptedTableError when hMetrics data is incomplete" do
        # Only 3 bytes instead of required 4 for one LongHorMetric
        data = "\x00\x00\x00".b
        hmtx = described_class.read(data)

        expect do
          hmtx.parse_with_context(1, 1)
        end.to raise_error(Fontisan::CorruptedTableError,
                           /Insufficient data.*hMetric/)
      end

      it "raises CorruptedTableError when LSB data is incomplete" do
        # 4 bytes for one hMetric, but missing data for LSBs
        data = build_hmtx_table(h_metrics: [{ advance_width: 1000, lsb: 50 }])
        hmtx = described_class.read(data)

        expect do
          hmtx.parse_with_context(1, 3) # Expects 2 more LSBs
        end.to raise_error(Fontisan::CorruptedTableError,
                           /Insufficient data.*LSB/)
      end
    end
  end

  describe "#metric_for" do
    context "with all unique metrics" do
      let(:h_metrics) do
        [
          { advance_width: 1000, lsb: 50 },
          { advance_width: 800, lsb: 100 },
          { advance_width: 1200, lsb: 75 },
        ]
      end
      let(:data) { build_hmtx_table(h_metrics: h_metrics) }
      let(:hmtx) do
        table = described_class.read(data)
        table.parse_with_context(3, 3)
        table
      end

      it "returns correct metrics for first glyph (glyph_id 0)" do
        metric = hmtx.metric_for(0)
        expect(metric).to eq(advance_width: 1000, lsb: 50)
      end

      it "returns correct metrics for middle glyph" do
        metric = hmtx.metric_for(1)
        expect(metric).to eq(advance_width: 800, lsb: 100)
      end

      it "returns correct metrics for last glyph" do
        metric = hmtx.metric_for(2)
        expect(metric).to eq(advance_width: 1200, lsb: 75)
      end
    end

    context "with shared advance widths (monospace)" do
      let(:h_metrics) { [{ advance_width: 600, lsb: 50 }] }
      let(:left_side_bearings) { [60, 70, 80, 90] }
      let(:data) do
        build_hmtx_table(
          h_metrics: h_metrics,
          left_side_bearings: left_side_bearings,
        )
      end
      let(:hmtx) do
        table = described_class.read(data)
        table.parse_with_context(1, 5)
        table
      end

      it "returns hMetrics entry for glyph 0" do
        metric = hmtx.metric_for(0)
        expect(metric).to eq(advance_width: 600, lsb: 50)
      end

      it "uses last advance width with indexed LSB for glyph 1" do
        metric = hmtx.metric_for(1)
        expect(metric).to eq(advance_width: 600, lsb: 60)
      end

      it "uses last advance width with indexed LSB for glyph 2" do
        metric = hmtx.metric_for(2)
        expect(metric).to eq(advance_width: 600, lsb: 70)
      end

      it "uses last advance width with indexed LSB for glyph 4" do
        metric = hmtx.metric_for(4)
        expect(metric).to eq(advance_width: 600, lsb: 90)
      end
    end

    context "with mixed metrics" do
      let(:h_metrics) do
        [
          { advance_width: 500, lsb: 0 },
          { advance_width: 600, lsb: 50 },
          { advance_width: 800, lsb: 100 },
        ]
      end
      let(:left_side_bearings) { [90, 85, 95, 100] }
      let(:data) do
        build_hmtx_table(
          h_metrics: h_metrics,
          left_side_bearings: left_side_bearings,
        )
      end
      let(:hmtx) do
        table = described_class.read(data)
        table.parse_with_context(3, 7)
        table
      end

      it "returns hMetrics for glyphs < numberOfHMetrics" do
        expect(hmtx.metric_for(0)).to eq(advance_width: 500, lsb: 0)
        expect(hmtx.metric_for(1)).to eq(advance_width: 600, lsb: 50)
        expect(hmtx.metric_for(2)).to eq(advance_width: 800, lsb: 100)
      end

      it "uses last advance with indexed LSB for glyphs >= numberOfHMetrics" do
        expect(hmtx.metric_for(3)).to eq(advance_width: 800, lsb: 90)
        expect(hmtx.metric_for(4)).to eq(advance_width: 800, lsb: 85)
        expect(hmtx.metric_for(5)).to eq(advance_width: 800, lsb: 95)
        expect(hmtx.metric_for(6)).to eq(advance_width: 800, lsb: 100)
      end
    end

    context "with invalid glyph IDs" do
      let(:h_metrics) { [{ advance_width: 1000, lsb: 50 }] }
      let(:hmtx) do
        data = build_hmtx_table(h_metrics: h_metrics)
        table = described_class.read(data)
        table.parse_with_context(1, 1)
        table
      end

      it "returns nil for negative glyph ID" do
        expect(hmtx.metric_for(-1)).to be_nil
      end

      it "returns nil for glyph ID >= numGlyphs" do
        expect(hmtx.metric_for(1)).to be_nil
        expect(hmtx.metric_for(100)).to be_nil
      end
    end

    context "before parsing" do
      let(:hmtx) do
        data = build_hmtx_table(h_metrics: [{ advance_width: 1000, lsb: 50 }])
        described_class.read(data)
      end

      it "raises error if called before parse_with_context" do
        expect do
          hmtx.metric_for(0)
        end.to raise_error(RuntimeError, /not parsed.*parse_with_context/)
      end
    end
  end

  describe "#parsed?" do
    let(:hmtx) do
      data = build_hmtx_table(h_metrics: [{ advance_width: 1000, lsb: 50 }])
      described_class.read(data)
    end

    it "returns false before parsing" do
      expect(hmtx.parsed?).to be false
    end

    it "returns true after parsing" do
      hmtx.parse_with_context(1, 1)
      expect(hmtx.parsed?).to be true
    end
  end

  describe "#expected_min_size" do
    context "with all unique metrics" do
      let(:hmtx) do
        data = build_hmtx_table(
          h_metrics: [
            { advance_width: 1000, lsb: 50 },
            { advance_width: 800, lsb: 100 },
            { advance_width: 1200, lsb: 75 },
          ],
        )
        table = described_class.read(data)
        table.parse_with_context(3, 3)
        table
      end

      it "returns correct size (numberOfHMetrics × 4)" do
        # 3 LongHorMetric × 4 bytes = 12 bytes
        expect(hmtx.expected_min_size).to eq(12)
      end
    end

    context "with shared advance widths" do
      let(:hmtx) do
        data = build_hmtx_table(
          h_metrics: [{ advance_width: 600, lsb: 50 }],
          left_side_bearings: [60, 70, 80, 90],
        )
        table = described_class.read(data)
        table.parse_with_context(1, 5)
        table
      end

      it "returns correct size (hMetrics + LSBs)" do
        # 1 LongHorMetric × 4 bytes + 4 LSBs × 2 bytes = 12 bytes
        expect(hmtx.expected_min_size).to eq(12)
      end
    end

    context "before parsing" do
      let(:hmtx) do
        data = build_hmtx_table(h_metrics: [{ advance_width: 1000, lsb: 50 }])
        described_class.read(data)
      end

      it "returns nil" do
        expect(hmtx.expected_min_size).to be_nil
      end
    end
  end

  describe "integration with real fonts" do
    let(:libertinus_serif_path) do
      font_fixture_path("libertinus", "Libertinus-7.051/static/TTF/LibertinusSerif-Regular.ttf")
    end

    context "when reading from TrueType font" do
      it "successfully parses hmtx table from Libertinus Serif" do
        skip "Font file not available" unless File.exist?(libertinus_serif_path)

        font = Fontisan::TrueTypeFont.from_file(libertinus_serif_path)

        # Get required tables for context
        hhea = font.table("hhea")
        skip "hhea table not found" if hhea.nil?

        maxp = font.table("maxp")
        skip "maxp table not found" if maxp.nil?

        hmtx_data = font.table_data["hmtx"]
        skip "hmtx table not found" if hmtx_data.nil?

        # Parse hmtx with context
        hmtx = described_class.read(hmtx_data)
        hmtx.parse_with_context(hhea.number_of_h_metrics, maxp.num_glyphs)

        # Verify parsing succeeded
        expect(hmtx.parsed?).to be true
        expect(hmtx.h_metrics).not_to be_empty
        expect(hmtx.number_of_h_metrics).to be >= 1
        expect(hmtx.num_glyphs).to be >= 1

        # Test metric_for with .notdef (usually glyph 0)
        notdef_metric = hmtx.metric_for(0)
        expect(notdef_metric).not_to be_nil
        expect(notdef_metric[:advance_width]).to be >= 0
      end
    end

    context "when reading from OpenType/CFF font" do
      let(:libertinus_serif_otf_path) do
        font_fixture_path("libertinus", "Libertinus-7.051/static/OTF/LibertinusSerif-Regular.otf")
      end

      it "successfully parses hmtx table from Libertinus Serif OTF" do
        skip "Font file not available" unless File.exist?(libertinus_serif_otf_path)

        font = Fontisan::OpenTypeFont.from_file(libertinus_serif_otf_path)

        hhea = font.table("hhea")
        skip "hhea table not found" if hhea.nil?

        maxp = font.table("maxp")
        skip "maxp table not found" if maxp.nil?

        hmtx_data = font.table_data["hmtx"]
        skip "hmtx table not found" if hmtx_data.nil?

        hmtx = described_class.read(hmtx_data)
        hmtx.parse_with_context(hhea.number_of_h_metrics, maxp.num_glyphs)

        # CFF fonts also have hmtx tables
        expect(hmtx.parsed?).to be true
        expect(hmtx.number_of_h_metrics).to be >= 1
      end
    end
  end

  describe "behavioral compatibility" do
    # These tests verify compatibility with reference implementations

    it "handles the same way as ttfunk for monospace fonts" do
      # ttfunk optimization: monospace fonts have numberOfHMetrics = 1
      # All glyphs share the same advance width
      h_metrics = [{ advance_width: 600, lsb: 0 }]
      left_side_bearings = Array.new(255, 0)

      data = build_hmtx_table(
        h_metrics: h_metrics,
        left_side_bearings: left_side_bearings,
      )
      hmtx = described_class.read(data)
      hmtx.parse_with_context(1, 256)

      # All glyphs should have advance_width = 600
      (0...256).each do |gid|
        metric = hmtx.metric_for(gid)
        expect(metric[:advance_width]).to eq(600)
      end
    end

    it "handles proportional fonts like ttfunk" do
      # Typical case: multiple metrics, then shared advance width
      h_metrics = (0...128).map do |i|
        { advance_width: 400 + (i * 10), lsb: 50 + i }
      end
      left_side_bearings = Array.new(128) { |i| 200 + i }

      data = build_hmtx_table(
        h_metrics: h_metrics,
        left_side_bearings: left_side_bearings,
      )
      hmtx = described_class.read(data)
      hmtx.parse_with_context(128, 256)

      # First 128 glyphs have unique metrics
      metric_0 = hmtx.metric_for(0)
      expect(metric_0).to eq(advance_width: 400, lsb: 50)

      metric_127 = hmtx.metric_for(127)
      expect(metric_127).to eq(advance_width: 1670, lsb: 177)

      # Remaining glyphs share last advance width
      metric_128 = hmtx.metric_for(128)
      expect(metric_128[:advance_width]).to eq(1670)
      expect(metric_128[:lsb]).to eq(200)

      metric_255 = hmtx.metric_for(255)
      expect(metric_255[:advance_width]).to eq(1670)
      expect(metric_255[:lsb]).to eq(327)
    end
  end
end
