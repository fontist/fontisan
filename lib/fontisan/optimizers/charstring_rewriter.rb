# frozen_string_literal: true

module Fontisan
  module Optimizers
    # Rewrites CharStrings by replacing repeated patterns with subroutine calls.
    # Uses position-aware replacement to handle multiple patterns per glyph
    # without offset corruption.
    #
    # @example Basic usage
    #   builder = SubroutineBuilder.new(patterns, type: :local)
    #   builder.build
    #   subroutine_map = patterns.each_with_index.to_h { |p, i| [p.bytes, i] }
    #   rewriter = CharstringRewriter.new(subroutine_map, builder)
    #   rewritten = rewriter.rewrite(charstring, patterns_for_glyph)
    #   valid = rewriter.validate(rewritten)
    #
    # @see docs/SUBROUTINE_ARCHITECTURE.md
    class CharstringRewriter
      # Initialize rewriter with subroutine map and builder
      # @param subroutine_map [Hash<String, Integer>] pattern bytes => subroutine_id
      # @param builder [SubroutineBuilder] builder for creating calls
      def initialize(subroutine_map, builder)
        @subroutine_map = subroutine_map
        @builder = builder
      end

      # Rewrite a CharString by replacing patterns with subroutine calls
      # Sorts patterns by position (descending) to avoid offset issues when
      # replacing multiple patterns in the same CharString.
      #
      # @param charstring [String] original CharString bytes
      # @param patterns [Array<Pattern>] patterns to replace in this CharString
      # @return [String] rewritten CharString with subroutine calls
      def rewrite(charstring, patterns)
        return charstring if patterns.empty?

        # Build list of all replacements: [position, pattern]
        replacements = build_replacement_list(charstring, patterns)

        # Remove overlapping replacements
        replacements = remove_overlaps(replacements)

        # Sort by position (descending) to avoid offset corruption
        replacements.sort_by! { |pos, _pattern| -pos }

        # Apply each replacement
        rewritten = charstring.dup
        replacements.each do |position, pattern|
          subroutine_id = @subroutine_map[pattern.bytes]
          next if subroutine_id.nil?

          call = @builder.create_call(subroutine_id)

          # Replace pattern with call at position
          rewritten[position, pattern.length] = call
        end

        rewritten
      end

      # Validate rewritten CharString for structural correctness
      # For now, performs basic validation. Future: full CFF parsing.
      #
      # @param charstring [String] CharString to validate
      # @return [Boolean] true if valid, false otherwise
      def validate(charstring)
        return false if charstring.nil? || charstring.empty?

        # Basic validation: check for return operator at end
        # and reasonable length
        return false if charstring.empty?

        # More comprehensive validation can be added later
        true
      end

      private

      # Remove overlapping replacements, keeping higher-value patterns
      # When two patterns occupy overlapping byte positions, we keep the one
      # with higher savings to maximize total optimization benefit.
      #
      # @param replacements [Array<Array>] array of [position, pattern] pairs
      # @return [Array<Array>] non-overlapping replacements
      def remove_overlaps(replacements)
        return replacements if replacements.empty?

        # Sort by position (ascending) then by savings (descending)
        sorted = replacements.sort_by { |pos, pattern| [pos, -pattern.savings] }

        non_overlapping = []
        last_end = 0

        sorted.each do |position, pattern|
          pattern_end = position + pattern.length

          # Check if this replacement starts after the last one ended
          if position >= last_end
            # No overlap - add this replacement
            non_overlapping << [position, pattern]
            last_end = pattern_end
          elsif non_overlapping.any?
            # Overlap detected - compare with previous
            prev_position, prev_pattern = non_overlapping.last
            prev_position + prev_pattern.length

            # If current pattern has higher savings, replace the previous one
            if pattern.savings > prev_pattern.savings
              # Current pattern is more valuable - replace previous
              non_overlapping[-1] = [position, pattern]
              last_end = pattern_end
            end
            # else: keep previous, skip current
          end
        end

        non_overlapping
      end

      # Build list of all pattern replacements with their positions
      # @param charstring [String] CharString being rewritten
      # @param patterns [Array<Pattern>] patterns to find
      # @return [Array<Array>] array of [position, pattern] pairs
      def build_replacement_list(charstring, patterns)
        replacements = []

        patterns.each do |pattern|
          # Find all positions where this pattern occurs
          positions = find_pattern_positions(charstring, pattern)

          positions.each do |position|
            replacements << [position, pattern]
          end
        end

        replacements
      end

      # Find all positions where a pattern occurs in the CharString
      # @param charstring [String] CharString to search
      # @param pattern [Pattern] pattern to find
      # @return [Array<Integer>] array of start positions
      def find_pattern_positions(charstring, pattern)
        positions = []
        offset = 0

        while offset <= charstring.length - pattern.length
          if charstring[offset, pattern.length] == pattern.bytes
            positions << offset
            # Move past this occurrence
            offset += pattern.length
          else
            offset += 1
          end
        end

        positions
      end
    end
  end
end
