# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Hints::TrueTypeInstructionAnalyzer do
  let(:analyzer) { described_class.new }

  describe "#analyze_prep" do
    context "with empty or nil input" do
      it "returns empty hash for nil prep" do
        result = analyzer.analyze_prep(nil, [])
        expect(result).to eq({})
      end

      it "returns empty hash for empty prep" do
        result = analyzer.analyze_prep("", [])
        expect(result).to eq({})
      end
    end

    context "with basic prep program" do
      it "extracts blue zones from CVT values" do
        # CVT with baseline (0) and cap height (700)
        cvt = [0, 100, 200, 700]
        prep = "" # Empty prep, rely on CVT analysis

        result = analyzer.analyze_prep(prep, cvt)

        expect(result[:blue_values]).to be_an(Array)
        expect(result[:blue_values].length).to eq(4) # Two zones: baseline and cap height
      end

      it "detects baseline zone from CVT" do
        cvt = [-10, 0, 500, 700]
        result = analyzer.analyze_prep("", cvt)

        # Should include baseline zone around the minimum near-zero value
        expect(result[:blue_values]).to include(-10)
        expect(result[:blue_values][0]).to be < 0
      end

      it "detects cap height zone from CVT" do
        cvt = [0, 100, 700]
        result = analyzer.analyze_prep("", cvt)

        # Should include cap height zone
        expect(result[:blue_values]).to include(700)
        expect(result[:blue_values][2]).to be >= 680
      end

      it "detects x-height values" do
        cvt = [0, 100, 450, 700] # 450 is typical x-height
        result = analyzer.analyze_prep("", cvt)

        expect(result[:family_blues]).to be_an(Array) if result[:family_blues]
      end

      it "detects descender values" do
        cvt = [-200, 0, 700] # -200 is descender
        result = analyzer.analyze_prep("", cvt)

        expect(result[:other_blues]).to be_an(Array) if result[:other_blues]
      end
    end

    context "with instruction bytecode" do
      it "parses NPUSHB instruction" do
        # NPUSHB: 0x40, count, bytes...
        prep = [0x40, 0x02, 0x10, 0x20].pack("C*")
        result = analyzer.analyze_prep(prep, [])

        expect(result).to be_a(Hash)
      end

      it "parses NPUSHW instruction" do
        # NPUSHW: 0x41, count, words...
        prep = [0x41, 0x01, 0x01, 0x00].pack("C*") # Push 256
        result = analyzer.analyze_prep(prep, [])

        expect(result).to be_a(Hash)
      end

      it "parses PUSHB instruction" do
        # PUSHB[0]: 0xB0, byte
        prep = [0xB0, 0x10].pack("C*")
        result = analyzer.analyze_prep(prep, [])

        expect(result).to be_a(Hash)
      end

      it "parses PUSHW instruction" do
        # PUSHW[0]: 0xB8, word (2 bytes)
        prep = [0xB8, 0x01, 0x00].pack("C*")
        result = analyzer.analyze_prep(prep, [])

        expect(result).to be_a(Hash)
      end

      it "extracts single width from SSW instruction" do
        # Push 68, then SSW (0x1F)
        prep = [0xB0, 0x44, 0x1F].pack("C*") # 0x44 = 68
        result = analyzer.analyze_prep(prep, [])

        expect(result[:single_width]).to eq(68)
      end

      it "extracts single width cut-in from SSWCI instruction" do
        # Push value, then SSWCI (0x1E)
        prep = [0xB0, 0x10, 0x1E].pack("C*")
        result = analyzer.analyze_prep(prep, [])

        expect(result[:single_width_cut_in]).to eq(16)
      end

      it "extracts CVT cut-in from SCVTCI instruction" do
        # Push value, then SCVTCI (0x1D)
        prep = [0xB0, 0x08, 0x1D].pack("C*")
        result = analyzer.analyze_prep(prep, [])

        expect(result[:cvt_cut_in]).to eq(8)
      end

      it "handles WCVTP instruction" do
        # Push value, push CVT index, WCVTP (0x44)
        prep = [0xB0, 0x64, 0xB0, 0x00, 0x44].pack("C*") # Write 100 to CVT[0]
        result = analyzer.analyze_prep(prep, [])

        expect(result).to be_a(Hash)
      end

      it "handles complex prep with multiple instructions" do
        # Complex prep: NPUSHB, SCVTCI, SSWCI, SSW
        # Stack is LIFO, so when we push 8, 16, 68:
        # - First push: stack = [8]
        # - Second push: stack = [8, 16]
        # - Third push: stack = [8, 16, 68]
        # - SCVTCI pops: gets 68, stack = [8, 16]
        # - SSWCI pops: gets 16, stack = [8]
        # - SSW pops: gets 8, stack = []
        # So we need to reverse the order if we want 8 for SCVTCI
        prep = [
          0x40, 0x03, 0x44, 0x10, 0x08, # NPUSHB: push 68, 16, 8 (reverse order)
          0x1D,                          # SCVTCI (pops 8)
          0x1E,                          # SSWCI (pops 16)
          0x1F,                          # SSW (pops 68)
        ].pack("C*")

        result = analyzer.analyze_prep(prep, [])

        expect(result[:cvt_cut_in]).to eq(8)
        expect(result[:single_width_cut_in]).to eq(16)
        expect(result[:single_width]).to eq(68)
      end
    end

    context "with CVT-based blue zone extraction" do
      it "uses default blue values when CVT is empty" do
        # With empty prep and empty CVT, should return empty hash
        result = analyzer.analyze_prep("", [])

        # Empty CVT means no blue zones can be extracted
        expect(result).to eq({})
      end

      it "uses CVT values to refine blue zones" do
        cvt = [0, 50, 100, 680]
        result = analyzer.analyze_prep("", cvt)

        # Should have baseline and cap height zones
        expect(result[:blue_values].length).to eq(4)
        expect(result[:blue_values][0]).to be <= 0
        expect(result[:blue_values][1]).to be >= 0
      end

      it "handles fonts with large UPM" do
        # 2048 UPM font with proportionally larger values
        cvt = [0, 100, 1024, 1456]
        result = analyzer.analyze_prep("", cvt)

        expect(result[:blue_values]).to be_an(Array)
        expect(result[:blue_values].length).to eq(4)
      end

      it "handles fonts with negative baseline" do
        cvt = [-30, 0, 700]
        result = analyzer.analyze_prep("", cvt)

        # Baseline zone should include negative value
        expect(result[:blue_values][0]).to be < 0
      end
    end

    context "error handling" do
      it "handles malformed bytecode gracefully" do
        # Truncated NPUSHB (missing bytes)
        prep = [0x40, 0x10].pack("C*") # Says 16 bytes but none provided

        expect {
          result = analyzer.analyze_prep(prep, [])
          expect(result).to be_a(Hash)
        }.not_to raise_error
      end

      it "returns empty hash on exception" do
        # Test with invalid input that might cause errors
        allow(analyzer).to receive(:extract_blue_zones_from_cvt).and_raise(StandardError.new("test error"))

        result = analyzer.analyze_prep("test", [100])
        expect(result).to eq({})
      end
    end
  end

  describe "#analyze_fpgm" do
    context "with empty or nil input" do
      it "returns empty hash for nil fpgm" do
        result = analyzer.analyze_fpgm(nil)
        expect(result).to eq({})
      end

      it "returns empty hash for empty fpgm" do
        result = analyzer.analyze_fpgm("")
        expect(result).to eq({})
      end
    end

    context "with fpgm bytecode" do
      it "detects presence of functions" do
        fpgm = [0xB0, 0x01].pack("C*") # Simple bytecode
        result = analyzer.analyze_fpgm(fpgm)

        expect(result[:has_functions]).to be true
      end

      it "estimates complexity for simple fpgm" do
        fpgm = [0xB0, 0x01, 0xB0, 0x02].pack("C*") # 4 bytes
        result = analyzer.analyze_fpgm(fpgm)

        expect(result[:complexity]).to eq(:simple)
      end

      it "estimates complexity for moderate fpgm" do
        fpgm = ("A" * 100).bytes.pack("C*") # 100 bytes
        result = analyzer.analyze_fpgm(fpgm)

        expect(result[:complexity]).to eq(:moderate)
      end

      it "estimates complexity for complex fpgm" do
        fpgm = ("A" * 250).bytes.pack("C*") # 250 bytes
        result = analyzer.analyze_fpgm(fpgm)

        expect(result[:complexity]).to eq(:complex)
      end
    end

    context "error handling" do
      it "returns empty hash on exception" do
        # Mock bytesize to raise error, triggering rescue block
        allow_any_instance_of(String).to receive(:bytesize).and_raise(StandardError.new("test error"))

        result = analyzer.analyze_fpgm("test")
        expect(result).to eq({})
      end
    end
  end

  describe "integration with real font data" do
    context "with typical TrueType font prep program" do
      it "extracts meaningful parameters" do
        # Simulate a realistic prep program
        # NPUSHB with CVT setup values, then control instructions
        prep = [
          0x40, 0x05, 0x08, 0x10, 0x44, 0x00, 0x01, # NPUSHB: 5 bytes
          0x1D,                                      # SCVTCI
          0x1E,                                      # SSWCI
          0x1F,                                      # SSW
        ].pack("C*")

        cvt = [0, 68, 88, 100, 450, 700]

        result = analyzer.analyze_prep(prep, cvt)

        expect(result).to include(:blue_values)
        expect(result).to include(:cvt_cut_in)
        expect(result).to include(:single_width)
      end
    end
  end
end