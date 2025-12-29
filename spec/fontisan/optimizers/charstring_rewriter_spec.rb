# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Optimizers::CharstringRewriter do
  let(:pattern1) do
    Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
      "ABCDEFGHIJ", # 10 bytes
      10,
      [0, 1, 2],
      3,
      18,
      { 0 => [0], 1 => [5], 2 => [10] },
    )
  end

  let(:pattern2) do
    Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
      "XYZ", # 3 bytes
      3,
      [0, 1],
      2,
      0,
      { 0 => [10], 1 => [8] },
    )
  end

  let(:patterns) { [pattern1, pattern2] }
  let(:builder) do
    builder = Fontisan::Optimizers::SubroutineBuilder.new(patterns,
                                                          type: :local)
    builder.build
    builder
  end

  let(:subroutine_map) do
    patterns.each_with_index.to_h { |p, i| [p.bytes, i] }
  end

  let(:rewriter) { described_class.new(subroutine_map, builder) }

  describe "#initialize" do
    it "sets subroutine map" do
      expect(rewriter.instance_variable_get(:@subroutine_map)).to eq(subroutine_map)
    end

    it "sets builder" do
      expect(rewriter.instance_variable_get(:@builder)).to eq(builder)
    end
  end

  describe "#rewrite" do
    context "basic pattern replacement" do
      it "replaces single pattern occurrence" do
        charstring = "AAABCDEFGHIJBBB"
        patterns_for_glyph = [pattern1]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        # Should replace ABCDEFGHIJ with callsubr
        call = builder.create_call(0)
        expect(rewritten).to eq("AA#{call}BBB")
      end

      it "replaces multiple occurrences of same pattern" do
        charstring = "ABCDEFGHIJ--ABCDEFGHIJ"
        patterns_for_glyph = [pattern1]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        # Both occurrences should be replaced
        call = builder.create_call(0)
        expect(rewritten).to eq("#{call}--#{call}")
      end

      it "handles pattern at start of CharString" do
        charstring = "ABCDEFGHIJREST"
        patterns_for_glyph = [pattern1]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        call = builder.create_call(0)
        expect(rewritten).to eq("#{call}REST")
      end

      it "handles pattern at end of CharString" do
        charstring = "STARTABCDEFGHIJ"
        patterns_for_glyph = [pattern1]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        call = builder.create_call(0)
        expect(rewritten).to eq("START#{call}")
      end

      it "handles entire CharString as pattern" do
        charstring = "ABCDEFGHIJ"
        patterns_for_glyph = [pattern1]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        call = builder.create_call(0)
        expect(rewritten).to eq(call)
      end
    end

    context "multiple patterns per glyph" do
      it "replaces multiple different patterns" do
        charstring = "AABCDEFGHIJXYZBB"
        patterns_for_glyph = [pattern1, pattern2]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        call1 = builder.create_call(0)
        call2 = builder.create_call(1)
        expect(rewritten).to eq("A#{call1}#{call2}BB")
      end

      it "handles overlapping pattern positions correctly" do
        # When patterns are replaced from highest position to lowest,
        # offsets remain valid
        charstring = "XYZABCDEFGHIJ"
        patterns_for_glyph = [pattern1, pattern2]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        call1 = builder.create_call(0)
        call2 = builder.create_call(1)
        expect(rewritten).to eq("#{call2}#{call1}")
      end

      it "replaces patterns in correct order" do
        charstring = "ABCDEFGHIJ***XYZ"
        patterns_for_glyph = [pattern1, pattern2]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        call1 = builder.create_call(0)
        call2 = builder.create_call(1)
        expect(rewritten).to eq("#{call1}***#{call2}")
      end
    end

    context "position sorting" do
      it "processes replacements from end to start" do
        # This test verifies that replacements are done in descending order
        # to avoid offset corruption
        charstring = "AAXYZBBABCDEFGHIJCC"
        patterns_for_glyph = [pattern1, pattern2]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        # Pattern2 at position 2, Pattern1 at position 7
        # Should replace pattern1 first (higher position)
        call1 = builder.create_call(0)
        call2 = builder.create_call(1)
        expect(rewritten).to eq("AA#{call2}BB#{call1}CC")
      end

      it "handles multiple patterns at different positions" do
        charstring = "XYZ--ABCDEFGHIJ--XYZ"
        patterns_for_glyph = [pattern1, pattern2]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        call1 = builder.create_call(0)
        call2 = builder.create_call(1)
        # Both XYZ occurrences and one ABCDEFGHIJ should be replaced
        expect(rewritten).to include(call1)
        expect(rewritten).to include(call2)
      end
    end

    context "validation" do
      it "returns true for valid CharString" do
        charstring = "ABCDEFGHIJ\x0b" # Pattern + return
        expect(rewriter.validate(charstring)).to be true
      end

      it "returns false for nil CharString" do
        expect(rewriter.validate(nil)).to be false
      end

      it "returns false for empty CharString" do
        expect(rewriter.validate("")).to be false
      end
    end

    context "edge cases" do
      it "handles empty patterns array" do
        charstring = "ABCDEFGHIJ"
        rewritten = rewriter.rewrite(charstring, [])

        # No patterns to replace, should return original
        expect(rewritten).to eq(charstring)
      end

      it "handles pattern not in subroutine map" do
        unknown_pattern = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "UNKNOWN",
          7,
          [0],
          1,
          0,
          { 0 => [0] },
        )

        charstring = "UNKNOWN"
        rewritten = rewriter.rewrite(charstring, [unknown_pattern])

        # Pattern not in map, should not be replaced
        expect(rewritten).to eq(charstring)
      end

      it "handles binary CharString data" do
        binary_pattern = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "\x00\x01\x02",
          3,
          [0],
          1,
          0,
          { 0 => [0] },
        )

        map = { "\x00\x01\x02" => 0 }
        patterns = [binary_pattern]
        builder_binary = Fontisan::Optimizers::SubroutineBuilder.new(patterns)
        builder_binary.build
        rewriter_binary = described_class.new(map, builder_binary)

        charstring = "PREFIX\x00\x01\x02SUFFIX"
        rewritten = rewriter_binary.rewrite(charstring, [binary_pattern])

        call = builder_binary.create_call(0)
        expect(rewritten).to eq("PREFIX#{call}SUFFIX")
      end

      it "handles CharString with no matching patterns" do
        charstring = "NOMATCH"
        patterns_for_glyph = [pattern1]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        # No pattern found, should return original
        expect(rewritten).to eq(charstring)
      end
    end

    describe "#remove_overlaps" do
      let(:high_savings_pattern) do
        Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "HIGH", 4, [0], 5, 50, { 0 => [5] }, false
        )
      end

      let(:medium_savings_pattern) do
        Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "MEDIUM", 6, [0], 3, 30, { 0 => [7] }, false
        )
      end

      let(:low_savings_pattern) do
        Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "LOW", 3, [0], 2, 10, { 0 => [10] }, false
        )
      end

      it "removes overlapping replacements" do
        replacements = [
          [5, high_savings_pattern],   # Position 5-8, savings 50
          [7, medium_savings_pattern], # Position 7-12 (overlaps with high)
        ]

        result = rewriter.send(:remove_overlaps, replacements)

        # Should keep only the high savings pattern
        expect(result.length).to eq(1)
        expect(result[0][1]).to eq(high_savings_pattern)
      end

      it "keeps non-overlapping replacements" do
        replacements = [
          [5, high_savings_pattern], # Position 5-8
          [15, medium_savings_pattern], # Position 15-20 (no overlap)
        ]

        result = rewriter.send(:remove_overlaps, replacements)

        # Should keep both since they don't overlap
        expect(result.length).to eq(2)
        expect(result.map do |r|
          r[1]
        end).to contain_exactly(high_savings_pattern, medium_savings_pattern)
      end

      it "handles multiple overlaps by keeping highest savings" do
        replacements = [
          [5, high_savings_pattern],    # Position 5-8, savings 50
          [7, medium_savings_pattern],  # Position 7-12, savings 30 (overlaps)
          [8, low_savings_pattern],     # Position 8-10, savings 10 (overlaps)
        ]

        result = rewriter.send(:remove_overlaps, replacements)

        # Should keep only high_savings_pattern
        expect(result.length).to eq(1)
        expect(result[0][1]).to eq(high_savings_pattern)
      end

      it "handles chain of non-overlapping patterns" do
        replacements = [
          [0, high_savings_pattern],    # Position 0-3
          [5, medium_savings_pattern],  # Position 5-10
          [15, low_savings_pattern],    # Position 15-17
        ]

        result = rewriter.send(:remove_overlaps, replacements)

        # All should be kept since they don't overlap
        expect(result.length).to eq(3)
      end

      it "prefers later pattern when both have same savings" do
        pattern_a = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "SAME", 4, [0], 3, 25, { 0 => [5] }, false
        )
        pattern_b = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "SAME", 4, [0], 3, 25, { 0 => [7] }, false
        )

        replacements = [
          [5, pattern_a],  # Position 5-8, savings 25
          [7, pattern_b],  # Position 7-10, savings 25 (overlaps)
        ]

        result = rewriter.send(:remove_overlaps, replacements)

        # Should keep one of them (the first encountered in sorted order)
        expect(result.length).to eq(1)
      end

      it "handles empty replacements array" do
        result = rewriter.send(:remove_overlaps, [])
        expect(result).to eq([])
      end

      it "handles single replacement" do
        replacements = [[5, high_savings_pattern]]
        result = rewriter.send(:remove_overlaps, replacements)

        expect(result).to eq(replacements)
      end
    end

    context "integration scenarios" do
      it "maintains CharString size reduction" do
        # Realistic scenario: pattern saves bytes
        charstring = "ABCDEFGHIJ" * 5 # 50 bytes
        patterns_for_glyph = [pattern1]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        # Should be significantly smaller
        expect(rewritten.length).to be < charstring.length
      end

      it "works with realistic CFF operators" do
        move_pattern = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "\x15\x16\x15", # rmoveto
          3,
          [0],
          1,
          0,
          { 0 => [0] },
        )

        map = { "\x15\x16\x15" => 0 }
        patterns = [move_pattern]
        builder_cff = Fontisan::Optimizers::SubroutineBuilder.new(patterns)
        builder_cff.build
        rewriter_cff = described_class.new(map, builder_cff)

        charstring = "PREFIX\x15\x16\x15SUFFIX"
        rewritten = rewriter_cff.rewrite(charstring, [move_pattern])

        # Should replace the rmoveto sequence
        expect(rewritten).not_to eq(charstring)
        expect(rewritten).to include("PREFIX")
        expect(rewritten).to include("SUFFIX")
      end

      it "handles complex multi-pattern CharString" do
        # Simulate complex glyph with multiple patterns
        charstring = "STARTABCDEFGHIJMIDDLEXYZABCDEFGHIJEND"
        patterns_for_glyph = [pattern1, pattern2]

        rewritten = rewriter.rewrite(charstring, patterns_for_glyph)

        # Verify all patterns were replaced
        builder.create_call(0)
        builder.create_call(1)

        expect(rewritten).to include("START")
        expect(rewritten).to include("MIDDLE")
        expect(rewritten).to include("END")
        # Original patterns should not appear
        expect(rewritten).not_to include("ABCDEFGHIJ")
        expect(rewritten).not_to include("XYZ")
      end
    end
  end
end
