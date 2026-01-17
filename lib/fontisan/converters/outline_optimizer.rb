# frozen_string_literal: true

require_relative "../optimizers/pattern_analyzer"
require_relative "../optimizers/subroutine_optimizer"
require_relative "../optimizers/subroutine_builder"
require_relative "../optimizers/charstring_rewriter"

module Fontisan
  module Converters
    # Optimizes CFF CharStrings using subroutine extraction
    #
    # This module analyzes CharStrings for repeated patterns, extracts
    # them as subroutines, and rewrites the CharStrings to call the
    # subroutines instead of repeating the code.
    #
    # The optimization process:
    # 1. Analyze patterns across all CharStrings
    # 2. Select optimal set of patterns for subroutines
    # 3. Optimize subroutine ordering
    # 4. Build subroutines from selected patterns
    # 5. Rewrite CharStrings to call subroutines
    module OutlineOptimizer
      # Optimize CharStrings using subroutine extraction
      #
      # @param charstrings [Array<String>] Original CharString bytes
      # @return [Array<Array<String>, Array<String>>] [optimized_charstrings, local_subrs]
      def optimize_charstrings(charstrings)
        # Convert to hash format expected by PatternAnalyzer
        charstrings_hash = {}
        charstrings.each_with_index do |cs, index|
          charstrings_hash[index] = cs
        end

        # Analyze patterns
        analyzer = Optimizers::PatternAnalyzer.new(
          min_length: 10,
          stack_aware: true,
        )
        patterns = analyzer.analyze(charstrings_hash)

        # Return original if no patterns found
        return [charstrings, []] if patterns.empty?

        # Optimize selection
        optimizer = Optimizers::SubroutineOptimizer.new(patterns,
                                                        max_subrs: 65_535)
        selected_patterns = optimizer.optimize_selection

        # Optimize ordering
        selected_patterns = optimizer.optimize_ordering(selected_patterns)

        # Return original if no patterns selected
        return [charstrings, []] if selected_patterns.empty?

        # Build subroutines
        builder = Optimizers::SubroutineBuilder.new(selected_patterns,
                                                    type: :local)
        local_subrs = builder.build

        # Build subroutine map
        subroutine_map = {}
        selected_patterns.each_with_index do |pattern, index|
          subroutine_map[pattern.bytes] = index
        end

        # Rewrite CharStrings
        rewriter = Optimizers::CharstringRewriter.new(subroutine_map, builder)
        optimized_charstrings = charstrings.map.with_index do |charstring, glyph_id|
          # Find patterns for this glyph
          glyph_patterns = selected_patterns.select do |p|
            p.glyphs.include?(glyph_id)
          end

          if glyph_patterns.empty?
            charstring
          else
            rewriter.rewrite(charstring, glyph_patterns, glyph_id)
          end
        end

        [optimized_charstrings, local_subrs]
      rescue StandardError => e
        # If optimization fails for any reason, return original CharStrings
        warn "Optimization warning: #{e.message}"
        [charstrings, []]
      end
    end
  end
end
