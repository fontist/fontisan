# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Minimal Adobe FEA (features.fea) parser. Extracts the two most
      # common feature constructs from UFO sources:
      #
      #   feature liga { sub f i by fi; } liga;    → LigatureSubst
      #   feature kern { pos A V -50; } kern;       → PairPos
      #
      # Unsupported constructs are collected and surfaced via
      # {ParsedFeatures#unsupported} so the caller can decide whether
      # to warn or raise. This is the "limited fea subset" approach
      # from TODO #10b — expand as real-world fonts demand.
      #
      # The parser is deliberately simple: it tokenizes on whitespace
      # and semicolons, recognizes `feature <tag> { ... } <tag>;` blocks,
      # and dispatches per-statement to registered rule handlers (OCP —
      # new rule kinds are one handler addition).
      #
      # @example
      #   parsed = FeatureCompiler.parse(fea_text)
      #   parsed.ligatures_for("liga")  # => [{sequence: ["f", "i"], result: "fi"}]
      class FeatureCompiler
        # @param text [String] features.fea content
        # @return [ParsedFeatures]
        def self.parse(text)
          new.parse(text)
        end

        # @param text [String]
        # @return [ParsedFeatures]
        def parse(text)
          @parsed = ParsedFeatures.new
          tokenize_blocks(text || "")
          @parsed
        end

        private

        # Split text into `feature <tag> { body } <tag>;` blocks and
        # pass each block body to the statement dispatcher.
        def tokenize_blocks(text)
          # Strip comments (# to end of line)
          cleaned = text.gsub(%r{#[^\n]*}, "")
          # Match feature blocks: feature TAG { ... } TAG;
          cleaned.scan(/feature\s+([A-Za-z0-9]{4})\s*\{([^}]*)\}\s*\1\s*;/m) do |tag, body|
            parse_body(tag, body)
          end
        end

        # Parse statements within a feature block.
        def parse_body(tag, body)
          statements = body.split(";").map(&:strip).reject(&:empty?)
          statements.each do |stmt|
            tokens = stmt.split(/\s+/)
            dispatch(tag, tokens, stmt)
          end
        end

        # Dispatch a statement to the appropriate handler based on the
        # leading keyword. Unknown statements are collected as unsupported.
        def dispatch(tag, tokens, raw)
          case tokens.first
          when "sub" then handle_sub(tag, tokens)
          when "pos" then handle_pos(tag, tokens)
          else
            @parsed.add_unsupported(tag, raw)
          end
        end

        # `sub A B C by ABC;` → ligature substitution
        def handle_sub(tag, tokens)
          # tokens: ["sub", "A", "B", ..., "by", "ABC"]
          by_idx = tokens.index("by")
          unless by_idx && by_idx > 1 && tokens.size > by_idx + 1
            @parsed.add_unsupported(tag, tokens.join(" "))
            return
          end

          sequence = tokens[1, by_idx - 1]
          result = tokens[by_idx + 1]
          return if sequence.nil? || sequence.empty? || result.nil?

          if sequence.size == 1
            # Single substitution: `sub A by A.alt;` — unsupported for now
            @parsed.add_unsupported(tag, tokens.join(" "))
            return
          end

          @parsed.add_ligature(tag, sequence: sequence, result: result)
        end

        # `pos A B -50;` → pair positioning
        def handle_pos(tag, tokens)
          # tokens: ["pos", "A", "B", "-50"] or ["pos", "A", "B", "<", "0", "-50", "0", ">"]
          return unless tokens.size >= 4

          left = tokens[1]
          right = tokens[2]
          value = parse_pos_value(tokens[3])
          return unless value

          @parsed.add_pair(tag, left:, right:, value:)
        end

        # Parse a positioning value: either a bare integer or the start
        # of a ValueRecord (we only handle the bare integer case for now).
        def parse_pos_value(token)
          Integer(token)
        rescue ArgumentError
          nil
        end
      end

      # Result of parsing features.fea. Aggregates ligature and pair
      # rules by feature tag, plus any unsupported statements.
      class ParsedFeatures
        attr_reader :ligatures, :pairs, :unsupported

        def initialize
          @ligatures = Hash.new { |h, k| h[k] = [] }
          @pairs = Hash.new { |h, k| h[k] = [] }
          @unsupported = Hash.new { |h, k| h[k] = [] }
        end

        # @param tag [String] feature tag
        # @return [Array<Hash>] ligature rules: {sequence: [names], result: name}
        def ligatures_for(tag)
          @ligatures[tag] || []
        end

        # @param tag [String] feature tag
        # @return [Array<Hash>] pair rules: {left:, right:, value:}
        def pairs_for(tag)
          @pairs[tag] || []
        end

        # @return [Boolean] true if no features were parsed
        def empty?
          @ligatures.empty? && @pairs.empty?
        end

        # ---- mutation (used by FeatureCompiler) ----

        def add_ligature(tag, sequence:, result:)
          @ligatures[tag] << { sequence: sequence, result: result }
        end

        def add_pair(tag, left:, right:, value:)
          @pairs[tag] << { left: left, right: right, value: value }
        end

        def add_unsupported(tag, statement)
          @unsupported[tag] << statement
        end
      end
    end
  end
end
