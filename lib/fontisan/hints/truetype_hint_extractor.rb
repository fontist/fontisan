# frozen_string_literal: true

require_relative "../models/hint"

module Fontisan
  module Hints
    # Extracts rendering hints from TrueType glyph data
    #
    # TrueType uses bytecode instructions for hinting. This extractor
    # analyzes glyph instruction sequences and converts them into
    # universal Hint objects for format-agnostic representation.
    #
    # **Supported TrueType Instructions:**
    #
    # - MDAP - Move Direct Absolute Point (stem positioning)
    # - MDRP - Move Direct Relative Point (stem width)
    # - IUP - Interpolate Untouched Points (smooth interpolation)
    # - SHP - Shift Point (point adjustments)
    # - ALIGNRP - Align to Reference Point (alignment)
    # - DELTA - Delta instructions (pixel-level adjustments)
    #
    # @example Extract hints from a glyph
    #   extractor = TrueTypeHintExtractor.new
    #   hints = extractor.extract(glyph)
    class TrueTypeHintExtractor
      # TrueType instruction opcodes
      MDAP_RND = 0x2E
      MDAP_NORND = 0x2F
      MDRP_MIN_RND_BLACK = 0xC0
      IUP_Y = 0x30
      IUP_X = 0x31
      SHP = [0x32, 0x33]
      ALIGNRP = 0x3C
      DELTAP1 = 0x5D
      DELTAP2 = 0x71
      DELTAP3 = 0x72

      # Extract hints from TrueType glyph
      #
      # @param glyph [Glyph] TrueType glyph with instructions
      # @return [Array<Hint>] Extracted hints
      def extract(glyph)
        return [] if glyph.nil? || glyph.empty?
        return [] unless glyph.respond_to?(:instructions)

        instructions = glyph.instructions || []
        return [] if instructions.empty?

        parse_instructions(instructions)
      end

      private

      # Parse TrueType instruction bytes into Hint objects
      #
      # @param instructions [String, Array<Integer>] Instruction bytes
      # @return [Array<Hint>] Parsed hints
      def parse_instructions(instructions)
        hints = []
        bytes = instructions.is_a?(String) ? instructions.bytes : instructions
        i = 0

        while i < bytes.length
          opcode = bytes[i]

          case opcode
          when MDAP_RND, MDAP_NORND
            # Stem positioning hint
            hint = extract_stem_hint(bytes, i)
            hints << hint if hint
            i += 1

          when MDRP_MIN_RND_BLACK
            # Stem width hint (usually follows MDAP)
            # This is typically part of a stem hint pair
            i += 1

          when IUP_Y, IUP_X
            # Interpolation hint
            hints << Models::Hint.new(
              type: :interpolate,
              data: { axis: opcode == IUP_Y ? :y : :x },
              source_format: :truetype
            )
            i += 1

          when *SHP
            # Shift point hint
            hints << Models::Hint.new(
              type: :shift,
              data: { instructions: [opcode] },
              source_format: :truetype
            )
            i += 1

          when ALIGNRP
            # Alignment hint
            hints << Models::Hint.new(
              type: :align,
              data: {},
              source_format: :truetype
            )
            i += 1

          when DELTAP1, DELTAP2, DELTAP3
            # Delta hint - pixel-level adjustments
            # Next byte is the count
            i += 1
            if i < bytes.length
              count = bytes[i]
              delta_data = bytes[i + 1, count * 2] || []
              hints << Models::Hint.new(
                type: :delta,
                data: {
                  instructions: [opcode] + [count] + delta_data,
                  count: count
                },
                source_format: :truetype
              )
              i += count * 2 + 1
            end

          else
            # Unknown or data bytes - skip
            i += 1
          end
        end

        hints
      end

      # Extract stem hint from MDAP instruction
      #
      # @param bytes [Array<Integer>] Instruction bytes
      # @param index [Integer] Current position
      # @return [Hint, nil] Stem hint if found
      def extract_stem_hint(bytes, index)
        # In TrueType, stem hints are inferred from MDAP + MDRP pairs
        # This is a simplified extraction - real implementation would
        # need to track the graphics state and point references

        # Check if next instruction is MDRP (stem width)
        has_width = index + 1 < bytes.length &&
                    bytes[index + 1] == MDRP_MIN_RND_BLACK

        if has_width
          Models::Hint.new(
            type: :stem,
            data: {
              position: 0, # Would be extracted from graphics state
              width: 0,    # Would be calculated from MDRP
              orientation: :vertical # Inferred from instruction context
            },
            source_format: :truetype
          )
        else
          nil
        end
      end
    end
  end
end