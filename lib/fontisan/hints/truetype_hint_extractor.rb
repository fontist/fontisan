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

      # Extract complete hint data from TrueType font
      #
      # This extracts both font-level hints (fpgm, prep, cvt tables) and
      # per-glyph hints from glyph instructions.
      #
      # @param font [TrueTypeFont] TrueType font object
      # @return [Models::HintSet] Complete hint set
      def extract_from_font(font)
        hint_set = Models::HintSet.new(format: "truetype")

        # Extract font-level programs
        hint_set.font_program = extract_font_program(font)
        hint_set.control_value_program = extract_control_value_program(font)
        hint_set.control_values = extract_control_values(font)

        # Extract per-glyph hints
        extract_glyph_hints(font, hint_set)

        # Update metadata
        hint_set.has_hints = !hint_set.empty?

        hint_set
      end

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

      # Extract font program (fpgm table)
      #
      # @param font [TrueTypeFont] TrueType font
      # @return [String] Font program bytecode (binary string)
      def extract_font_program(font)
        return "" unless font.has_table?("fpgm")

        font_program_data = font.instance_variable_get(:@table_data)["fpgm"]
        return "" unless font_program_data

        # Return as binary string
        font_program_data.force_encoding("ASCII-8BIT")
      rescue StandardError => e
        warn "Failed to extract font program: #{e.message}"
        ""
      end

      # Extract control value program (prep table)
      #
      # @param font [TrueTypeFont] TrueType font
      # @return [String] Control value program bytecode (binary string)
      def extract_control_value_program(font)
        return "" unless font.has_table?("prep")

        prep_data = font.instance_variable_get(:@table_data)["prep"]
        return "" unless prep_data

        # Return as binary string
        prep_data.force_encoding("ASCII-8BIT")
      rescue StandardError => e
        warn "Failed to extract control value program: #{e.message}"
        ""
      end

      # Extract control values (cvt table)
      #
      # @param font [TrueTypeFont] TrueType font
      # @return [Array<Integer>] Control values
      def extract_control_values(font)
        return [] unless font.has_table?("cvt ")

        cvt_data = font.instance_variable_get(:@table_data)["cvt "]
        return [] unless cvt_data

        # CVT table is an array of 16-bit signed integers (FWord values)
        values = []
        io = StringIO.new(cvt_data)
        while !io.eof?
          # Read 16-bit big-endian signed integer
          bytes = io.read(2)
          break unless bytes&.length == 2

          value = bytes.unpack1("n") # Unsigned short
          # Convert to signed
          value = value - 65536 if value > 32767
          values << value
        end

        values
      rescue StandardError => e
        warn "Failed to extract control values: #{e.message}"
        []
      end

      # Extract per-glyph hints from glyf table
      #
      # @param font [TrueTypeFont] TrueType font
      # @param hint_set [Models::HintSet] Hint set to populate
      # @return [void]
      def extract_glyph_hints(font, hint_set)
        return unless font.has_table?("glyf")

        glyf_table = font.table("glyf")
        return unless glyf_table

        # Get number of glyphs from maxp table
        maxp_table = font.table("maxp")
        return unless maxp_table

        num_glyphs = maxp_table.num_glyphs

        # Iterate through all glyphs
        (0...num_glyphs).each do |glyph_id|
          begin
            glyph = glyf_table.glyph_for(glyph_id)
            next unless glyph
            next if glyph.number_of_contours <= 0 # Skip compound glyphs and empty glyphs

            # Extract hints from simple glyph instructions
            hints = extract(glyph)
            next if hints.empty?

            # Store glyph hints
            hint_set.add_glyph_hints(glyph_id, hints)
          rescue StandardError => e
            # Skip glyphs that fail to parse
            next
          end
        end
      rescue StandardError => e
        warn "Failed to extract glyph hints: #{e.message}"
      end
    end
  end
end
