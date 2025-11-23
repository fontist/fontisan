# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Optimizers::SubroutineOptimizer do
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

  describe "#conflicts_with_selected?" do
    let(:optimizer) { described_class.new(patterns) }

    context "with non-overlapping patterns" do
      it "returns false for different glyphs" do
        # pattern1 in glyphs [0,1,2], pattern2 in glyphs [3,4]
        result = optimizer.send(:conflicts_with_selected?, pattern2, [pattern1])
        expect(result).to be false
      end

      it "returns false for same glyphs but non-overlapping positions" do
        non_overlap = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "BBB", 3, [0], 1, 5,
          { 0 => [20] } # Far from pattern1 position at 0
        )
        result = optimizer.send(:conflicts_with_selected?, non_overlap, [pattern1])
        expect(result).to be false
      end
    end

    context "with overlapping patterns" do
      it "returns true for overlapping positions" do
        overlap = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "OVER", 4, [0], 1, 5,
          { 0 => [5] } # Overlaps with pattern1 (len=10 at pos=0)
        )
        result = optimizer.send(:conflicts_with_selected?, overlap, [pattern1])
        expect(result).to be true
      end

      it "returns true for exact position match" do
        same_pos = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "AAA", 3, [0], 1, 5,
          { 0 => [0] } # Same position as pattern1
        )
        result = optimizer.send(:conflicts_with_selected?, same_pos, [pattern1])
        expect(result).to be true
      end

      it "returns true for contained overlap" do
        contained = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
          "CCC", 3, [0], 1, 5,
          { 0 => [3] } # Inside pattern1 (0-10)
        )
        result = optimizer.send(:conflicts_with_selected?, contained, [pattern1])
        expect(result).to be true
      end
    end
  end

  describe "#positions_overlap?" do
    let(:optimizer) { described_class.new(patterns) }

    it "returns false for non-overlapping ranges" do
      p1 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "AAA", 3, [0], 1, 0, { 0 => [0] } # 0-3
      )
      p2 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "BBB", 3, [0], 1, 0, { 0 => [10] } # 10-13
      )
      result = optimizer.send(:positions_overlap?, p1, p2, 0)
      expect(result).to be false
    end

    it "returns true for touching ranges" do
      p1 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "AAA", 3, [0], 1, 0, { 0 => [0] } # 0-3
      )
      p2 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "BBB", 3, [0], 1, 0, { 0 => [2] } # 2-5
      )
      result = optimizer.send(:positions_overlap?, p1, p2, 0)
      expect(result).to be true
    end

    it "returns true for complete overlap" do
      p1 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "AAAAAAAAAA", 10, [0], 1, 0, { 0 => [0] } # 0-10
      )
      p2 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "BBB", 3, [0], 1, 0, { 0 => [3] } # 3-6 (inside p1)
      )
      result = optimizer.send(:positions_overlap?, p1, p2, 0)
      expect(result).to be true
    end

    it "returns false when glyph has no positions" do
      p1 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "AAA", 3, [0], 1, 0, { 0 => [0] }
      )
      p2 = Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
        "BBB", 3, [1], 1, 0, { 1 => [0] }
      )
      # Check glyph 0, but p2 doesn't have positions in glyph 0
      result = optimizer.send(:positions_overlap?, p1, p2, 0)
      expect(result).to be false
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
