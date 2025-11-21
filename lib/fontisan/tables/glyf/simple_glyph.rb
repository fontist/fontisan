# frozen_string_literal: true

module Fontisan
  module Tables
    # Represents a simple TrueType glyph with contours
    #
    # A simple glyph is defined by one or more contours, where each contour
    # is a closed path made up of on-curve and off-curve points. The points
    # are stored using delta encoding to save space.
    #
    # The glyph structure consists of:
    # - Header: numberOfContours, xMin, yMin, xMax, yMax (10 bytes)
    # - endPtsOfContours: array marking the last point of each contour
    # - instructions: TrueType hinting instructions (optional)
    # - flags: array of point flags (compressed with repeat counts)
    # - xCoordinates: x-coordinates (delta-encoded, variable byte length)
    # - yCoordinates: y-coordinates (delta-encoded, variable byte length)
    #
    # Point flags (8-bit) indicate:
    # - Bit 0 (0x01): ON_CURVE_POINT - point is on the curve
    # - Bit 1 (0x02): X_SHORT_VECTOR - x-coordinate is 1 byte
    # - Bit 2 (0x04): Y_SHORT_VECTOR - y-coordinate is 1 byte
    # - Bit 3 (0x08): REPEAT_FLAG - repeat this flag n times
    # - Bit 4 (0x10): X_IS_SAME_OR_POSITIVE_X_SHORT - x value interpretation
    # - Bit 5 (0x20): Y_IS_SAME_OR_POSITIVE_Y_SHORT - y value interpretation
    #
    # Reference: OpenType specification, glyf table - Simple Glyph Description
    # https://docs.microsoft.com/en-us/typography/opentype/spec/glyf#simple-glyph-description
    class SimpleGlyph
      # Flag constants
      ON_CURVE_POINT = 0x01
      X_SHORT_VECTOR = 0x02
      Y_SHORT_VECTOR = 0x04
      REPEAT_FLAG = 0x08
      X_IS_SAME_OR_POSITIVE_X_SHORT = 0x10
      Y_IS_SAME_OR_POSITIVE_Y_SHORT = 0x20

      # Glyph header fields
      attr_reader :glyph_id
      attr_reader :num_contours, :x_min, :y_min, :x_max, :y_max,
                  :instruction_length, :instructions, :flags, :x_coordinates, :y_coordinates

      # Glyph data fields
      attr_reader :end_pts_of_contours

      # Parse simple glyph data
      #
      # @param data [String] Binary glyph data
      # @param glyph_id [Integer] Glyph ID for error reporting
      # @return [SimpleGlyph] Parsed simple glyph
      # @raise [Fontisan::CorruptedTableError] If data is insufficient or invalid
      def self.parse(data, glyph_id)
        glyph = new(glyph_id)
        glyph.parse_data(data)
        glyph
      end

      # Initialize a new simple glyph
      #
      # @param glyph_id [Integer] Glyph ID
      def initialize(glyph_id)
        @glyph_id = glyph_id
      end

      # Parse glyph data
      #
      # @param data [String] Binary glyph data
      # @raise [Fontisan::CorruptedTableError] If parsing fails
      def parse_data(data)
        io = StringIO.new(data)
        io.set_encoding(Encoding::BINARY)

        parse_header(io)
        parse_contour_ends(io)
        parse_instructions(io)
        parse_flags(io)
        parse_coordinates(io)

        validate_parsed_data!
      end

      # Check if this is a simple glyph
      #
      # @return [Boolean] Always true for SimpleGlyph
      def simple?
        true
      end

      # Check if this is a compound glyph
      #
      # @return [Boolean] Always false for SimpleGlyph
      def compound?
        false
      end

      # Check if glyph has no outline data
      #
      # @return [Boolean] True if no contours
      def empty?
        num_contours.zero?
      end

      # Get bounding box as array
      #
      # @return [Array<Integer>] Bounding box [xMin, yMin, xMax, yMax]
      def bounding_box
        [x_min, y_min, x_max, y_max]
      end

      # Get total number of points
      #
      # @return [Integer] Total points in all contours
      def num_points
        return 0 if empty?

        end_pts_of_contours.last + 1
      end

      # Check if a specific point is on the curve
      #
      # @param index [Integer] Point index (0-based)
      # @return [Boolean, nil] True if on curve, false if off curve, nil if invalid
      def on_curve?(index)
        return nil if index.negative? || index >= num_points

        (flags[index] & ON_CURVE_POINT) != 0
      end

      # Get contour for a specific point
      #
      # @param point_index [Integer] Point index (0-based)
      # @return [Integer, nil] Contour index (0-based) or nil if invalid
      def contour_for_point(point_index)
        return nil if point_index.negative? || point_index >= num_points

        end_pts_of_contours.index { |end_pt| point_index <= end_pt }
      end

      # Get all points for a specific contour
      #
      # @param contour_index [Integer] Contour index (0-based)
      # @return [Array<Hash>, nil] Array of point hashes or nil if invalid
      def points_for_contour(contour_index)
        return nil if contour_index.negative? || contour_index >= num_contours

        start_pt = contour_index.zero? ? 0 : end_pts_of_contours[contour_index - 1] + 1
        end_pt = end_pts_of_contours[contour_index]

        (start_pt..end_pt).map do |i|
          {
            x: x_coordinates[i],
            y: y_coordinates[i],
            on_curve: on_curve?(i),
          }
        end
      end

      private

      # Parse glyph header (10 bytes)
      #
      # @param io [StringIO] Input stream
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_header(io)
        header = io.read(10)
        if header.nil? || header.length < 10
          raise Fontisan::CorruptedTableError,
                "Insufficient header data for simple glyph #{glyph_id}"
        end

        values = header.unpack("n5")
        @num_contours = to_signed_16(values[0])
        @x_min = to_signed_16(values[1])
        @y_min = to_signed_16(values[2])
        @x_max = to_signed_16(values[3])
        @y_max = to_signed_16(values[4])

        if @num_contours.negative?
          raise Fontisan::CorruptedTableError,
                "Simple glyph #{glyph_id} has negative contour count: #{@num_contours}"
        end
      end

      # Parse contour end points
      #
      # @param io [StringIO] Input stream
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_contour_ends(io)
        return if num_contours.zero?

        data = io.read(num_contours * 2)
        if data.nil? || data.length < num_contours * 2
          raise Fontisan::CorruptedTableError,
                "Insufficient contour end data for simple glyph #{glyph_id}"
        end

        @end_pts_of_contours = data.unpack("n*")
      end

      # Parse TrueType instructions
      #
      # @param io [StringIO] Input stream
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_instructions(io)
        length_data = io.read(2)
        if length_data.nil? || length_data.length < 2
          raise Fontisan::CorruptedTableError,
                "Insufficient instruction length data for simple glyph #{glyph_id}"
        end

        @instruction_length = length_data.unpack1("n")

        if @instruction_length.positive?
          @instructions = io.read(@instruction_length)
          if @instructions.nil? || @instructions.length < @instruction_length
            raise Fontisan::CorruptedTableError,
                  "Insufficient instruction data for simple glyph #{glyph_id}"
          end
        else
          @instructions = "".b
        end
      end

      # Parse flags with repeat compression
      #
      # Flags use run-length encoding: when REPEAT_FLAG is set,
      # the next byte indicates how many times to repeat the flag.
      #
      # @param io [StringIO] Input stream
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_flags(io)
        return if num_contours.zero?

        total_points = num_points
        @flags = []

        while @flags.length < total_points
          flag_byte = io.read(1)
          if flag_byte.nil? || flag_byte.empty?
            raise Fontisan::CorruptedTableError,
                  "Insufficient flag data for simple glyph #{glyph_id}"
          end

          flag = flag_byte.unpack1("C")
          @flags << flag

          # Check for repeat flag
          if (flag & REPEAT_FLAG) != 0
            repeat_count = io.read(1)
            if repeat_count.nil? || repeat_count.empty?
              raise Fontisan::CorruptedTableError,
                    "Missing repeat count for simple glyph #{glyph_id}"
            end

            count = repeat_count.unpack1("C")
            count.times { @flags << flag }
          end
        end

        if @flags.length != total_points
          raise Fontisan::CorruptedTableError,
                "Flag count mismatch for simple glyph #{glyph_id}: " \
                "expected #{total_points}, got #{@flags.length}"
        end
      end

      # Parse x and y coordinates with delta encoding
      #
      # Coordinates are delta-encoded from the previous point.
      # The flag indicates whether coordinates are 1 byte (short) or 2 bytes.
      # For short coordinates, another flag bit indicates sign.
      # For long coordinates, a flag bit indicates if the value is same as previous (delta=0).
      #
      # @param io [StringIO] Input stream
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_coordinates(io)
        return if num_contours.zero?

        @x_coordinates = parse_coordinate_array(io, :x)
        @y_coordinates = parse_coordinate_array(io, :y)
      end

      # Parse a coordinate array (x or y)
      #
      # @param io [StringIO] Input stream
      # @param axis [:x, :y] Which axis to parse
      # @return [Array<Integer>] Absolute coordinates
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_coordinate_array(io, axis)
        short_flag = axis == :x ? X_SHORT_VECTOR : Y_SHORT_VECTOR
        same_or_positive_flag = axis == :x ? X_IS_SAME_OR_POSITIVE_X_SHORT : Y_IS_SAME_OR_POSITIVE_Y_SHORT

        coordinates = []
        current = 0

        flags.each_with_index do |flag, i|
          if (flag & short_flag) != 0
            # Short coordinate (1 byte, unsigned)
            byte = io.read(1)
            if byte.nil? || byte.empty?
              raise Fontisan::CorruptedTableError,
                    "Insufficient #{axis} coordinate data for simple glyph #{glyph_id} at point #{i}"
            end

            value = byte.unpack1("C")
            # Sign determination: if same_or_positive_flag is set, value is positive; otherwise negative
            delta = (flag & same_or_positive_flag).zero? ? -value : value
          elsif (flag & same_or_positive_flag) != 0
            # Same as previous (delta = 0)
            delta = 0
          else
            # Long coordinate (2 bytes, signed)
            bytes = io.read(2)
            if bytes.nil? || bytes.length < 2
              raise Fontisan::CorruptedTableError,
                    "Insufficient #{axis} coordinate data for simple glyph #{glyph_id} at point #{i}"
            end

            delta = to_signed_16(bytes.unpack1("n"))
          end

          current += delta
          coordinates << current
        end

        coordinates
      end

      # Validate parsed data consistency
      #
      # @raise [Fontisan::CorruptedTableError] If validation fails
      def validate_parsed_data!
        return if num_contours.zero?

        # Check that we have correct number of points
        expected_points = num_points
        if flags.length != expected_points
          raise Fontisan::CorruptedTableError,
                "Point count mismatch for simple glyph #{glyph_id}: " \
                "expected #{expected_points} points, got #{flags.length} flags"
        end

        if x_coordinates.length != expected_points
          raise Fontisan::CorruptedTableError,
                "X coordinate count mismatch for simple glyph #{glyph_id}: " \
                "expected #{expected_points}, got #{x_coordinates.length}"
        end

        if y_coordinates.length != expected_points
          raise Fontisan::CorruptedTableError,
                "Y coordinate count mismatch for simple glyph #{glyph_id}: " \
                "expected #{expected_points}, got #{y_coordinates.length}"
        end

        # Check that contour end points are monotonically increasing
        end_pts_of_contours.each_cons(2) do |prev, curr|
          if curr <= prev
            raise Fontisan::CorruptedTableError,
                  "Invalid contour end points for simple glyph #{glyph_id}: " \
                  "not monotonically increasing"
          end
        end

        # Check that last contour end point matches total points
        last_end_pt = end_pts_of_contours.last
        if last_end_pt != expected_points - 1
          raise Fontisan::CorruptedTableError,
                "Last contour end point mismatch for simple glyph #{glyph_id}: " \
                "expected #{expected_points - 1}, got #{last_end_pt}"
        end
      end

      # Convert unsigned 16-bit value to signed
      #
      # @param value [Integer] Unsigned 16-bit value
      # @return [Integer] Signed 16-bit value
      def to_signed_16(value)
        value > 0x7FFF ? value - 0x10000 : value
      end
    end
  end
end
