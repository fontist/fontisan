# frozen_string_literal: true

require_relative "../binary/base_record"

module Fontisan
  module Tables
    # BinData structure for the 'hhea' (Horizontal Header) table
    #
    # The hhea table contains horizontal layout metrics for the entire font.
    # It defines font-wide horizontal metrics such as ascent, descent, line
    # gap, and the number of horizontal metrics in the hmtx table.
    #
    # Reference: OpenType specification, hhea table
    # https://docs.microsoft.com/en-us/typography/opentype/spec/hhea
    #
    # @example Reading an hhea table
    #   data = File.binread("font.ttf", 36, hhea_offset)
    #   hhea = Fontisan::Tables::Hhea.read(data)
    #   puts hhea.ascent           # => 2048
    #   puts hhea.descent          # => -512
    #   puts hhea.version_number   # => 1.0
    class Hhea < Binary::BaseRecord
      # Table size in bytes (fixed size)
      TABLE_SIZE = 36

      # Version as 16.16 fixed-point (stored as int32)
      # Typically 0x00010000 (1.0)
      int32 :version_raw

      # Typographic ascent (distance from baseline to highest ascender)
      # Positive value in FUnits
      int16 :ascent

      # Typographic descent (distance from baseline to lowest descender)
      # Negative value in FUnits
      int16 :descent

      # Typographic line gap (additional space between lines)
      # Non-negative value in FUnits
      int16 :line_gap

      # Maximum advance width value in hmtx table
      uint16 :advance_width_max

      # Minimum left sidebearing value in hmtx table
      int16 :min_left_side_bearing

      # Minimum right sidebearing value in hmtx table
      int16 :min_right_side_bearing

      # Maximum extent: max(lsb + (xMax - xMin))
      int16 :x_max_extent

      # Used to calculate slope of the cursor (rise/run)
      # For vertical text: rise = 1, run = 0
      # For italic text: rise != run
      int16 :caret_slope_rise

      # Used to calculate slope of the cursor (rise/run)
      # For vertical text: run = 0
      int16 :caret_slope_run

      # Amount by which slanted highlight should be shifted
      int16 :caret_offset

      # Reserved fields (must be zero)
      # 4 x int16 = 8 bytes
      skip length: 8

      # Format of metric data (0 for current format)
      int16 :metric_data_format

      # Number of hMetric entries in hmtx table
      # Must be >= 1
      uint16 :number_of_h_metrics

      # Convert version from fixed-point to float
      #
      # @return [Float] Version number (typically 1.0)
      def version
        fixed_to_float(version_raw)
      end

      # Check if the table is valid
      #
      # @return [Boolean] True if valid, false otherwise
      def valid?
        # Version should be 1.0 (0x00010000)
        return false unless version_raw == 0x00010000

        # Metric data format must be 0
        return false unless metric_data_format.zero?

        # Number of metrics must be at least 1
        return false unless number_of_h_metrics >= 1

        true
      end

      # Validate the table and raise error if invalid
      #
      # @raise [Fontisan::CorruptedTableError] If table is invalid
      def validate!
        unless version_raw == 0x00010000
          message = "Invalid hhea version: expected 0x00010000 (1.0), " \
                    "got 0x#{version_raw.to_i.to_s(16).upcase}"
          raise Fontisan::CorruptedTableError, message
        end

        unless metric_data_format.zero?
          message = "Invalid metric data format: expected 0, " \
                    "got #{metric_data_format.to_i}"
          raise Fontisan::CorruptedTableError, message
        end

        unless number_of_h_metrics >= 1
          message = "Invalid number of h metrics: must be >= 1, " \
                    "got #{number_of_h_metrics.to_i}"
          raise Fontisan::CorruptedTableError, message
        end
      end
    end
  end
end
