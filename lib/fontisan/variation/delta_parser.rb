# frozen_string_literal: true

require "stringio"

module Fontisan
  module Variation
    # Parses variation deltas from gvar tuple data
    #
    # The gvar table stores deltas in various compression formats to minimize
    # file size. This parser handles all delta formats and decompresses them
    # into usable point delta arrays.
    #
    # Delta Formats:
    # - DELTAS_ARE_ZERO: All deltas are zero (no data stored)
    # - DELTAS_ARE_WORDS: Deltas stored as signed 16-bit words
    # - DELTAS_ARE_BYTES: Deltas stored as signed 8-bit bytes
    # - Point number runs: Compressed sequences of affected points
    #
    # Reference: OpenType specification, gvar table delta encoding
    #
    # @example Parsing delta data
    #   parser = Fontisan::Variation::DeltaParser.new
    #   deltas = parser.parse(tuple_data, point_count)
    #   # Returns: [{ x: 10, y: 5 }, { x: -3, y: 2 }, ...]
    class DeltaParser
      # Delta format flags (from tuple variation header flags)
      DELTAS_ARE_ZERO = 0x80
      DELTAS_ARE_WORDS = 0x40

      # Point number flags
      POINTS_ARE_WORDS = 0x80
      POINT_RUN_COUNT_MASK = 0x7F

      # Parse delta data from tuple variation
      #
      # @param data [String] Binary delta data
      # @param point_count [Integer] Total number of points in glyph
      # @param private_points [Boolean] Whether tuple has private point numbers
      # @param shared_points [Array<Integer>, nil] Shared point numbers if applicable
      # @return [Array<Hash>] Array of point deltas { x:, y: }
      # @raise [VariationDataCorruptedError] If delta data is corrupted or cannot be parsed
      def parse(data, point_count, private_points: false, shared_points: nil)
        return zero_deltas(point_count) if data.nil? || data.empty?

        io = StringIO.new(data)
        io.set_encoding(Encoding::BINARY)

        # Parse point numbers if present
        points = if private_points
                   parse_point_numbers(io)
                 elsif shared_points
                   shared_points
                 else
                   # All points affected
                   (0...point_count).to_a
                 end

        # Determine delta format from first byte (if present)
        format_byte = io.getbyte
        return zero_deltas(point_count) if format_byte.nil?

        io.pos -= 1 # Put byte back

        # Parse X deltas
        x_deltas = parse_delta_array(io, points.length)

        # Parse Y deltas
        y_deltas = parse_delta_array(io, points.length)

        # Build full delta array (zero for untouched points)
        build_full_deltas(points, x_deltas, y_deltas, point_count)
      rescue StandardError => e
        raise VariationDataCorruptedError.new(
          message: "Failed to parse delta data: #{e.message}",
          details: {
            point_count: point_count,
            private_points: private_points,
            error_class: e.class.name,
          },
        )
      end

      # Parse delta data with explicit format flag
      #
      # @param data [String] Binary delta data
      # @param point_count [Integer] Total number of points
      # @param flags [Integer] Tuple variation flags
      # @return [Array<Hash>] Array of point deltas
      def parse_with_flags(data, point_count, flags)
        if (flags & DELTAS_ARE_ZERO).zero?
          parse(data, point_count)
        else
          zero_deltas(point_count)
        end
      end

      private

      # Parse point numbers from packed format
      #
      # Point numbers indicate which points have deltas. Uses run-length
      # encoding to compress sequences of point numbers.
      #
      # @param io [StringIO] Input stream
      # @return [Array<Integer>] Array of point numbers
      def parse_point_numbers(io)
        points = []
        first_byte = io.getbyte
        return points if first_byte.nil?

        # First byte indicates total number of point numbers
        total_points = first_byte

        # Parse all point number runs
        point_index = 0
        remaining = total_points

        while remaining.positive?
          control = io.getbyte
          return points if control.nil?

          # Number of points in this run
          run_count = (control & POINT_RUN_COUNT_MASK) + 1

          # Limit run_count to remaining points
          run_count = [run_count, remaining].min

          if (control & POINTS_ARE_WORDS).zero?
            # Points stored as 8-bit bytes (deltas from previous)
            run_count.times do
              byte = io.getbyte
              return points if byte.nil?

              point_index += byte
              points << point_index
              remaining -= 1
            end
          else
            # Points stored as 16-bit words
            run_count.times do
              bytes = io.read(2)
              return points if bytes.nil? || bytes.bytesize < 2

              point = bytes.unpack1("n")
              points << point
              point_index = point
              remaining -= 1
            end
          end
        end

        points
      end

      # Parse an array of delta values
      #
      # Deltas can be stored as bytes or words depending on value range.
      # The format is determined by inspecting the first byte.
      #
      # @param io [StringIO] Input stream
      # @param count [Integer] Number of deltas to parse
      # @return [Array<Integer>] Array of delta values
      def parse_delta_array(io, count)
        return [] if count.zero?

        deltas = []

        # Read control byte to determine format
        control = io.getbyte
        return deltas if control.nil?

        if (control & DELTAS_ARE_WORDS).zero?
          # Deltas stored as 8-bit signed bytes
          count.times do
            byte = io.getbyte
            return deltas if byte.nil?

            signed = byte > 0x7F ? byte - 0x100 : byte
            deltas << signed
          end
        else
          # Deltas stored as 16-bit signed words
          count.times do
            bytes = io.read(2)
            return deltas if bytes.nil? || bytes.bytesize < 2

            value = bytes.unpack1("n")
            signed = value > 0x7FFF ? value - 0x10000 : value
            deltas << signed
          end
        end

        deltas
      end

      # Build full delta array including untouched points
      #
      # @param points [Array<Integer>] Point numbers with deltas
      # @param x_deltas [Array<Integer>] X deltas
      # @param y_deltas [Array<Integer>] Y deltas
      # @param point_count [Integer] Total points in glyph
      # @return [Array<Hash>] Full delta array
      def build_full_deltas(points, x_deltas, y_deltas, point_count)
        full_deltas = Array.new(point_count) { { x: 0, y: 0 } }

        points.each_with_index do |point_num, i|
          next if point_num >= point_count
          next if i >= x_deltas.length || i >= y_deltas.length

          full_deltas[point_num] = {
            x: x_deltas[i],
            y: y_deltas[i],
          }
        end

        full_deltas
      end

      # Create array of zero deltas
      #
      # @param count [Integer] Number of deltas
      # @return [Array<Hash>] Array of zero deltas
      def zero_deltas(count)
        Array.new(count) { { x: 0, y: 0 } }
      end
    end
  end
end
