# frozen_string_literal: true

require "stringio"
require_relative "stack_tracker"

module Fontisan
  module Optimizers
    # Analyzes CharString patterns across glyphs to identify repeated sequences
    # suitable for subroutinization. Implements suffix tree-based pattern matching
    # for efficient detection of repeated byte sequences.
    #
    # Can optionally use stack-aware detection to ensure patterns are stack-neutral,
    # making them safe for subroutinization without causing stack underflow/overflow.
    #
    # @example Basic usage
    #   analyzer = PatternAnalyzer.new(min_length: 10)
    #   charstrings = { 0 => "\x01\x02...", 1 => "\x01\x02..." }
    #   patterns = analyzer.analyze(charstrings)
    #
    # @example Stack-aware analysis
    #   analyzer = PatternAnalyzer.new(min_length: 10, stack_aware: true)
    #   patterns = analyzer.analyze(charstrings)
    #
    # @see docs/SUBROUTINE_ARCHITECTURE.md
    class PatternAnalyzer
      # Pattern data structure representing a repeated CharString sequence
      Pattern = Struct.new(
        :bytes,        # String: pattern byte sequence
        :length,       # Integer: byte length
        :glyphs,       # Array<Integer>: glyph IDs containing pattern
        :frequency,    # Integer: number of occurrences
        :savings,      # Integer: total byte savings
        :positions, # Hash<Integer, Array<Integer>>: glyph_id => [positions]
        :stack_neutral, # Boolean: whether pattern is stack-neutral
      ) do
        # Calculate overhead for calling this pattern as a subroutine
        # @return [Integer] byte overhead (callsubr + number + return)
        def call_overhead
          1 + number_size(frequency) + 1 # callsubr + number + return
        end

        # Calculate CFF integer encoding size
        # @param n [Integer] number to encode
        # @return [Integer] byte size of encoded number
        def number_size(num)
          return 1 if num >= -107 && num <= 107
          return 2 if num >= -1131 && num <= 1131
          return 3 if num >= -32768 && num <= 32767

          5
        end
      end

      # Initialize pattern analyzer
      # @param min_length [Integer] minimum pattern length in bytes
      # @param stack_aware [Boolean] whether to enforce stack-neutral patterns
      def initialize(min_length: 10, stack_aware: false)
        @min_length = min_length
        @stack_aware = stack_aware
        @patterns = {}
        @stack_trackers = {} # Cache StackTracker instances per glyph
      end

      # Analyze CharStrings to find repeated patterns
      #
      # @param charstrings [Hash<Integer, String>] glyph_id => charstring_bytes
      # @return [Array<Pattern>] patterns sorted by savings (descending)
      def analyze(charstrings)
        raise ArgumentError, "No CharStrings provided" if charstrings.empty?

        # Build stack trackers if stack-aware mode enabled
        build_stack_trackers(charstrings) if @stack_aware

        # Extract all byte sequences and build pattern candidates
        extract_patterns(charstrings)

        # Calculate savings for each pattern
        calculate_savings

        # Filter patterns by minimum length and positive savings
        filter_patterns

        # Sort by savings (descending) and return
        @patterns.values.sort_by { |p| -p.savings }
      end

      private

      # Find operator boundaries in CharString
      # Returns positions where operators end, which are valid pattern boundaries
      # @param charstring [String] CharString bytes
      # @return [Array<Integer>] byte positions of boundaries
      def find_operator_boundaries(charstring)
        io = StringIO.new(charstring)
        boundaries = [0] # Start is always a boundary

        until io.eof?
          byte = io.getbyte

          if byte <= 31 && byte != 28
            # Operator byte (28 is a number encoding prefix)
            if byte == 12
              # Two-byte operator
              io.getbyte
            end
            # Mark position after operator as boundary
            boundaries << io.pos
          else
            # Number - skip it
            io.pos -= 1
            skip_number(io)
          end
        end

        boundaries
      end

      # Skip over a number without decoding
      # Handles all CFF integer encoding formats
      # @param io [StringIO] input stream
      def skip_number(io)
        byte = io.getbyte
        return if byte.nil?

        case byte
        when 28
          # 3-byte signed integer
          io.read(2)
        when 32..246
          # Single byte integer - already consumed
        when 247..254
          # 2-byte integer
          io.getbyte
        when 255
          # 5-byte integer
          io.read(4)
        end
      end

      # Build stack trackers for all CharStrings (if stack-aware)
      def build_stack_trackers(charstrings)
        charstrings.each do |glyph_id, charstring|
          tracker = StackTracker.new(charstring)
          tracker.track
          @stack_trackers[glyph_id] = tracker
        end
      end

      # Extract patterns from all CharStrings
      # Uses operator boundaries to ensure patterns are syntactically valid
      # OPTIMIZED: Samples glyphs and uses discrete lengths to avoid O(n³) complexity
      def extract_patterns(charstrings)
        pattern_occurrences = Hash.new { |h, k| h[k] = [] }

        # OPTIMIZATION 1: Sample glyphs if there are too many
        # For large fonts (1000+ glyphs), sample 30% of glyphs
        sample_size = if charstrings.length > 1000
                        (charstrings.length * 0.3).to_i
                      else
                        charstrings.length
                      end

        # Use deterministic selection instead of random sampling
        # Sort keys first to ensure consistent ordering across platforms
        sampled_glyphs = charstrings.keys.sort.take(sample_size)

        # NEW: Pre-compute boundaries for sampled glyphs
        # Check if boundaries are useful (more than just start position)
        glyph_boundaries = {}
        use_boundaries = false
        sampled_glyphs.each do |glyph_id|
          boundaries = find_operator_boundaries(charstrings[glyph_id])
          glyph_boundaries[glyph_id] = boundaries
          # If any glyph has meaningful boundaries (more than just [0]), use boundary mode
          use_boundaries = true if boundaries.length > 2
        end

        # OPTIMIZATION 2: Use discrete pattern lengths instead of continuous range
        # This reduces iterations from 40 to ~5
        pattern_lengths = [@min_length, @min_length + 5, @min_length + 10,
                           @min_length + 15, @min_length + 20]

        # For each sampled glyph, extract patterns
        sampled_glyphs.each do |glyph_id|
          charstring = charstrings[glyph_id]
          next if charstring.length < @min_length

          if use_boundaries
            # Use boundary-based extraction for valid CFF CharStrings
            boundaries = glyph_boundaries[glyph_id]

            # Try each boundary as a potential start position
            boundaries.each do |start_pos|
              # Find boundaries that could be end positions
              pattern_lengths.each do |target_length|
                # Find next boundary that gives us approximately target_length
                end_pos = boundaries.find { |b| b >= start_pos + target_length }
                next unless end_pos

                actual_length = end_pos - start_pos
                next if actual_length < @min_length
                next if actual_length > @min_length + 25 # Max pattern size

                # Check if pattern is stack-neutral (if stack-aware mode)
                if @stack_aware
                  tracker = @stack_trackers[glyph_id]
                  next unless tracker
                  next unless tracker.stack_neutral?(start_pos, end_pos)
                end

                pattern_bytes = charstring[start_pos, actual_length]

                # Record occurrence: pattern => [[glyph_id, position], ...]
                pattern_occurrences[pattern_bytes] << [glyph_id, start_pos]
              end
            end
          else
            # Fall back to sliding window for non-CFF data (e.g., test data)
            pattern_lengths.each do |length|
              break if length > charstring.length

              (0..charstring.length - length).each do |start_pos|
                # Check if pattern is stack-neutral (if stack-aware mode)
                if @stack_aware
                  tracker = @stack_trackers[glyph_id]
                  next unless tracker
                  next unless tracker.stack_neutral?(start_pos,
                                                     start_pos + length)
                end

                pattern_bytes = charstring[start_pos, length]

                # Record occurrence: pattern => [[glyph_id, position], ...]
                pattern_occurrences[pattern_bytes] << [glyph_id, start_pos]
              end
            end
          end
        end

        # Convert occurrences to Pattern objects
        pattern_occurrences.each do |bytes, occurrences|
          # Only keep patterns that appear in at least 2 glyphs or 2+ times
          next if occurrences.length < 2

          # Group by glyph_id
          by_glyph = occurrences.group_by(&:first)

          # Only keep if appears in multiple glyphs
          next if by_glyph.keys.length < 2

          # Build positions hash
          positions = {}
          by_glyph.each do |glyph_id, glyph_occurrences|
            positions[glyph_id] = glyph_occurrences.map(&:last).uniq
          end

          @patterns[bytes] = Pattern.new(
            bytes,
            bytes.length,
            by_glyph.keys,
            occurrences.length,
            0, # Will be calculated later
            positions,
            @stack_aware, # Mark if validated as stack-neutral
          )
        end
      end

      # Calculate byte savings for each pattern
      def calculate_savings
        @patterns.each_value do |pattern|
          # Savings = (pattern_length - overhead) * (frequency - 1)
          # -1 because we keep one occurrence in a subroutine
          overhead = pattern.call_overhead
          savings_per_use = pattern.length - overhead

          # Total savings across all uses (minus the subroutine definition)
          pattern.savings = if savings_per_use.positive?
                              savings_per_use * (pattern.frequency - 1)
                            else
                              0
                            end
        end
      end

      # Filter patterns by criteria
      def filter_patterns
        @patterns.select! do |_bytes, pattern|
          # Must meet minimum length
          next false if pattern.length < @min_length

          # Must have positive savings
          next false if pattern.savings <= 0

          # Must appear in at least 2 glyphs
          next false if pattern.glyphs.length < 2

          true
        end
      end

      # Find maximal patterns (not contained in larger patterns)
      # TODO: Implement in optimization phase
      def find_maximal_patterns
        # For now, keep all patterns
        # Future: remove patterns that are substrings of larger patterns
        # with same or higher frequency
      end
    end
  end
end
