# frozen_string_literal: true

module Fontisan
  module Cldr
    # Parses ICU UnicodeSet bracket notation as used in CLDR
    # exemplarCharacters fields.
    #
    # Supported syntax (sufficient for exemplar sets):
    #   - Single chars: `a`, `à`, any BMP or supplementary codepoint
    #   - Ranges: `a-z`, `A-Z`
    #   - Escapes: `\uXXXX`, `\UXXXXXXXX`, `\u{XXXX...}`
    #   - Negation: `[^...]` (inverts against 0..0x10FFFF)
    #
    # Unsupported (CLDR exemplars do not use these; raise ParseError):
    #   - Property syntax `[:script=Latin:]`
    #   - Set operations `[a-z & [b-c]]`
    #   - Nested sets `[a[b-c]]`
    #   - Named sequences `{a b c}`
    #
    # Output: sorted, deduplicated Array<Integer> of codepoints.
    module UnicodeSetParser
      class ParseError < Cldr::Error; end
      MAX_CODEPOINT = 0x10FFFF
      private_constant :MAX_CODEPOINT

      module_function

      # @param set_string [String] bracketed ICU UnicodeSet, e.g. "[a-zà]"
      # @return [Array<Integer>] sorted, deduplicated codepoints
      def call(set_string)
        raise ParseError, "input must be bracketed" unless set_string.start_with?("[") && set_string.end_with?("]")

        body = set_string[1..-2]
        negate = body.start_with?("^")
        body = body[1..] if negate

        cps = parse_body(body)
        cps = invert(cps) if negate
        cps.sort.uniq
      end

      # Walk the body char by char, emitting codepoints and ranges.
      def parse_body(body)
        cps = []
        chars = body.chars.to_a
        i = 0
        prev_cp = nil

        while i < chars.length
          ch = chars[i]

          case ch
          when "\\"
            cp, advance = parse_escape(chars, i)
            cps << cp
            prev_cp = cp
            i += advance
          when "-"
            raise ParseError, "dangling '-' at start" if prev_cp.nil?
            raise ParseError, "dangling '-' at end" if i + 1 >= chars.length

            next_cp, advance = read_next_codepoint(chars, i + 1)
            raise ParseError, "range with no upper bound" if next_cp.nil?

            cps.concat(((prev_cp + 1)..next_cp).to_a)
            prev_cp = next_cp
            i += 1 + advance
          when "[", "]"
            raise ParseError, "nested set syntax is not supported"
          when "{"
            raise ParseError, "named sequences ({...}) are not supported"
          when ":"
            raise ParseError, "property syntax ([:...:]) is not supported"
          else
            cps << ch.ord
            prev_cp = ch.ord
            i += 1
          end
        end

        cps
      end
      private_class_method :parse_body

      # Read the next codepoint starting at index `start`. Handles escapes.
      # @return [Array(Integer, Integer)] codepoint + chars consumed, or
      #   [nil, 0] if no codepoint is available.
      def read_next_codepoint(chars, start)
        return [nil, 0] if start >= chars.length

        ch = chars[start]
        if ch == "\\"
          parse_escape(chars, start)
        else
          [ch.ord, 1]
        end
      end
      private_class_method :read_next_codepoint

      # Parse a backslash escape sequence.
      # Supports \uXXXX, \UXXXXXXXX, \u{XXXX...}, and standard backslash
      # escapes (\\, \[, \], \-, \^).
      # @return [Array(Integer, Integer)] codepoint + chars consumed
      def parse_escape(chars, start)
        # chars[start] is "\\"
        return [0, 1] if start + 1 >= chars.length

        marker = chars[start + 1]
        case marker
        when "u"
          brace_form(chars, start) || four_hex(chars, start, "u")
        when "U"
          eight_hex(chars, start)
        when "\\"
          [0x5C, 2]
        when "[", "]", "-", "^"
          [marker.ord, 2]
        else
          raise ParseError, "unknown escape sequence \\#{marker}"
        end
      end
      private_class_method :parse_escape

      def brace_form(chars, start)
        return nil unless chars[start + 2] == "{"

        # \u{XXX...} variable hex
        end_idx = (start + 3..).find { |j| j >= chars.length || chars[j] == "}" }
        raise ParseError, "unclosed \\u{ escape" if end_idx.nil? || chars[end_idx] != "}"

        hex = chars[(start + 3)...end_idx].join
        cp = hex.to_i(16)
        raise ParseError, "\\u{ escape with no digits" if cp.zero? && hex.empty?

        [cp, (end_idx - start) + 1]
      end
      private_class_method :brace_form

      def four_hex(chars, start, marker)
        # \uXXXX — exactly 4 hex digits
        hex = chars[(start + 2), 4]&.join
        raise ParseError, "truncated \\#{marker} escape" if hex.nil? || hex.length < 4

        cp = hex.to_i(16)
        raise ParseError, "\\#{marker} escape with non-hex digits" if cp.zero? && !hex.match?(/\A0+\z/)

        [cp, 6]
      end
      private_class_method :four_hex

      def eight_hex(chars, start)
        # \UXXXXXXXX — exactly 8 hex digits
        hex = chars[(start + 2), 8]&.join
        raise ParseError, "truncated \\U escape" if hex.nil? || hex.length < 8

        cp = hex.to_i(16)
        raise ParseError, "\\U escape with non-hex digits" if cp.zero? && !hex.match?(/\A0+\z/)

        [cp, 10]
      end
      private_class_method :eight_hex

      def invert(cps)
        set = cps.to_set
        (0..MAX_CODEPOINT).each_with_object([]) do |cp, arr|
          arr << cp unless set.include?(cp)
        end
      end
      private_class_method :invert
    end
  end
end
