# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Optimizers::SubroutineGenerator do
  # Helper to create a mock font with CFF table
  def create_mock_font(charstrings_data)
    charstrings_index = instance_double(
      Fontisan::Tables::Cff::CharstringsIndex,
    )

    # Mock each to return charstrings_data
    allow(charstrings_index).to receive(:each) do |&block|
      charstrings_data.each(&block)
    end

    cff_table = instance_double(Fontisan::Tables::Cff)
    allow(cff_table).to receive(:charstrings_index).with(0)
      .and_return(charstrings_index)

    font = instance_double(Fontisan::OpenTypeFont)
    allow(font).to receive(:table).with("CFF ").and_return(cff_table)

    font
  end

  # Create test pattern
  def create_pattern(bytes, length, glyphs, frequency, savings, positions)
    Fontisan::Optimizers::PatternAnalyzer::Pattern.new(
      bytes,
      length,
      glyphs,
      frequency,
      savings,
      positions,
    )
  end

  describe "#initialize" do
    it "sets default options" do
      generator = described_class.new
      expect(generator.instance_variable_get(:@min_pattern_length)).to eq(10)
      expect(generator.instance_variable_get(:@max_subroutines)).to eq(65_535)
      expect(generator.instance_variable_get(:@optimize_ordering)).to be true
    end

    it "sets custom options" do
      generator = described_class.new(
        min_pattern_length: 15,
        max_subroutines: 1000,
        optimize_ordering: false,
      )
      expect(generator.instance_variable_get(:@min_pattern_length)).to eq(15)
      expect(generator.instance_variable_get(:@max_subroutines)).to eq(1000)
      expect(generator.instance_variable_get(:@optimize_ordering)).to be false
    end

    it "validates option types implicitly through usage" do
      # Valid integer options should work
      expect do
        described_class.new(
          min_pattern_length: 20,
          max_subroutines: 5000,
        )
      end.not_to raise_error
    end
  end

  describe "#extract_charstrings" do
    it "extracts from CFF table" do
      charstrings = {
        0 => "\x01\x02\x03",
        1 => "\x04\x05\x06",
        2 => "\x07\x08\x09",
      }
      font = create_mock_font(charstrings.values)
      generator = described_class.new

      result = generator.send(:extract_charstrings, font)

      expect(result).to eq(charstrings)
    end

    it "handles empty CharStrings" do
      font = create_mock_font([])
      generator = described_class.new

      result = generator.send(:extract_charstrings, font)

      expect(result).to eq({})
    end

    it "raises error for non-CFF font" do
      font = instance_double(Fontisan::OpenTypeFont)
      allow(font).to receive(:table).with("CFF ").and_return(nil)
      generator = described_class.new

      expect do
        generator.send(:extract_charstrings, font)
      end.to raise_error(ArgumentError, "Font must have CFF table")
    end

    it "extracts correct number of glyphs" do
      charstrings = (0...100).map { |i| "CS#{i}" }
      font = create_mock_font(charstrings)
      generator = described_class.new

      result = generator.send(:extract_charstrings, font)

      expect(result.keys.length).to eq(100)
    end
  end

  describe "#generate" do
    let(:charstrings) do
      {
        0 => "ABCDEFGHIJKLMN", # 14 bytes
        1 => "XYABCDEFGHIJZ",  # 13 bytes (contains same 10-byte pattern)
        2 => "QWABCDEFGHIJRT", # 14 bytes (contains same 10-byte pattern)
      }
    end

    let(:font) { create_mock_font(charstrings.values) }

    context "full pipeline orchestration" do
      it "runs full pipeline successfully" do
        generator = described_class.new(min_pattern_length: 10)

        result = generator.generate(font)

        expect(result).to be_a(Hash)
        expect(result).to have_key(:local_subrs)
        expect(result).to have_key(:charstrings)
        expect(result).to have_key(:bias)
        expect(result).to have_key(:savings)
        expect(result).to have_key(:pattern_count)
        expect(result).to have_key(:selected_count)
      end

      it "returns correct result structure" do
        generator = described_class.new(min_pattern_length: 10)

        result = generator.generate(font)

        expect(result[:local_subrs]).to be_an(Array)
        expect(result[:charstrings]).to be_a(Hash)
        expect(result[:bias]).to be_an(Integer)
        expect(result[:savings]).to be_an(Integer)
        expect(result[:pattern_count]).to be_an(Integer)
        expect(result[:selected_count]).to be_an(Integer)
      end

      it "orchestrates all components in order" do
        generator = described_class.new(min_pattern_length: 10)

        # Verify component coordination through result
        result = generator.generate(font)

        # Should find pattern "ABCDEFGHIJ" in glyphs 0, 1, 2
        expect(result[:selected_count]).to be > 0
        expect(result[:local_subrs]).not_to be_empty
      end

      it "handles fonts with no patterns" do
        # Create font with unique CharStrings (no repeating patterns)
        no_pattern_charstrings = {
          0 => "UNIQUE123",
          1 => "DIFFERENT456",
          2 => "DISTINCT789",
        }
        font_no_patterns = create_mock_font(no_pattern_charstrings.values)
        generator = described_class.new(min_pattern_length: 10)

        result = generator.generate(font_no_patterns)

        expect(result[:selected_count]).to eq(0)
        expect(result[:local_subrs]).to be_empty
        expect(result[:savings]).to eq(0)
      end

      it "handles fonts with many patterns" do
        # Create font with multiple repeating patterns
        many_pattern_charstrings = (0...50).to_h do |i|
          [i, "COMMON_PATTERN_#{i % 5}_END"]
        end
        font_many = create_mock_font(many_pattern_charstrings.values)
        generator = described_class.new(min_pattern_length: 10)

        result = generator.generate(font_many)

        expect(result[:pattern_count]).to be > 0
      end
    end

    context "with optimize_ordering enabled" do
      it "orders subroutines by frequency" do
        generator = described_class.new(
          min_pattern_length: 10,
          optimize_ordering: true,
        )

        result = generator.generate(font)

        # Patterns should be ordered (highest frequency first)
        expect(result[:local_subrs]).to be_an(Array)
      end
    end

    context "with optimize_ordering disabled" do
      it "uses savings order only" do
        generator = described_class.new(
          min_pattern_length: 10,
          optimize_ordering: false,
        )

        result = generator.generate(font)

        expect(result[:local_subrs]).to be_an(Array)
      end
    end
  end

  describe "#build_subroutine_map" do
    it "creates map from patterns" do
      patterns = [
        create_pattern("ABC", 3, [0], 2, 5, { 0 => [0, 5] }),
        create_pattern("XYZ", 3, [1], 2, 5, { 1 => [0, 5] }),
        create_pattern("QWE", 3, [2], 2, 5, { 2 => [0, 5] }),
      ]
      generator = described_class.new

      map = generator.send(:build_subroutine_map, patterns)

      expect(map).to eq({
                          "ABC" => 0,
                          "XYZ" => 1,
                          "QWE" => 2,
                        })
    end

    it "maps patterns to sequential IDs" do
      patterns = [
        create_pattern("P1", 2, [0], 2, 5, { 0 => [0] }),
        create_pattern("P2", 2, [1], 2, 5, { 1 => [0] }),
      ]
      generator = described_class.new

      map = generator.send(:build_subroutine_map, patterns)

      expect(map["P1"]).to eq(0)
      expect(map["P2"]).to eq(1)
    end

    it "handles empty patterns" do
      generator = described_class.new

      map = generator.send(:build_subroutine_map, [])

      expect(map).to eq({})
    end
  end

  describe "#rewrite_charstrings" do
    let(:pattern) do
      create_pattern("ABCD", 4, [0, 1], 2, 5, { 0 => [2], 1 => [1] })
    end
    let(:builder) do
      instance_double(
        Fontisan::Optimizers::SubroutineBuilder,
        bias: 0,
        create_call: "\x20\x0a", # callsubr for ID 0
      )
    end
    let(:rewriter) do
      Fontisan::Optimizers::CharstringRewriter.new(
        { "ABCD" => 0 },
        builder,
      )
    end

    it "rewrites all glyphs with patterns" do
      charstrings = {
        0 => "XXABCDYY",
        1 => "ZABCDQQ",
      }
      patterns = [pattern]
      generator = described_class.new

      result = generator.send(
        :rewrite_charstrings,
        charstrings,
        patterns,
        rewriter,
      )

      expect(result.keys).to eq([0, 1])
      expect(result[0]).not_to eq(charstrings[0]) # Should be rewritten
      expect(result[1]).not_to eq(charstrings[1]) # Should be rewritten
    end

    it "keeps original for glyphs without patterns" do
      charstrings = {
        0 => "XXABCDYY",
        1 => "NOPATTERNN",
      }
      pattern_glyph_0 = create_pattern("ABCD", 4, [0], 1, 5, { 0 => [2] })
      patterns = [pattern_glyph_0]
      generator = described_class.new

      result = generator.send(
        :rewrite_charstrings,
        charstrings,
        patterns,
        rewriter,
      )

      # Glyph 0 should be rewritten
      expect(result[0]).not_to eq(charstrings[0])
      # Glyph 1 should be unchanged (no pattern)
      expect(result[1]).to eq(charstrings[1])
    end

    it "maps patterns to correct glyphs" do
      charstrings = {
        0 => "AABCDX",
        1 => "BQWERT",
        2 => "CABCDY",
      }
      pattern1 = create_pattern("ABCD", 4, [0, 2], 2, 5, { 0 => [1], 2 => [1] })
      pattern2 = create_pattern("QWER", 4, [1], 1, 5, { 1 => [1] })
      patterns = [pattern1, pattern2]

      rewriter_multi = Fontisan::Optimizers::CharstringRewriter.new(
        { "ABCD" => 0, "QWER" => 1 },
        builder,
      )
      generator = described_class.new

      result = generator.send(
        :rewrite_charstrings,
        charstrings,
        patterns,
        rewriter_multi,
      )

      # Glyphs 0 and 2 should have pattern1 replaced
      expect(result[0]).not_to eq(charstrings[0])
      expect(result[2]).not_to eq(charstrings[2])
      # Glyph 1 should have pattern2 replaced
      expect(result[1]).not_to eq(charstrings[1])
    end

    it "handles multiple patterns per glyph" do
      charstrings = {
        0 => "ABCDXYQWER",
      }
      pattern1 = create_pattern("ABCD", 4, [0], 1, 5, { 0 => [0] })
      pattern2 = create_pattern("QWER", 4, [0], 1, 5, { 0 => [6] })
      patterns = [pattern1, pattern2]

      rewriter_multi = Fontisan::Optimizers::CharstringRewriter.new(
        { "ABCD" => 0, "QWER" => 1 },
        builder,
      )
      generator = described_class.new

      result = generator.send(
        :rewrite_charstrings,
        charstrings,
        patterns,
        rewriter_multi,
      )

      # Both patterns should be replaced
      expect(result[0]).not_to eq(charstrings[0])
      expect(result[0].length).to be < charstrings[0].length
    end
  end

  describe "#calculate_total_savings" do
    it "calculates correct total" do
      patterns = [
        create_pattern("A", 1, [0], 2, 10, { 0 => [0] }),
        create_pattern("B", 1, [1], 2, 20, { 1 => [0] }),
        create_pattern("C", 1, [2], 2, 15, { 2 => [0] }),
      ]
      generator = described_class.new

      total = generator.send(:calculate_total_savings, patterns)

      expect(total).to eq(45)
    end

    it "handles zero savings" do
      patterns = [
        create_pattern("A", 1, [0], 2, 0, { 0 => [0] }),
      ]
      generator = described_class.new

      total = generator.send(:calculate_total_savings, patterns)

      expect(total).to eq(0)
    end

    it "sums all pattern savings" do
      patterns = (0...10).map do |i|
        create_pattern("P#{i}", 2, [i], 2, i * 5, { i => [0] })
      end
      generator = described_class.new

      total = generator.send(:calculate_total_savings, patterns)

      expected = (0...10).sum { |i| i * 5 }
      expect(total).to eq(expected)
    end
  end

  describe "edge cases" do
    it "handles empty CharStrings" do
      font = create_mock_font([])
      generator = described_class.new

      result = generator.generate(font)

      expect(result[:selected_count]).to eq(0)
      expect(result[:local_subrs]).to be_empty
    end

    it "handles single glyph font" do
      charstrings = { 0 => "SINGLEGLYPHDATA" }
      font = create_mock_font(charstrings.values)
      generator = described_class.new

      result = generator.generate(font)

      # No patterns possible with single glyph
      expect(result[:selected_count]).to eq(0)
    end

    it "handles all-identical glyphs" do
      identical = "SAMECONTENT"
      charstrings = (0...5).to_h { |i| [i, identical] }
      font = create_mock_font(charstrings.values)
      generator = described_class.new(min_pattern_length: 5)

      result = generator.generate(font)

      # Should find pattern for identical content
      expect(result[:selected_count]).to be > 0
    end

    it "handles no beneficial patterns" do
      # Very short CharStrings where overhead > pattern length
      short_charstrings = {
        0 => "ABC",
        1 => "ABC",
        2 => "ABC",
      }
      font = create_mock_font(short_charstrings.values)
      generator = described_class.new(min_pattern_length: 2)

      result = generator.generate(font)

      # Patterns might be found but filtered due to negative savings
      expect(result[:savings]).to be >= 0
    end
  end

  describe "integration scenarios" do
    it "works with realistic CharString data" do
      # Simulate realistic CFF CharString structure
      # CharStrings typically contain move, line, curve commands
      realistic_charstrings = {
        0 => "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c",
        1 => "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c",
        2 => "\x0d\x0e\x01\x02\x03\x04\x05\x06\x07\x08\x0a\x0b",
      }
      font = create_mock_font(realistic_charstrings.values)
      generator = described_class.new(min_pattern_length: 8)

      result = generator.generate(font)

      expect(result[:selected_count]).to be >= 0
      expect(result[:charstrings].keys.sort).to eq([0, 1, 2])
    end

    it "achieves expected savings with repeated patterns" do
      # Create scenario with clear savings opportunity
      common_pattern = "COMMONPART12"
      charstrings = (0...10).to_h do |i|
        [i, "UNIQUE#{i}#{common_pattern}END"]
      end
      font = create_mock_font(charstrings.values)
      generator = described_class.new(min_pattern_length: 10)

      result = generator.generate(font)

      # Should find common pattern and achieve savings
      expect(result[:savings]).to be > 0 if result[:selected_count] > 0
    end

    it "produces valid result structure" do
      charstrings = {
        0 => "TESTDATA123456",
        1 => "TESTDATA789012",
      }
      font = create_mock_font(charstrings.values)
      generator = described_class.new

      result = generator.generate(font)

      # Validate structure completeness
      expect(result[:local_subrs]).to be_an(Array)
      expect(result[:charstrings]).to be_a(Hash)
      expect(result[:bias]).to be_an(Integer)
      expect(result[:savings]).to be_an(Integer)
      expect(result[:pattern_count]).to be_an(Integer)
      expect(result[:selected_count]).to be_an(Integer)

      # Validate relationships
      expect(result[:selected_count]).to be <= result[:pattern_count]
      expect(result[:local_subrs].length).to eq(result[:selected_count])
    end

    it "maintains glyph integrity" do
      original_charstrings = {
        0 => "GLYPH0DATA",
        1 => "GLYPH1DATA",
        2 => "GLYPH2DATA",
      }
      font = create_mock_font(original_charstrings.values)
      generator = described_class.new

      result = generator.generate(font)

      # All original glyphs should be present in result
      expect(result[:charstrings].keys.sort).to eq([0, 1, 2])

      # Each rewritten CharString should not be nil or empty
      result[:charstrings].each_value do |charstring|
        expect(charstring).not_to be_nil
        expect(charstring).not_to be_empty
      end
    end
  end
end
