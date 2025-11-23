# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Optimizers::SubroutineBuilder do
  let(:pattern1) do
    Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
      "ABCDEFGHIJ", # 10 bytes
      10,
      [0, 1, 2],
      3,
      18, # savings
      { 0 => [0], 1 => [5], 2 => [10] },
    )
  end

  let(:pattern2) do
    Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
      "XYZ", # 3 bytes
      3,
      [0, 1],
      2,
      0, # savings
      { 0 => [10], 1 => [8] },
    )
  end

  let(:patterns) { [pattern1, pattern2] }
  let(:builder) { described_class.new(patterns, type: :local) }

  describe "#initialize" do
    it "sets patterns" do
      expect(builder.instance_variable_get(:@patterns)).to eq(patterns)
    end

    it "sets type to local by default" do
      builder = described_class.new(patterns)
      expect(builder.instance_variable_get(:@type)).to eq(:local)
    end

    it "sets type to global when specified" do
      builder = described_class.new(patterns, type: :global)
      expect(builder.instance_variable_get(:@type)).to eq(:global)
    end
  end

  describe "#build" do
    it "returns array of subroutines" do
      subroutines = builder.build
      expect(subroutines).to be_an(Array)
      expect(subroutines.length).to eq(2)
    end

    it "appends return operator to each pattern" do
      subroutines = builder.build

      # First subroutine: pattern1 + return
      expect(subroutines[0]).to eq("ABCDEFGHIJ\x0b")

      # Second subroutine: pattern2 + return
      expect(subroutines[1]).to eq("XYZ\x0b")
    end

    it "maintains pattern order" do
      subroutines = builder.build

      # Order should match input patterns array
      expect(subroutines[0]).to start_with(pattern1.bytes)
      expect(subroutines[1]).to start_with(pattern2.bytes)
    end

    it "handles empty patterns" do
      builder = described_class.new([])
      subroutines = builder.build
      expect(subroutines).to be_empty
    end

    it "handles single pattern" do
      builder = described_class.new([pattern1])
      subroutines = builder.build
      expect(subroutines.length).to eq(1)
      expect(subroutines[0]).to eq("ABCDEFGHIJ\x0b")
    end
  end

  describe "#bias" do
    context "with < 1240 subroutines" do
      it "returns bias of 107" do
        patterns = Array.new(100) { pattern1 }
        builder = described_class.new(patterns)
        builder.build
        expect(builder.bias).to eq(107)
      end

      it "returns 107 for exactly 1239 subroutines" do
        patterns = Array.new(1239) { pattern1 }
        builder = described_class.new(patterns)
        builder.build
        expect(builder.bias).to eq(107)
      end
    end

    context "with 1240 to 33899 subroutines" do
      it "returns bias of 1131" do
        patterns = Array.new(1240) { pattern1 }
        builder = described_class.new(patterns)
        builder.build
        expect(builder.bias).to eq(1131)
      end

      it "returns 1131 for exactly 33899 subroutines" do
        patterns = Array.new(33_899) { pattern1 }
        builder = described_class.new(patterns)
        builder.build
        expect(builder.bias).to eq(1131)
      end
    end

    context "with >= 33900 subroutines" do
      it "returns bias of 32768" do
        patterns = Array.new(33_900) { pattern1 }
        builder = described_class.new(patterns)
        builder.build
        expect(builder.bias).to eq(32_768)
      end

      it "returns 32768 for exactly 65535 subroutines" do
        patterns = Array.new(65_535) { pattern1 }
        builder = described_class.new(patterns)
        builder.build
        expect(builder.bias).to eq(32_768)
      end

      it "returns 32768 for 65536 subroutines" do
        patterns = Array.new(65_536) { pattern1 }
        builder = described_class.new(patterns)
        builder.build
        expect(builder.bias).to eq(32_768)
      end
    end

    it "returns 107 before build is called" do
      expect(builder.bias).to eq(107)
    end
  end

  describe "#create_call" do
    before { builder.build }

    context "with bias 107 (default for < 1240 subroutines)" do
      it "creates callsubr for subroutine 0" do
        # bias=107, so biased_id = 0 - 107 = -107
        # encode_integer(-107) = 32 + (-107) = -75 (as signed byte = 181)
        # callsubr = "\x0a"
        call = builder.create_call(0)
        expect(call.bytes).to eq([181, 10])
      end

      it "creates callsubr for subroutine 1" do
        # biased_id = 1 - 107 = -106
        # encode_integer(-106) = 32 + (-106) = -74 (as signed byte = 182)
        call = builder.create_call(1)
        expect(call.bytes).to eq([182, 10])
      end

      it "creates callsubr for subroutine 107" do
        # biased_id = 107 - 107 = 0
        # encode_integer(0) = 32 + 0 = 32 = "\x20"
        call = builder.create_call(107)
        expect(call.bytes).to eq([32, 10])
      end
    end

    context "with bias 1131 (for 1240-33899 subroutines)" do
      before do
        patterns = Array.new(1240) { pattern1 }
        @builder_with_bias = described_class.new(patterns)
        @builder_with_bias.build
      end

      it "creates callsubr for subroutine 0" do
        # biased_id = 0 - 1131 = -1131
        # encode_integer(-1131) requires 2-byte encoding
        call = @builder_with_bias.create_call(0)
        expect(call[-1]).to eq("\x0a") # callsubr operator
      end

      it "creates callsubr for subroutine 1200" do
        # biased_id = 1200 - 1131 = 69
        # encode_integer(69) = 32 + 69 = 101 = "\x65"
        call = @builder_with_bias.create_call(1200)
        expect(call.bytes).to eq([101, 10])
      end
    end

    it "ends with callsubr operator" do
      call = builder.create_call(0)
      expect(call[-1]).to eq("\x0a")
    end
  end

  describe "CFF integer encoding" do
    before { builder.build }

    context "range 1: -107 to 107 (single byte)" do
      it "encodes biased_id 0 (subroutine 107)" do
        call = builder.create_call(107)
        # bias=107, biased_id = 107 - 107 = 0
        # encode_integer(0) = 32 + 0 = 32 = 0x20
        expect(call.bytes[0]).to eq(32)
      end

      it "encodes biased_id 50 (subroutine 157)" do
        call = builder.create_call(157)
        # bias=107, biased_id = 157 - 107 = 50
        # 32 + 50 = 82
        expect(call.bytes[0]).to eq(82)
      end

      it "encodes biased_id -50 (subroutine 57)" do
        call = builder.create_call(57)
        # bias=107, biased_id = 57 - 107 = -50
        # 32 + (-50) = -18 (as signed byte = 238)
        expect(call.bytes[0]).to eq(238)
      end

      it "encodes biased_id 107 (subroutine 214)" do
        call = builder.create_call(214)
        # bias=107, biased_id = 214 - 107 = 107
        # 32 + 107 = 139
        expect(call.bytes[0]).to eq(139)
      end

      it "encodes biased_id -107 (subroutine 0)" do
        call = builder.create_call(0)
        # bias=107, biased_id = 0 - 107 = -107
        # 32 + (-107) = -75 (as signed byte = 181)
        expect(call.bytes[0]).to eq(181)
      end
    end

    context "range 2: 108 to 1131 (two bytes)" do
      it "encodes biased_id 108" do
        # Need 1240+ subroutines to get bias=1131
        patterns = Array.new(1240) { pattern1 }
        builder_large = described_class.new(patterns)
        builder_large.build

        # With bias=1131, id=1239 gives biased_id=108
        call = builder_large.create_call(1239)

        # encode_integer(108): b0 = 247, b1 = 0
        expect(call.bytes[0]).to eq(247)
        expect(call.bytes[1]).to eq(0)
      end

      it "encodes biased_id 1131" do
        patterns = Array.new(1240) { pattern1 }
        builder_large = described_class.new(patterns)
        builder_large.build

        # With bias=1131, id=2262 gives biased_id=1131
        call = builder_large.create_call(2262)

        # encode_integer(1131): b0 = 247 + ((1131-108)>>8) = 250
        expect(call.bytes[0]).to be_between(247, 250)
      end
    end

    context "range 3: -1131 to -108 (two bytes)" do
      it "encodes biased_id -108" do
        # With bias=107 and small subroutine count, we can't reach -108
        # Need bias=1131, so id=1023 gives biased_id=-108
        patterns = Array.new(1240) { pattern1 }
        builder_large = described_class.new(patterns)
        builder_large.build

        call = builder_large.create_call(1023)

        # encode_integer(-108): b0 = 251 - ((-108+108)>>8) = 251
        expect(call.bytes[0]).to eq(251)
      end
    end

    context "range 4: -32768 to 32767 (three bytes)" do
      it "encodes biased_id 1132" do
        patterns = Array.new(1240) { pattern1 }
        builder_large = described_class.new(patterns)
        builder_large.build

        # With bias=1131, id=2263 gives biased_id=1132
        call = builder_large.create_call(2263)

        # encode_integer(1132): b0 = 29 (prefix for 3-byte encoding)
        expect(call.bytes[0]).to eq(29)
      end

      it "encodes biased_id -1132" do
        patterns = Array.new(1240) { pattern1 }
        builder_large = described_class.new(patterns)
        builder_large.build

        # With bias=1131, id=-1 gives biased_id=-1132
        # This is not a realistic case, but tests the encoding
        call = builder_large.create_call(-1)

        # encode_integer(-1132): b0 = 29
        expect(call.bytes[0]).to eq(29)
      end

      it "encodes biased_id 32767" do
        patterns = Array.new(33_900) { pattern1 }
        builder_large = described_class.new(patterns)
        builder_large.build

        # With bias=32768, id=65535 gives biased_id=32767
        call = builder_large.create_call(65_535)

        expect(call.bytes[0]).to eq(29)
      end

      it "encodes biased_id -32768" do
        patterns = Array.new(33_900) { pattern1 }
        builder_large = described_class.new(patterns)
        builder_large.build

        # With bias=32768, id=0 gives biased_id=-32768
        call = builder_large.create_call(0)
        expect(call.bytes[0]).to eq(29)
      end
    end

    context "range 5: larger numbers (five bytes)" do
      it "encodes biased_id 32768" do
        patterns = Array.new(33_900) { pattern1 }
        builder_large = described_class.new(patterns)
        builder_large.build

        # With bias=32768, id=65536 gives biased_id=32768
        call = builder_large.create_call(65_536)

        # encode_integer(32768): b0 = 255 (prefix for 5-byte encoding)
        expect(call.bytes[0]).to eq(255)
      end

      it "encodes biased_id -32769" do
        patterns = Array.new(33_900) { pattern1 }
        builder_large = described_class.new(patterns)
        builder_large.build

        # With bias=32768, id=-1 gives biased_id=-32769
        # This is outside range 4, so uses range 5 (5-byte encoding)
        call = builder_large.create_call(-1)
        expect(call.bytes[0]).to eq(255) # Range 5: 5-byte encoding
      end

      it "encodes biased_id 100000" do
        patterns = Array.new(65_536) { pattern1 }
        builder_large = described_class.new(patterns)
        builder_large.build

        # With bias=32768, id=132768 gives biased_id=100000
        call = builder_large.create_call(132_768)
        expect(call.bytes[0]).to eq(255)
      end
    end
  end

  describe "integration scenarios" do
    context "with realistic patterns" do
      let(:move_pattern) do
        Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "\x15\x16\x15", # rmoveto
          3,
          [0, 1, 2],
          3,
          0,
          { 0 => [0], 1 => [0], 2 => [0] },
        )
      end

      let(:curve_pattern) do
        Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "\x08\x09\x0a\x0b\x0c\x0d\x08", # rrcurveto
          7,
          [0, 1],
          2,
          4,
          { 0 => [3], 1 => [3] },
        )
      end

      it "builds valid CFF subroutines" do
        builder = described_class.new([move_pattern, curve_pattern])
        subroutines = builder.build

        # Each subroutine should end with return (0x0b)
        subroutines.each do |subr|
          expect(subr[-1]).to eq("\x0b")
        end
      end

      it "creates valid callsubr operators" do
        builder = described_class.new([move_pattern, curve_pattern])
        builder.build

        call0 = builder.create_call(0)
        call1 = builder.create_call(1)

        # Both should end with callsubr operator (0x0a)
        expect(call0[-1]).to eq("\x0a")
        expect(call1[-1]).to eq("\x0a")
      end

      it "maintains correct subroutine indexing" do
        builder = described_class.new([move_pattern, curve_pattern])
        subroutines = builder.build

        # Subroutine 0 should be move_pattern
        expect(subroutines[0]).to start_with("\x15\x16\x15")

        # Subroutine 1 should be curve_pattern
        expect(subroutines[1]).to start_with("\x08\x09\x0a\x0b\x0c\x0d\x08")
      end
    end

    context "edge cases" do
      it "handles very large pattern count" do
        patterns = Array.new(100_000) { pattern1 }
        builder = described_class.new(patterns)
        subroutines = builder.build

        expect(subroutines.length).to eq(100_000)
        expect(builder.bias).to eq(32_768)
      end

      it "handles pattern with binary data" do
        binary_pattern = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "\x00\x01\x02\x03\x04",
          5,
          [0, 1],
          2,
          3,
          { 0 => [0], 1 => [0] },
        )

        builder = described_class.new([binary_pattern])
        subroutines = builder.build

        expect(subroutines[0]).to eq("\x00\x01\x02\x03\x04\x0b")
      end

      it "handles empty pattern bytes" do
        empty_pattern = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "",
          0,
          [0, 1],
          2,
          0,
          { 0 => [0], 1 => [0] },
        )

        builder = described_class.new([empty_pattern])
        subroutines = builder.build

        expect(subroutines[0]).to eq("\x0b") # Just return operator
      end
    end
  end
end
