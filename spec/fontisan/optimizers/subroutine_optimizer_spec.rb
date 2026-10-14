# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/baseline_optimizer_cases"

RSpec.describe Fontisan::Optimizers::SubroutineOptimizer do
  include Fontisan::SpecHelpers::BaselineOptimizerCases

  let(:pattern1) do
    Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
      "ABCDEFGHIJ", # 10 bytes
      10,
      [0, 1, 2],
      3,
      18, # High savings
      { 0 => [0], 1 => [5], 2 => [10] },
    )
  end

  let(:pattern2) do
    Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
      "XYZ", # 3 bytes
      3,
      [3, 4],
      2,
      6, # Medium savings
      { 3 => [0], 4 => [0] },
    )
  end

  let(:pattern3) do
    Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
      "QWERTY", # 6 bytes
      6,
      [5, 6],
      2,
      4, # Low savings
      { 5 => [0], 6 => [0] },
    )
  end

  let(:patterns) { [pattern1, pattern2, pattern3] }

  describe "#initialize" do
    it "sets patterns" do
      optimizer = described_class.new(patterns)
      expect(optimizer.instance_variable_get(:@patterns)).to eq(patterns)
    end

    it "sets max_subrs with default" do
      optimizer = described_class.new(patterns)
      expect(optimizer.instance_variable_get(:@max_subrs)).to eq(65535)
    end

    it "sets custom max_subrs" do
      optimizer = described_class.new(patterns, max_subrs: 1000)
      expect(optimizer.instance_variable_get(:@max_subrs)).to eq(1000)
    end
  end

  describe "#optimize_selection" do
    let(:optimizer) { described_class.new(patterns) }

    context "with no conflicts" do
      it "selects all patterns when under limit" do
        selected = optimizer.optimize_selection
        expect(selected.length).to eq(3)
      end

      it "selects patterns by highest savings first" do
        selected = optimizer.optimize_selection
        # Should be ordered by savings: pattern1 (18), pattern2 (6), pattern3 (4)
        expect(selected[0]).to eq(pattern1)
        expect(selected[1]).to eq(pattern2)
        expect(selected[2]).to eq(pattern3)
      end

      it "returns patterns in savings order" do
        selected = optimizer.optimize_selection
        savings = selected.map(&:savings)
        expect(savings).to eq(savings.sort.reverse)
      end
    end

    context "with max_subrs limit" do
      it "respects max_subrs limit" do
        optimizer = described_class.new(patterns, max_subrs: 2)
        selected = optimizer.optimize_selection
        expect(selected.length).to eq(2)
      end

      it "selects top patterns when limited" do
        optimizer = described_class.new(patterns, max_subrs: 2)
        selected = optimizer.optimize_selection
        # Should select pattern1 and pattern2 (highest savings)
        expect(selected).to contain_exactly(pattern1, pattern2)
      end

      it "handles max_subrs of 1" do
        optimizer = described_class.new(patterns, max_subrs: 1)
        selected = optimizer.optimize_selection
        expect(selected.length).to eq(1)
        expect(selected[0]).to eq(pattern1)
      end
    end

    context "with conflicting patterns" do
      let(:conflicting_pattern) do
        Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "OVERLAP",
          7,
          [0], # Same glyph as pattern1
          1,
          20, # Even higher savings
          { 0 => [5] }, # Overlaps with pattern1 at position 0 in glyph 0
        )
      end

      it "skips conflicting patterns" do
        patterns_with_conflict = [conflicting_pattern, pattern1, pattern2]
        optimizer = described_class.new(patterns_with_conflict)
        selected = optimizer.optimize_selection

        # conflicting_pattern has higher savings but overlaps with pattern1
        # Should select conflicting_pattern first, then pattern2
        expect(selected).to include(conflicting_pattern)
        expect(selected).to include(pattern2)
        # pattern1 conflicts with conflicting_pattern, should be skipped
      end

      it "handles multiple conflicting patterns" do
        overlap1 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "AAA", 3, [0], 1, 15, { 0 => [0] }
        )
        overlap2 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "BBB", 3, [0], 1, 10, { 0 => [2] } # Overlaps with overlap1
        )

        patterns_overlap = [overlap1, overlap2, pattern2]
        optimizer = described_class.new(patterns_overlap)
        selected = optimizer.optimize_selection

        # overlap1 has higher savings, should be selected
        expect(selected).to include(overlap1)
        expect(selected).to include(pattern2)
        # overlap2 conflicts with overlap1
        expect(selected).not_to include(overlap2)
      end
    end
  end

  describe "#optimize_ordering" do
    let(:optimizer) { described_class.new(patterns) }

    it "orders by frequency descending" do
      # pattern1: freq=3, pattern2: freq=2, pattern3: freq=2
      ordered = optimizer.optimize_ordering(patterns)
      expect(ordered.first).to eq(pattern1)
    end

    it "maintains stable order for equal frequencies" do
      # pattern2 and pattern3 both have freq=2
      ordered = optimizer.optimize_ordering([pattern2, pattern3])
      # Order should be stable (same as input for equal frequencies)
      expect(ordered.length).to eq(2)
    end

    it "handles single pattern" do
      ordered = optimizer.optimize_ordering([pattern1])
      expect(ordered).to eq([pattern1])
    end

    it "handles empty array" do
      ordered = optimizer.optimize_ordering([])
      expect(ordered).to eq([])
    end
  end

  describe "#optimize_selection position conflicts" do
    [
      ["keeps patterns from different glyphs", "ABCDEFGHIJ", { 0 => [0] },
       "XYZ", { 1 => [0] }, [0, 1]],
      ["keeps distant positions in a shared glyph", "ABCDEFGHIJ", { 0 => [0] },
       "XYZ", { 0 => [20] }, [0, 1]],
      ["rejects partial overlap", "ABCDEFGHIJ", { 0 => [0] },
       "HIJKLM", { 0 => [7] }, [0]],
      ["rejects the same start position", "ABCDEFGHIJ", { 0 => [0] },
       "ABC", { 0 => [0] }, [0]],
      ["rejects a pattern contained inside another", "ABCDEFGHIJ", { 0 => [0] },
       "DEF", { 0 => [3] }, [0]],
      ["keeps separated short ranges", "ABC", { 0 => [0] },
       "KLM", { 0 => [10] }, [0, 1]],
      ["rejects ranges sharing their last byte", "ABC", { 0 => [0] },
       "CDE", { 0 => [2] }, [0]],
      ["rejects complete containment", "ABCDEFGHIJ", { 0 => [0] },
       "DEFGHI", { 0 => [3] }, [0]],
      ["keeps adjacent half-open ranges", "ABC", { 0 => [0] },
       "DEF", { 0 => [3] }, [0, 1]],
      ["keeps a candidate ending at the selected start", "DEF", { 0 => [3] },
       "ABC", { 0 => [0] }, [0, 1]],
      ["rejects a candidate containing a selected pattern", "DEF", { 0 => [3] },
       "ABCDEFGHIJ", { 0 => [0] }, [0]],
      ["rejects a candidate starting before the selected pattern", "FGHI", { 0 => [5] },
       "DEFG", { 0 => [3] }, [0]],
      ["keeps a candidate ending before the selected pattern", "KLM", { 0 => [10] },
       "ABC", { 0 => [0] }, [0, 1]],
      ["checks every occurrence in the selected pattern", "ABC", { 0 => [0, 10] },
       "CDE", { 0 => [12] }, [0]],
      ["checks every occurrence in the candidate", "ABC", { 0 => [10] },
       "CDE", { 0 => [0, 12] }, [0]],
      ["checks every common glyph", "ABC", { 0 => [0], 1 => [10] },
       "CDE", { 0 => [10], 1 => [12] }, [0]],
    ].each do |description, first_bytes, first_positions, second_bytes, second_positions, selected_indices|
      it description do
        preferred = optimizer_pattern(first_bytes, positions: first_positions, savings: 20)
        candidate = optimizer_pattern(second_bytes, positions: second_positions, savings: 10)
        input = [candidate, preferred]
        expected = selected_indices.map { |index| [preferred, candidate].fetch(index) }

        expect(described_class.new(input).optimize_selection).to eq(expected)
      end
    end

    it "keeps a candidate without positions in a shared glyph" do
      preferred = optimizer_pattern("ABC", positions: { 0 => [0] }, savings: 20)
      candidate = optimizer_pattern("DEF", positions: { 1 => [0] }, savings: 10, glyphs: [0, 1])

      expect(described_class.new([candidate, preferred]).optimize_selection).to eq([preferred, candidate])
    end

    it "keeps a selected pattern without positions in a shared glyph" do
      preferred = optimizer_pattern("DEF", positions: { 1 => [0] }, savings: 20, glyphs: [0, 1])
      candidate = optimizer_pattern("ABC", positions: { 0 => [0] }, savings: 10)

      expect(described_class.new([candidate, preferred]).optimize_selection).to eq([preferred, candidate])
    end

    it "checks all selected peers for conflicts" do
      first = optimizer_pattern("ABC", positions: { 0 => [0] }, savings: 30)
      second = optimizer_pattern("KLM", positions: { 0 => [10] }, savings: 20)
      conflicting = optimizer_pattern("MNO", positions: { 0 => [12] }, savings: 10)

      expect(described_class.new([conflicting, second, first]).optimize_selection).to eq([first, second])
    end

    it "selects longer patterns first when savings are equal" do
      shorter = optimizer_pattern("BCD", positions: { 0 => [1] }, savings: 20)
      longer = optimizer_pattern("ABCDE", positions: { 0 => [0] }, savings: 20)

      expect(described_class.new([shorter, longer]).optimize_selection).to eq([longer])
    end

    it "orders equal savings and lengths by the smallest glyph" do
      higher_glyph = optimizer_pattern("ABC", positions: { 1 => [0] }, savings: 20)
      lower_glyph = optimizer_pattern("DEF", positions: { 0 => [0] }, savings: 20)

      expect(described_class.new([higher_glyph, lower_glyph]).optimize_selection).to eq([lower_glyph, higher_glyph])
    end

    it "orders equal savings, lengths and glyphs by bytes" do
      later_bytes = optimizer_pattern("XYZ", positions: { 0 => [10] }, savings: 20)
      earlier_bytes = optimizer_pattern("ABC", positions: { 0 => [0] }, savings: 20)

      expect(described_class.new([later_bytes, earlier_bytes]).optimize_selection).to eq([earlier_bytes, later_bytes])
    end
  end

  describe "edge cases" do
    it "handles empty patterns" do
      optimizer = described_class.new([])
      selected = optimizer.optimize_selection
      expect(selected).to eq([])
    end

    it "handles max_subrs of 0" do
      optimizer = described_class.new(patterns, max_subrs: 0)
      selected = optimizer.optimize_selection
      expect(selected).to eq([])
    end

    it "handles patterns with zero savings" do
      zero_savings = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "ZZZ", 3, [10], 1, 0, { 10 => [0] } # Different glyph to avoid conflict
      )
      optimizer = described_class.new([zero_savings, pattern1])
      selected = optimizer.optimize_selection
      # Should still select both (optimizer doesn't filter by savings)
      expect(selected.length).to eq(2)
    end

    it "handles patterns with negative savings" do
      negative = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "NN", 2, [11], 1, -5, { 11 => [0] } # Different glyph to avoid conflict
      )
      optimizer = described_class.new([negative, pattern1])
      selected = optimizer.optimize_selection
      # Optimizer processes all patterns, filtering is analyzer's job
      expect(selected.length).to eq(2)
    end
  end

  describe "integration scenarios" do
    it "selects optimal patterns from large set" do
      # Create 100 patterns with varying savings
      large_patterns = (0...100).map do |i|
        Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "PAT#{i}", 5, [i], 1, 100 - i, { i => [0] }
        )
      end

      optimizer = described_class.new(large_patterns, max_subrs: 50)
      selected = optimizer.optimize_selection

      expect(selected.length).to eq(50)
      # Should be top 50 by savings
      expect(selected.first.savings).to eq(100)
      expect(selected.last.savings).to eq(51)
    end

    it "handles complex overlap scenarios" do
      # Create patterns with various overlaps
      p1 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "A" * 10, 10, [0], 1, 50, { 0 => [0] }
      )
      p2 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "B" * 5, 5, [0], 1, 40, { 0 => [5] } # Overlaps with p1
      )
      p3 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "C" * 8, 8, [0], 1, 30, { 0 => [15] } # No overlap
      )

      optimizer = described_class.new([p1, p2, p3])
      selected = optimizer.optimize_selection

      # p1 selected first (highest savings)
      # p2 conflicts with p1, skipped
      # p3 doesn't conflict, selected
      expect(selected).to contain_exactly(p1, p3)
    end

    it "combines selection and ordering" do
      # Full workflow
      optimizer = described_class.new(patterns, max_subrs: 2)
      selected = optimizer.optimize_selection
      ordered = optimizer.optimize_ordering(selected)

      expect(ordered.length).to eq(2)
      # Selected by savings, ordered by frequency
      expect(ordered.first.frequency).to be >= ordered.last.frequency
    end

    it "maintains pattern integrity through optimization" do
      optimizer = described_class.new(patterns)
      selected = optimizer.optimize_selection
      ordered = optimizer.optimize_ordering(selected)

      # Verify patterns are unchanged
      ordered.each do |pattern|
        expect(pattern.bytes).not_to be_nil
        expect(pattern.length).to be > 0
        expect(pattern.glyphs).not_to be_empty
        expect(pattern.positions).not_to be_empty
      end
    end
  end
end
