# frozen_string_literal: true

module Fontisan
  module Optimizers
    # Optimizes subroutine selection and ordering for maximum file size reduction.
    # Uses a greedy algorithm to select the most beneficial patterns while avoiding
    # conflicts, then orders them by frequency for efficient encoding.
    #
    # @example Basic usage
    #   analyzer = PatternAnalyzer.new
    #   patterns = analyzer.analyze(charstrings)
    #   optimizer = SubroutineOptimizer.new(patterns, max_subrs: 65535)
    #   selected_patterns = optimizer.optimize_selection
    #   ordered_patterns = optimizer.optimize_ordering(selected_patterns)
    #
    # @see docs/SUBROUTINE_ARCHITECTURE.md
    class SubroutineOptimizer
      # Initialize optimizer with patterns
      # @param patterns [Array<Pattern>] patterns from analyzer
      # @param max_subrs [Integer] maximum number of subroutines (default: 65535)
      def initialize(patterns, max_subrs: 65535)
        @patterns = patterns
        @max_subrs = max_subrs
      end

      # Select optimal subset of patterns to subroutinize
      # Uses greedy algorithm: select by highest savings first, checking for
      # conflicts with already selected patterns.
      #
      # @return [Array<Pattern>] selected patterns
      def optimize_selection
        selected = []
        # Sort by savings (descending), then by length (descending), then by min glyph ID,
        # then by byte values for complete determinism across platforms
        remaining = @patterns.sort_by { |p| [-p.savings, -p.length, p.glyphs.min, p.bytes.bytes] }

        remaining.each do |pattern|
          break if selected.length >= @max_subrs
          next if conflicts_with_selected?(pattern, selected)

          selected << pattern
        end

        selected
      end

      # Optimize subroutine ordering by frequency
      # Higher frequency patterns get lower IDs for more efficient encoding
      # in CFF format.
      #
      # @param subroutines [Array<Pattern>] subroutines to order
      # @return [Array<Pattern>] ordered subroutines
      def optimize_ordering(subroutines)
        # Higher frequency = lower ID (shorter encoding)
        # Use same comprehensive sort keys as optimize_selection for consistency
        subroutines.sort_by { |subr| [-subr.frequency, -subr.length, subr.glyphs.min, subr.bytes.bytes] }
      end

      # Check if nesting would be beneficial
      # TODO: Phase 2.1 - check if subroutines contain common patterns
      #
      # @param subroutines [Array<Pattern>] subroutines to analyze
      # @return [Array<Pattern>] subroutines (unchanged for now)
      def optimize_nesting(subroutines)
        subroutines
      end

      private

      # Check if pattern conflicts with any already selected patterns
      # A conflict occurs when patterns overlap in the same glyph at
      # overlapping positions.
      #
      # @param pattern [Pattern] pattern to check
      # @param selected [Array<Pattern>] already selected patterns
      # @return [Boolean] true if conflicts, false otherwise
      def conflicts_with_selected?(pattern, selected)
        selected.any? do |sel|
          # Check if they share any glyphs
          common_glyphs = pattern.glyphs & sel.glyphs
          next false if common_glyphs.empty?

          # Check if positions overlap in any common glyph
          common_glyphs.any? { |gid| positions_overlap?(pattern, sel, gid) }
        end
      end

      # Check if two patterns overlap at positions in a specific glyph
      # Ranges overlap if they intersect at any point.
      #
      # @param p1 [Pattern] first pattern
      # @param p2 [Pattern] second pattern
      # @param glyph_id [Integer] glyph to check
      # @return [Boolean] true if positions overlap, false otherwise
      def positions_overlap?(p1, p2, glyph_id)
        pos1 = p1.positions[glyph_id] || []
        pos2 = p2.positions[glyph_id] || []

        pos1.any? do |start1|
          end1 = start1 + p1.length
          pos2.any? do |start2|
            end2 = start2 + p2.length
            # Check if ranges overlap: start1 < end2 && start2 < end1
            start1 < end2 && start2 < end1
          end
        end
      end
    end
  end
end
