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

      # Validation helper: Check if version is valid
      #
      # OpenType spec requires version to be 1.0
      #
      # @return [Boolean] True if version is 1.0
      def valid_version?
        version_raw == 0x00010000
      end

      # Validation helper: Check if metric data format is valid
      #
      # Must be 0 for current format
      #
      # @return [Boolean] True if format is 0
      def valid_metric_data_format?
        metric_data_format.zero?
      end

      # Validation helper: Check if number of h metrics is valid
      #
      # Must be at least 1
      #
      # @return [Boolean] True if number_of_h_metrics >= 1
      def valid_number_of_h_metrics?
        number_of_h_metrics && number_of_h_metrics >= 1
      end

      # Validation helper: Check if ascent/descent values are reasonable
      #
      # Ascent should be positive, descent should be negative
      #
      # @return [Boolean] True if ascent/descent have correct signs
      def valid_ascent_descent?
        ascent.positive? && descent.negative?
      end

      # Validation helper: Check if line gap is non-negative
      #
      # Line gap should be >= 0
      #
      # @return [Boolean] True if line_gap >= 0
      def valid_line_gap?
        line_gap >= 0
      end

      # Validation helper: Check if advance width max is positive
      #
      # Maximum advance width should be > 0
      #
      # @return [Boolean] True if advance_width_max > 0
      def valid_advance_width_max?
        advance_width_max&.positive?
      end

      # Validation helper: Check if caret slope is valid
      #
      # For vertical text: rise=1, run=0
      # For horizontal italic: both should be non-zero
      #
      # @return [Boolean] True if caret slope values are sensible
      def valid_caret_slope?
        # At least one should be non-zero
        caret_slope_rise != 0 || caret_slope_run != 0
      end

      # Validation helper: Check if extent is reasonable
      #
      # x_max_extent should be positive
      #
      # @return [Boolean] True if x_max_extent > 0
      def valid_x_max_extent?
        x_max_extent.positive?
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
