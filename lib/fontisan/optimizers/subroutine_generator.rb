# frozen_string_literal: true

module Fontisan
  module Optimizers
    # Main orchestrator for CFF subroutine generation pipeline.
    # Coordinates PatternAnalyzer, SubroutineOptimizer, SubroutineBuilder,
    # and CharstringRewriter to generate optimized subroutines for fonts.
    #
    # The generator processes CharStrings from a CFF font table by:
    # 1. Analyzing patterns across all glyphs
    # 2. Selecting optimal patterns (avoiding conflicts, within limits)
    # 3. Ordering patterns by frequency for efficient encoding
    # 4. Building actual subroutine CharStrings
    # 5. Rewriting original CharStrings with subroutine calls
    #
    # @example Basic usage
    #   generator = SubroutineGenerator.new(min_pattern_length: 10)
    #   result = generator.generate(font)
    #   puts "Generated #{result[:selected_count]} subroutines"
    #   puts "Total savings: #{result[:savings]} bytes"
    #
    # @see docs/SUBROUTINE_ARCHITECTURE.md
    class SubroutineGenerator
      # Default minimum pattern length in bytes
      DEFAULT_MIN_PATTERN_LENGTH = 10

      # Default maximum number of subroutines (CFF limit)
      DEFAULT_MAX_SUBROUTINES = 65_535

      # Initialize generator with options
      # @param options [Hash] configuration options
      # @option options [Integer] :min_pattern_length (10) minimum pattern size
      # @option options [Integer] :max_subroutines (65535) max subroutine count
      # @option options [Boolean] :optimize_ordering (true) enable frequency
      #   ordering
      def initialize(options = {})
        @min_pattern_length = options[:min_pattern_length] ||
          DEFAULT_MIN_PATTERN_LENGTH
        @max_subroutines = options[:max_subroutines] || DEFAULT_MAX_SUBROUTINES
        @optimize_ordering = options[:optimize_ordering] != false
      end

      # Generate subroutines for a font
      #
      # Main entry point for the subroutine generation pipeline. Processes
      # a font's CFF table to create optimized subroutines and rewrite
      # CharStrings.
      #
      # @param font [Fontisan::OpenTypeFont] font to optimize
      # @return [Hash] result containing:
      #   - :local_subrs [Array<String>] subroutine CharStrings
      #   - :charstrings [Hash<Integer, String>] rewritten CharStrings
      #   - :bias [Integer] CFF bias value for subroutines
      #   - :savings [Integer] total bytes saved
      #   - :pattern_count [Integer] total patterns found
      #   - :selected_count [Integer] patterns selected as subroutines
      # @raise [ArgumentError] if font has no CFF table
      def generate(font)
        # 1. Extract CharStrings from CFF table
        charstrings = extract_charstrings(font)

        # Handle empty font gracefully
        if charstrings.empty?
          return {
            local_subrs: [],
            charstrings: {},
            bias: 0,
            savings: 0,
            pattern_count: 0,
            selected_count: 0,
          }
        end

        # 2. Analyze patterns
        analyzer = PatternAnalyzer.new(
          min_length: @min_pattern_length,
          stack_aware: true,
        )
        patterns = analyzer.analyze(charstrings)

        # 3. Optimize selection
        optimizer = SubroutineOptimizer.new(patterns,
                                            max_subrs: @max_subroutines)
        selected_patterns = optimizer.optimize_selection

        # 4. Optimize ordering (if enabled)
        if @optimize_ordering
          selected_patterns = optimizer.optimize_ordering(selected_patterns)
        end

        # 5. Build subroutines
        builder = SubroutineBuilder.new(selected_patterns, type: :local)
        subroutines = builder.build

        # 6. Build subroutine map
        subroutine_map = build_subroutine_map(selected_patterns)

        # 7. Rewrite CharStrings
        rewriter = CharstringRewriter.new(subroutine_map, builder)
        rewritten_charstrings = rewrite_charstrings(
          charstrings,
          selected_patterns,
          rewriter,
        )

        # 8. Return complete result
        {
          local_subrs: subroutines,
          charstrings: rewritten_charstrings,
          bias: builder.bias,
          savings: calculate_total_savings(selected_patterns),
          pattern_count: patterns.length,
          selected_count: selected_patterns.length,
        }
      end

      private

      # Extract CharStrings from CFF table
      #
      # Retrieves raw CharString byte sequences for each glyph from the
      # font's CFF table. The CharStrings INDEX is accessed through the
      # CFF table structure.
      #
      # @param font [Fontisan::OpenTypeFont] font to extract from
      # @return [Hash<Integer, String>] glyph_id => charstring_bytes
      # @raise [ArgumentError] if font has no CFF table
      def extract_charstrings(font)
        cff = font.table("CFF ")
        raise ArgumentError, "Font must have CFF table" unless cff

        charstrings = {}

        # Get CharStrings INDEX for first font (index 0)
        charstrings_index = cff.charstrings_index(0)
        unless charstrings_index
          raise ArgumentError, "Font CFF table has no CharStrings"
        end

        # Extract raw CharString bytes for each glyph
        # Index.each yields raw bytes, we add index manually
        index = 0
        charstrings_index.each do |cs_data|
          charstrings[index] = cs_data
          index += 1
        end

        charstrings
      end

      # Build map from pattern bytes to subroutine ID
      #
      # Creates a lookup table for the rewriter to quickly find which
      # subroutine ID corresponds to each pattern's byte sequence.
      #
      # @param patterns [Array<Pattern>] selected patterns
      # @return [Hash<String, Integer>] pattern_bytes => subroutine_id
      def build_subroutine_map(patterns)
        map = {}
        patterns.each_with_index do |pattern, index|
          map[pattern.bytes] = index
        end
        map
      end

      # Rewrite all CharStrings with subroutine calls
      #
      # Processes each glyph's CharString, replacing pattern occurrences
      # with calls to their corresponding subroutines. Glyphs without
      # applicable patterns are kept unchanged.
      #
      # @param charstrings [Hash<Integer, String>] original CharStrings
      # @param patterns [Array<Pattern>] patterns to use
      # @param rewriter [CharstringRewriter] rewriter instance
      # @return [Hash<Integer, String>] rewritten CharStrings
      def rewrite_charstrings(charstrings, patterns, rewriter)
        rewritten = {}

        charstrings.each do |glyph_id, charstring|
          # Find patterns for this glyph
          glyph_patterns = patterns.select { |p| p.glyphs.include?(glyph_id) }

          rewritten[glyph_id] = if glyph_patterns.empty?
                                  # No patterns, keep original
                                  charstring
                                else
                                  # Rewrite with subroutine calls
                                  rewriter.rewrite(charstring, glyph_patterns)
                                end
        end

        rewritten
      end

      # Calculate total byte savings
      #
      # Sums up the savings from all selected patterns to determine
      # total file size reduction achieved by subroutinization.
      #
      # @param patterns [Array<Pattern>] selected patterns
      # @return [Integer] total bytes saved
      def calculate_total_savings(patterns)
        patterns.sum(&:savings)
      end
    end
  end
end
