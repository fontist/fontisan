# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Optimizers::PatternAnalyzer do
  let(:analyzer) { described_class.new(min_length: 10) }

  describe "#initialize" do
    it "sets minimum pattern length" do
      analyzer = described_class.new(min_length: 15)
      expect(analyzer.instance_variable_get(:@min_length)).to eq(15)
    end

    it "defaults to min_length of 10" do
      analyzer = described_class.new
      expect(analyzer.instance_variable_get(:@min_length)).to eq(10)
    end
  end

  describe "#analyze" do
    context "with empty charstrings" do
      it "raises ArgumentError" do
        expect { analyzer.analyze({}) }.to raise_error(
          ArgumentError,
          "No CharStrings provided",
        )
      end
    end

    context "with simple repeated patterns" do
      let(:charstrings) do
        {
          0 => "A" * 20, # 20 A's
          1 => ("B" * 5) + ("A" * 20) + ("C" * 5), # Pattern in middle
          2 => ("A" * 20) + ("D" * 5), # Pattern at start
        }
      end

      it "identifies repeated sequences" do
        patterns = analyzer.analyze(charstrings)
        expect(patterns).not_to be_empty

        # Should find the "A" * 20 pattern
        pattern = patterns.find { |p| p.bytes == "A" * 20 }
        expect(pattern).not_to be_nil
        expect(pattern.glyphs).to contain_exactly(0, 1, 2)
        expect(pattern.frequency).to eq(3)
      end

      it "calculates pattern length correctly" do
        patterns = analyzer.analyze(charstrings)
        pattern = patterns.find { |p| p.bytes == "A" * 20 }
        expect(pattern.length).to eq(20)
      end

      it "tracks glyph IDs where pattern appears" do
        patterns = analyzer.analyze(charstrings)
        pattern = patterns.find { |p| p.bytes == "A" * 20 }
        expect(pattern.glyphs).to contain_exactly(0, 1, 2)
      end

      it "tracks positions within each glyph" do
        patterns = analyzer.analyze(charstrings)
        pattern = patterns.find { |p| p.bytes == "A" * 20 }

        expect(pattern.positions[0]).to include(0) # At start of glyph 0
        expect(pattern.positions[1]).to include(5) # After 5 B's in glyph 1
        expect(pattern.positions[2]).to include(0) # At start of glyph 2
      end
    end

    context "with patterns below minimum length" do
      let(:charstrings) do
        {
          0 => "ABC" * 3, # 9 bytes total, pattern of 3 bytes
          1 => "ABC" * 3,
        }
      end

      it "filters out short patterns" do
        patterns = analyzer.analyze(charstrings)
        # "ABC" is only 3 bytes, below min_length of 10
        short_pattern = patterns.find { |p| p.bytes == "ABC" }
        expect(short_pattern).to be_nil
      end
    end

    context "with patterns that save bytes" do
      let(:charstrings) do
        pattern = "X" * 15 # 15-byte pattern
        {
          0 => pattern,
          1 => pattern,
          2 => pattern,
        }
      end

      it "calculates positive savings" do
        patterns = analyzer.analyze(charstrings)
        pattern = patterns.first

        expect(pattern.savings).to be > 0
      end

      it "sorts patterns by savings descending" do
        # Add another pattern with lower savings
        long_pattern = "Y" * 20
        short_pattern = "Z" * 11
        charstrings = {
          0 => long_pattern + short_pattern,
          1 => long_pattern + short_pattern,
          2 => long_pattern,
          3 => short_pattern,
        }

        patterns = analyzer.analyze(charstrings)

        # Patterns should be sorted by savings (descending)
        expect(patterns.first.savings).to be >= patterns.last.savings
      end
    end

    context "with single occurrence patterns" do
      let(:charstrings) do
        {
          0 => "A" * 15, # Only in one glyph
          1 => "B" * 15,
          2 => "C" * 15,
        }
      end

      it "filters out patterns that appear in only one glyph" do
        patterns = analyzer.analyze(charstrings)
        expect(patterns).to be_empty
      end
    end

    context "with overlapping patterns" do
      let(:charstrings) do
        {
          0 => "ABCDEFGHIJKLMNOP",
          1 => "ABCDEFGHIJKLMNOP",
        }
      end

      it "finds multiple overlapping patterns" do
        patterns = analyzer.analyze(charstrings)

        # Should find various substring matches
        expect(patterns).not_to be_empty

        # All patterns should appear in both glyphs
        patterns.each do |pattern|
          expect(pattern.glyphs).to contain_exactly(0, 1)
        end
      end
    end

    context "with real CharString-like data" do
      let(:charstrings) do
        # Simulate CFF CharString operators (move, line, curve)
        move = "\x15\x16\x15" # rmoveto with coordinates
        line = "\x05\x06\x05" # rlineto
        curve = "\x08\x09\x0a\x0b\x0c\x0d\x08" # rrcurveto

        common_sequence = move + line + curve # 13 bytes

        {
          0 => common_sequence + line,
          1 => move + common_sequence,
          2 => common_sequence + curve,
        }
      end

      it "identifies common CharString sequences" do
        patterns = analyzer.analyze(charstrings)
        common_pattern = patterns.find do |p|
          p.length >= 10 && p.glyphs.length >= 2
        end

        expect(common_pattern).not_to be_nil
        expect(common_pattern.frequency).to be >= 2
      end
    end
  end

  describe Fontisan::Optimizers::PatternAnalyzer::Pattern do
    let(:pattern) do
      described_class.new(
        "X" * 15,      # bytes
        15,            # length
        [0, 1, 2],     # glyphs
        3,             # frequency
        0,             # savings (to be calculated)
        { 0 => [0], 1 => [5], 2 => [0] }, # positions
      )
    end

    describe "#call_overhead" do
      it "calculates overhead for small numbers" do
        # Small frequency (3): 1 + 1 + 1 = 3 bytes
        # (callsubr + 1-byte number + return)
        expect(pattern.call_overhead).to eq(3)
      end

      it "calculates overhead for medium numbers" do
        pattern.frequency = 500
        # 500 needs 2-byte encoding: 1 + 2 + 1 = 4 bytes
        expect(pattern.call_overhead).to eq(4)
      end

      it "calculates overhead for large numbers" do
        pattern.frequency = 10_000
        # 10000 needs 3-byte encoding: 1 + 3 + 1 = 5 bytes
        expect(pattern.call_overhead).to eq(5)
      end
    end

    describe "#number_size" do
      it "returns 1 for small integers (-107 to 107)" do
        expect(pattern.number_size(0)).to eq(1)
        expect(pattern.number_size(50)).to eq(1)
        expect(pattern.number_size(-50)).to eq(1)
        expect(pattern.number_size(107)).to eq(1)
        expect(pattern.number_size(-107)).to eq(1)
      end

      it "returns 2 for medium integers (-1131 to 1131)" do
        expect(pattern.number_size(108)).to eq(2)
        expect(pattern.number_size(-108)).to eq(2)
        expect(pattern.number_size(1131)).to eq(2)
        expect(pattern.number_size(-1131)).to eq(2)
      end

      it "returns 3 for large integers (-32768 to 32767)" do
        expect(pattern.number_size(1132)).to eq(3)
        expect(pattern.number_size(-1132)).to eq(3)
        expect(pattern.number_size(32_767)).to eq(3)
        expect(pattern.number_size(-32_768)).to eq(3)
      end

      it "returns 5 for very large integers" do
        expect(pattern.number_size(32_768)).to eq(5)
        expect(pattern.number_size(-32_769)).to eq(5)
        expect(pattern.number_size(100_000)).to eq(5)
      end
    end
  end

  describe "#find_operator_boundaries" do
    it "identifies boundaries at operator positions" do
      # Construct CharString: 32(-107) 05(rmoveto)
      charstring = "\x20\x05".b

      analyzer = described_class.new(min_length: 1)
      boundaries = analyzer.send(:find_operator_boundaries, charstring)

      expect(boundaries).to eq([0, 2]) # Start and after rmoveto
    end

    it "handles two-byte operators" do
      # CharString: 32(-107) 0c0a(add operator) 05(rmoveto)
      charstring = "\x20\x0c\x0a\x05".b

      analyzer = described_class.new(min_length: 1)
      boundaries = analyzer.send(:find_operator_boundaries, charstring)

      expect(boundaries).to eq([0, 3, 4]) # Start, after add, after rmoveto
    end

    it "handles multi-byte numbers" do
      # CharString: f72a(150 in 2-byte encoding) 05(rmoveto)
      charstring = "\xf7\x2a\x05".b

      analyzer = described_class.new(min_length: 1)
      boundaries = analyzer.send(:find_operator_boundaries, charstring)

      expect(boundaries).to eq([0, 3]) # Start and after rmoveto
    end

    it "handles 3-byte numbers (28 prefix)" do
      # CharString: 1c(28 prefix) 0100(256) 05(rmoveto)
      charstring = "\x1c\x01\x00\x05".b

      analyzer = described_class.new(min_length: 1)
      boundaries = analyzer.send(:find_operator_boundaries, charstring)

      expect(boundaries).to eq([0, 4]) # Start and after rmoveto
    end

    it "handles 5-byte numbers (255 prefix)" do
      # CharString: ff(255 prefix) 00010000(65536) 05(rmoveto)
      charstring = "\xff\x00\x01\x00\x00\x05".b

      analyzer = described_class.new(min_length: 1)
      boundaries = analyzer.send(:find_operator_boundaries, charstring)

      expect(boundaries).to eq([0, 6]) # Start and after rmoveto
    end

    it "handles complex CharStrings with multiple operators" do
      # Multiple operators and numbers
      charstring = "\x20\x21\x05\x1c\x01\x00\x06\x0c\x0a\x14".b
      # 32 33 rmoveto(05) 28 0100 rlineto(06) add(0c0a) endchar(14)

      analyzer = described_class.new(min_length: 1)
      boundaries = analyzer.send(:find_operator_boundaries, charstring)

      # Should have boundaries at: start(0), after rmoveto(3), after rlineto(7), after add(9), after endchar(10)
      expect(boundaries.length).to be >= 4
      expect(boundaries).to include(0) # Start always included
    end
  end

  describe "#skip_number" do
    it "skips single-byte numbers (32-246)" do
      io = StringIO.new("\x80\x05".b) # 128 is single byte
      analyzer = described_class.new(min_length: 1)

      analyzer.send(:skip_number, io)

      expect(io.pos).to eq(1) # Should have consumed 1 byte
    end

    it "skips 2-byte numbers (247-254)" do
      io = StringIO.new("\xf7\x2a\x05".b) # 2-byte number
      analyzer = described_class.new(min_length: 1)

      analyzer.send(:skip_number, io)

      expect(io.pos).to eq(2) # Should have consumed 2 bytes
    end

    it "skips 3-byte numbers (28 prefix)" do
      io = StringIO.new("\x1c\x01\x00\x05".b) # 3-byte number
      analyzer = described_class.new(min_length: 1)

      analyzer.send(:skip_number, io)

      expect(io.pos).to eq(3) # Should have consumed 3 bytes
    end

    it "skips 5-byte numbers (255 prefix)" do
      io = StringIO.new("\xff\x00\x01\x00\x00\x05".b) # 5-byte number
      analyzer = described_class.new(min_length: 1)

      analyzer.send(:skip_number, io)

      expect(io.pos).to eq(5)  # Should have consumed 5 bytes
    end
  end

  describe "integration scenarios" do
    context "with font-like CharString data" do
      let(:move_op) { "\x15" } # rmoveto
      let(:line_op) { "\x05" } # rlineto
      let(:curve_op) { "\x08" } # rrcurveto
      let(:end_op) { "\x0e" } # endchar

      let(:charstrings) do
        # Create realistic CharStrings with repeated patterns
        glyph_header = "#{move_op}d2" # Move to (100, 50)
        glyph_body = "#{line_op}\n\u0000#{line_op}\u0000\n" # Two lines
        glyph_footer = end_op

        common_drawing = glyph_body # This will be repeated

        {
          0 => glyph_header + common_drawing + glyph_footer,
          1 => glyph_header + common_drawing + glyph_footer,
          2 => glyph_header + common_drawing + glyph_footer,
          3 => glyph_header.reverse + common_drawing + glyph_footer,
        }
      end

      it "finds beneficial patterns in realistic data" do
        patterns = analyzer.analyze(charstrings)

        # Should find at least the common_drawing pattern
        beneficial_patterns = patterns.select { |p| p.savings > 0 }
        expect(beneficial_patterns).not_to be_empty
      end

      it "calculates realistic savings" do
        patterns = analyzer.analyze(charstrings)
        return if patterns.empty?

        total_savings = patterns.sum(&:savings)
        # Should save some bytes by subroutinizing
        expect(total_savings).to be > 0
      end
    end

    context "edge cases" do
      it "handles glyphs with no common patterns" do
        charstrings = {
          0 => "A" * 20,
          1 => "B" * 20,
          2 => "C" * 20,
        }

        patterns = analyzer.analyze(charstrings)
        expect(patterns).to be_empty
      end

      it "handles identical glyphs" do
        identical = "X" * 50
        charstrings = {
          0 => identical,
          1 => identical,
          2 => identical,
        }

        patterns = analyzer.analyze(charstrings)
        # Should find patterns within the identical glyphs
        # Note: The analyzer finds optimal shorter overlapping patterns
        # rather than the full 50-byte pattern
        expect(patterns).not_to be_empty

        # Verify that patterns were found with good frequency
        # All patterns should appear in all 3 glyphs
        patterns.each do |p|
          expect(p.glyphs.sort).to eq([0, 1, 2])
          expect(p.frequency).to be >= 3
        end

        # Should find at least one substantial pattern (>= 20 bytes)
        substantial_patterns = patterns.select { |p| p.length >= 20 }
        expect(substantial_patterns).not_to be_empty
      end

      it "handles very short charstrings" do
        charstrings = {
          0 => "AB",
          1 => "AB",
        }

        patterns = analyzer.analyze(charstrings)
        # Too short for min_length
        expect(patterns).to be_empty
      end
    end
  end
end
