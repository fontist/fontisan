# frozen_string_literal: true

module Fontisan
  module Type1
    # TTF to Type 1 CharString Converter
    #
    # [`TTFToType1Converter`](lib/fontisan/type1/ttf_to_type1_converter.rb) converts
    # TrueType glyphs to Type 1 CharStrings.
    #
    # The conversion involves:
    # - Converting quadratic curves (TrueType) to cubic curves (Type 1)
    # - Scaling coordinates if needed
    # - Generating Type 1 CharString commands
    #
    # @example Convert TTF font to Type 1 CharStrings
    #   scaler = Fontisan::Type1::UPMScaler.type1_standard(font)
    #   converter = Fontisan::Type1::TTFToType1Converter.new(font, scaler, encoding)
    #   charstrings = converter.convert
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5178.Type1.pdf
    class TTFToType1Converter
      # Type 1 CharString command codes
      HSTEM = 1
      VSTEM = 3
      VMOVETO = 4
      RLINETO = 5
      HLINETO = 6
      VLINETO = 7
      RRCURVETO = 8
      CLOSEPATH = 9
      CALLSUBR = 10
      RETURN = 11
      ESCAPE = 12
      HSBW = 13
      ENDCHAR = 14
      RMOVETO = 21
      HMOVETO = 22
      VHCURVETO = 30
      HVCURVETO = 31

      # Convert TTF font to Type 1 CharStrings
      #
      # @param font [Fontisan::Font] Source TTF font
      # @param scaler [UPMScaler] UPM scaler
      # @param encoding [Class] Encoding class
      # @return [Hash<Integer, String>] Glyph ID to CharString mapping
      def self.convert(font, scaler, encoding)
        new(font, scaler, encoding).convert
      end

      def initialize(font, scaler, encoding)
        @font = font
        @scaler = scaler
        @encoding = encoding
        @charstrings = {}
      end

      # Convert all glyphs to CharStrings
      #
      # @return [Hash<Integer, String>] Glyph ID to CharString mapping
      def convert
        glyf_table = @font.table(Constants::GLYF_TAG)
        return {} unless glyf_table

        loca_table = @font.table(Constants::LOCA_TAG)
        head_table = @font.table(Constants::HEAD_TAG)

        maxp = @font.table(Constants::MAXP_TAG)
        num_glyphs = maxp&.num_glyphs || 0

        num_glyphs.times do |gid|
          @charstrings[gid] =
            convert_glyph(glyf_table, loca_table, head_table, gid)
        end

        @charstrings
      end

      private

      # Convert a single glyph to CharString
      #
      # @param glyf_table [Tables::Glyf] TTF glyf table
      # @param loca_table [Tables::Loca] TTF loca table
      # @param head_table [Tables::Head] TTF head table
      # @param gid [Integer] Glyph ID
      # @return [String] Type 1 CharString data
      def convert_glyph(glyf_table, loca_table, head_table, gid)
        glyph = glyf_table.glyph_for(gid, loca_table, head_table)

        # Handle empty glyph
        return empty_charstring if glyph.nil?

        # Handle compound glyphs
        if glyph.compound?
          return convert_composite_glyph(glyph, glyf_table)
        end

        # Convert simple glyph
        convert_simple_glyph(glyph)
      end

      # Convert a simple glyph to CharString
      #
      # @param glyph [Object] TTF simple glyph
      # @return [String] Type 1 CharString data
      def convert_simple_glyph(glyph)
        commands = []
        points = extract_points(glyph)

        return empty_charstring if points.empty?

        # Start with hsbw (horizontal side bearing and width)
        lsb = @scaler.scale(glyph.left_side_bearing || 0)
        width = @scaler.scale(glyph.advance_width || 500)
        commands << [HSBW, lsb, width]

        # Convert contours to Type 1 commands
        contour_commands = convert_contours(points)
        commands.concat(contour_commands)

        # End character
        commands << [ENDCHAR]

        # Encode to CharString format
        encode_charstring(commands)
      end

      # Extract points from a simple glyph
      #
      # @param glyph [Object] TTF simple glyph
      # @return [Array<Hash>] Array of points with on_curve flag
      def extract_points(glyph)
        return [] unless glyph.respond_to?(:points)

        points = []
        glyph.points.each do |point|
          points << {
            x: @scaler.scale(point.x),
            y: @scaler.scale(point.y),
            on_curve: point.on_curve?,
          }
        end

        points
      end

      # Convert contours to Type 1 commands
      #
      # @param points [Array<Hash>] Array of points
      # @return [Array<Array<Integer>>] Array of command arrays
      def convert_contours(points)
        commands = []
        return commands if points.empty?

        # Start at first point
        start_point = points[0]
        current_point = { x: start_point[:x], y: start_point[:y] }

        # Process remaining points in runs
        i = 1
        while i < points.length
          point = points[i]

          if point[:on_curve]
            # On-curve point - draw line or curve from previous
            if i.positive? && !points[i - 1][:on_curve]
              # Previous was off-curve, this is end of quadratic curve
              prev_point = points[i - 1]
              curve_commands = convert_quadratic_to_cubic(
                current_point,
                prev_point,
                point,
              )
              commands.concat(curve_commands)
            else
              # Line to this point
              dx = point[:x] - current_point[:x]
              dy = point[:y] - current_point[:y]
              commands << [RLINETO, dx, dy]
            end
            current_point = { x: point[:x], y: point[:y] }
          elsif i + 1 < points.length && !points[i + 1][:on_curve]
            # Off-curve control point
            # Check if next point is also off-curve (implicit on-curve midpoint)
            next_point = points[i + 1]
            implicit_on = {
              x: ((point[:x] + next_point[:x]).to_f / 2).round,
              y: ((point[:y] + next_point[:y]).to_f / 2).round,
            }

            curve_commands = convert_quadratic_to_cubic(
              current_point,
              point,
              implicit_on,
            )
            commands.concat(curve_commands)
            current_point = implicit_on
            # Both are off-curve, implicit on-curve at midpoint
            # If next point is on-curve, we'll handle it in next iteration
          end

          i += 1
        end

        # Close contour if needed (implicit close path for Type 1)
        # Type 1 implicitly closes paths, so we don't need explicit close

        commands
      end

      # Convert quadratic Bézier curve to cubic Bézier curve
      #
      # TrueType uses quadratic curves with one control point:
      # P0 (on) -> P1 (off) -> P2 (on)
      #
      # Type 1 uses cubic curves with two control points:
      # P0 (on) -> C1 (off) -> C2 (off) -> P2 (on)
      #
      # Conversion formula:
      # C1 = P0 + (2/3)(P1 - P0) = (1/3)P0 + (2/3)P1
      # C2 = P2 + (2/3)(P1 - P2) = (2/3)P1 + (1/3)P2
      #
      # @param p0 [Hash] Start point {x, y}
      # @param p1 [Hash] Control point {x, y}
      # @param p2 [Hash] End point {x, y}
      # @return [Array<Array<Integer>>] Array of command arrays
      def convert_quadratic_to_cubic(p0, p1, p2)
        # Calculate cubic control points
        c1_x = p0[:x] + ((2 * (p1[:x] - p0[:x])).to_f / 3).round
        c1_y = p0[:y] + ((2 * (p1[:y] - p0[:y])).to_f / 3).round

        c2_x = p2[:x] + ((2 * (p1[:x] - p2[:x])).to_f / 3).round
        c2_y = p2[:y] + ((2 * (p1[:y] - p2[:y])).to_f / 3).round

        # Calculate deltas
        dc1x = c1_x - p0[:x]
        dc1y = c1_y - p0[:y]
        dc2x = c2_x - c1_x
        dc2y = c2_y - c1_y
        dx = p2[:x] - c2_x
        dy = p2[:y] - c2_y

        [
          [RRCURVETO, dc1x, dc1y, dc2x, dc2y, dx, dy],
        ]
      end

      # Convert a composite glyph to CharString
      #
      # @param glyph [Object] TTF composite glyph
      # @param glyf_table [Object] TTF glyf table
      # @return [String] Type 1 CharString data
      def convert_composite_glyph(_glyph, _glyf_table)
        # For composite glyphs, we need to decompose or use seac
        # TODO: Implement proper composite handling with seac or decomposition

        # For now, return a simple placeholder
        # In a full implementation, we would:
        # 1. Extract component glyphs
        # 2. Transform and merge their outlines
        # 3. Generate combined CharString

        empty_charstring
      end

      # Encode commands to Type 1 CharString binary format
      #
      # @param commands [Array<Array<Integer>>] Array of command arrays
      # @return [String] Binary CharString data
      def encode_charstring(commands)
        bytes = []

        commands.each do |cmd|
          cmd.each do |value|
            if value.is_a?(Integer)
              bytes.concat(encode_number(value))
            end
          end
        end

        bytes.pack("C*")
      end

      # Encode a number for CharString
      #
      # Type 1 CharStrings use a variable-length encoding for integers
      #
      # @param value [Integer] Number to encode
      # @return [Array<Integer>] Array of bytes
      def encode_number(value)
        if value >= -107 && value <= 107
          # Single byte encoding: value + 139
          [value + 139]
        elsif value >= 108 && value <= 1131
          # Two byte encoding
          byte1 = ((value - 108) >> 8) + 247
          byte2 = (value - 108) & 0xFF
          [byte1, byte2]
        elsif value >= -1131 && value <= -108
          # Two byte encoding for negative
          byte1 = ((-value - 108) >> 8) + 251
          byte2 = (-value - 108) & 0xFF
          [byte1, byte2]
        elsif value >= -32768 && value <= 32767
          # Three byte encoding (16-bit signed)
          [255, value & 0xFF, (value >> 8) & 0xFF]
        else
          # Four byte encoding (32-bit)
          bytes = []
          4.times do |i|
            bytes << ((value >> (8 * i)) & 0xFF)
          end
          [255] + bytes
        end
      end

      # Generate empty CharString
      #
      # @return [String] Empty CharString data
      def empty_charstring
        # hsbw with width 0, then endchar
        [0, 500, ENDCHAR].pack("C*")
      end
    end
  end
end
