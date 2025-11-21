# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff
      # Wrapper class for CFF glyph data
      #
      # [`CFFGlyph`](lib/fontisan/tables/cff/cff_glyph.rb) provides a unified
      # interface for CFF glyphs that matches the API of TrueType glyphs
      # ([`SimpleGlyph`](lib/fontisan/tables/glyf/simple_glyph.rb) and
      # [`CompoundGlyph`](lib/fontisan/tables/glyf/compound_glyph.rb)).
      #
      # This allows [`GlyphAccessor`](lib/fontisan/glyph_accessor.rb) to work
      # transparently with both TrueType (glyf) and OpenType/CFF fonts.
      #
      # CFF Glyph Characteristics:
      # - Always "simple" (no composite structure like TrueType compound glyphs)
      # - Outline data stored as Type 2 CharString programs
      # - Width information embedded in CharString
      # - Glyph names from Charset
      #
      # @example Accessing a CFF glyph
      #   cff = font.table("CFF ")
      #   charstring = cff.charstring_for_glyph(42)
      #   glyph = CFFGlyph.new(42, charstring, cff.charset, cff.encoding)
      #
      #   puts glyph.name           # => "A"
      #   puts glyph.width          # => 500
      #   puts glyph.bounding_box   # => [10, 0, 490, 700]
      #   puts glyph.simple?        # => true
      #   puts glyph.compound?      # => false
      #
      # Reference: [`docs/ttfunk-feature-analysis.md:541-575`](docs/ttfunk-feature-analysis.md:541)
      class CFFGlyph
        # @return [Integer] Glyph ID (GID)
        attr_reader :glyph_id

        # @return [CharString] Interpreted CharString with path data
        attr_reader :charstring

        # Initialize a CFF glyph wrapper
        #
        # @param glyph_id [Integer] Glyph ID (0-based, 0 is .notdef)
        # @param charstring [CharString] Interpreted CharString object
        # @param charset [Charset] Charset for name lookup
        # @param encoding [Encoding, nil] Encoding (optional, for character code
        #   mapping)
        def initialize(glyph_id, charstring, charset, encoding = nil)
          @glyph_id = glyph_id
          @charstring = charstring
          @charset = charset
          @encoding = encoding
        end

        # Check if this is a simple glyph
        #
        # CFF glyphs are conceptually "simple" - they don't have the composite
        # structure that TrueType compound glyphs have. While CFF CharStrings
        # can call subroutines, these are code reuse mechanisms, not glyph
        # composition.
        #
        # @return [Boolean] Always true for CFF glyphs
        def simple?
          true
        end

        # Check if this is a compound glyph
        #
        # CFF glyphs don't have components like TrueType compound glyphs.
        #
        # @return [Boolean] Always false for CFF glyphs
        def compound?
          false
        end

        # Check if this glyph has no outline data
        #
        # A glyph is empty if its CharString path is empty (e.g., space
        # character)
        #
        # @return [Boolean] True if glyph has no path data
        def empty?
          return true unless @charstring

          @charstring.path.empty?
        end

        # Get the bounding box for this glyph
        #
        # Returns the glyph's bounding box in font units as calculated from
        # the CharString path.
        #
        # @return [Array<Float>, nil] [xMin, yMin, xMax, yMax] or nil if empty
        def bounding_box
          return nil unless @charstring

          @charstring.bounding_box
        end

        # Get the advance width for this glyph
        #
        # Returns the glyph's advance width from the CharString.
        #
        # @return [Integer, nil] Advance width in font units, or nil if not
        #   available
        def width
          return nil unless @charstring

          @charstring.width
        end

        # Get the PostScript glyph name
        #
        # Looks up the glyph name from the Charset using the glyph ID.
        #
        # @return [String] Glyph name (e.g., "A", "Aacute", ".notdef")
        def name
          return ".notdef" unless @charset

          @charset.glyph_name(@glyph_id) || ".notdef"
        end

        # Convert the glyph outline to drawing commands
        #
        # Returns an array of drawing commands that can be used to render
        # the glyph outline.
        #
        # @return [Array<Array>] Array of command arrays:
        #   - [:move_to, x, y]
        #   - [:line_to, x, y]
        #   - [:curve_to, x1, y1, x2, y2, x, y]
        #
        # @example Rendering a glyph
        #   glyph.to_commands.each do |cmd|
        #     case cmd[0]
        #     when :move_to
        #       canvas.move_to(cmd[1], cmd[2])
        #     when :line_to
        #       canvas.line_to(cmd[1], cmd[2])
        #     when :curve_to
        #       canvas.curve_to(cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6])
        #     end
        #   end
        def to_commands
          return [] unless @charstring

          @charstring.to_commands
        end

        # Get the raw path data
        #
        # Returns the raw path array from the CharString for advanced use cases.
        #
        # @return [Array<Hash>] Array of path command hashes with keys:
        #   - :type (:move_to, :line_to, :curve_to)
        #   - :x, :y (coordinates)
        #   - :x1, :y1, :x2, :y2 (control points for curves)
        def path
          return [] unless @charstring

          @charstring.path
        end

        # String representation for debugging
        #
        # @return [String] Human-readable representation
        def to_s
          "#<#{self.class.name} gid=#{@glyph_id} name=#{name.inspect} " \
            "width=#{width} bbox=#{bounding_box.inspect}>"
        end

        alias inspect to_s
      end
    end
  end
end
