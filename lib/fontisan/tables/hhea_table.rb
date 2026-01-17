# frozen_string_literal: true

require_relative "../sfnt_table"
require_relative "hhea"

module Fontisan
  module Tables
    # OOP representation of the 'hhea' (Horizontal Header) table
    #
    # The hhea table contains horizontal layout metrics for the entire font,
    # defining font-wide horizontal metrics such as ascent, descent, line gap,
    # and the number of horizontal metrics in the hmtx table.
    #
    # This class extends SfntTable to provide hhea-specific validation and
    # convenience methods for accessing common hhea table fields.
    #
    # @example Accessing hhea table data
    #   hhea = font.sfnt_table("hhea")
    #   hhea.ascent            # => 2048
    #   hhea.descent           # => -512
    #   hhea.line_gap          # => 0
    #   hhea.line_height       # => 2560
    class HheaTable < SfntTable
      # Fixed value 0x00010000 for version 1.0
      VERSION_1_0 = 0x00010000

      # Get hhea table version
      #
      # @return [Float, nil] Version number (typically 1.0), or nil if not parsed
      def version
        return nil unless parsed

        parsed.version
      end

      # Get typographic ascent
      #
      # Distance from baseline to highest ascender (positive value)
      #
      # @return [Integer, nil] Ascent in FUnits, or nil if not parsed
      def ascent
        parsed&.ascent
      end

      # Get typographic descent
      #
      # Distance from baseline to lowest descender (negative value)
      #
      # @return [Integer, nil] Descent in FUnits, or nil if not parsed
      def descent
        parsed&.descent
      end

      # Get typographic line gap
      #
      # Additional space between lines (non-negative value)
      #
      # @return [Integer, nil] Line gap in FUnits, or nil if not parsed
      def line_gap
        parsed&.line_gap
      end

      # Get total line height
      #
      # Calculated as ascent - descent + line_gap
      #
      # @return [Integer, nil] Line height in FUnits, or nil if not parsed
      def line_height
        return nil unless parsed

        ascent - descent + line_gap
      end

      # Get maximum advance width
      #
      # Maximum advance width value in hmtx table
      #
      # @return [Integer, nil] Maximum advance width, or nil if not parsed
      def advance_width_max
        parsed&.advance_width_max
      end

      # Get minimum left sidebearing
      #
      # @return [Integer, nil] Minimum lsb value, or nil if not parsed
      def min_left_side_bearing
        parsed&.min_left_side_bearing
      end

      # Get minimum right sidebearing
      #
      # @return [Integer, nil] Minimum rsb value, or nil if not parsed
      def min_right_side_bearing
        parsed&.min_right_side_bearing
      end

      # Get maximum x extent
      #
      # Maximum of lsb + (xMax - xMin) for all glyphs
      #
      # @return [Integer, nil] Maximum extent, or nil if not parsed
      def x_max_extent
        parsed&.x_max_extent
      end

      # Get caret slope rise
      #
      # Used to calculate slope of cursor (rise/run)
      # For vertical text: rise = 1, run = 0
      #
      # @return [Integer, nil] Caret slope rise, or nil if not parsed
      def caret_slope_rise
        parsed&.caret_slope_rise
      end

      # Get caret slope run
      #
      # Used to calculate slope of cursor (rise/run)
      # For vertical text: run = 0
      #
      # @return [Integer, nil] Caret slope run, or nil if not parsed
      def caret_slope_run
        parsed&.caret_slope_run
      end

      # Get caret offset
      #
      # Amount by which slanted highlight should be shifted
      #
      # @return [Integer, nil] Caret offset, or nil if not parsed
      def caret_offset
        parsed&.caret_offset
      end

      # Get metric data format
      #
      # Format of metric data (0 for current format)
      #
      # @return [Integer, nil] Metric data format, or nil if not parsed
      def metric_data_format
        parsed&.metric_data_format
      end

      # Get number of hmetrics
      #
      # Number of hMetric entries in hmtx table
      #
      # @return [Integer, nil] Number of metrics (must be >= 1), or nil if not parsed
      def number_of_h_metrics
        parsed&.number_of_h_metrics
      end

      # Check if caret is vertical
      #
      # @return [Boolean] true if caret is vertical (rise != 0, run == 0)
      def vertical_caret?
        return false unless parsed

        caret_slope_rise != 0 && caret_slope_run.zero?
      end

      # Check if caret is italic
      #
      # @return [Boolean] true if caret is slanted (both rise and run non-zero)
      def italic_caret?
        return false unless parsed

        caret_slope_rise != 0 && caret_slope_run != 0
      end

      # Check if caret is horizontal
      #
      # @return [Boolean] true if caret is horizontal (rise == 0, run != 0)
      def horizontal_caret?
        return false unless parsed

        caret_slope_rise.zero? && caret_slope_run != 0
      end

      # Get caret angle in degrees
      #
      # @return [Float, nil] Caret angle in degrees, or nil if not parsed
      def caret_angle
        return nil unless parsed

        return 0.0 if caret_slope_run.zero?

        Math.atan2(caret_slope_rise, caret_slope_run) * (180.0 / Math::PI)
      end

      protected

      # Validate the parsed hhea table
      #
      # @return [Boolean] true if valid
      # @raise [InvalidFontError] if hhea table is invalid
      def validate_parsed_table?
        return true unless parsed

        # Validate version
        unless parsed.valid_version?
          raise InvalidFontError,
                "Invalid hhea table version: expected 0x00010000 (1.0), " \
                "got 0x#{parsed.version_raw.to_s(16).upcase}"
        end

        # Validate metric data format
        unless parsed.valid_metric_data_format?
          raise InvalidFontError,
                "Invalid hhea metric data format: #{parsed.metric_data_format} (must be 0)"
        end

        # Validate number of h metrics
        unless parsed.valid_number_of_h_metrics?
          raise InvalidFontError,
                "Invalid hhea number_of_h_metrics: #{parsed.number_of_h_metrics} (must be >= 1)"
        end

        # Validate ascent/descent
        unless parsed.valid_ascent_descent?
          raise InvalidFontError,
                "Invalid hhea ascent/descent: ascent=#{parsed.ascent}, " \
                "descent=#{parsed.descent} (ascent must be positive, descent must be negative)"
        end

        # Validate line gap
        unless parsed.valid_line_gap?
          raise InvalidFontError,
                "Invalid hhea line_gap: #{parsed.line_gap} (must be >= 0)"
        end

        # Validate advance width max
        unless parsed.valid_advance_width_max?
          raise InvalidFontError,
                "Invalid hhea advance_width_max: #{parsed.advance_width_max} (must be > 0)"
        end

        # Validate caret slope
        unless parsed.valid_caret_slope?
          raise InvalidFontError,
                "Invalid hhea caret slope: rise=#{parsed.caret_slope_rise}, " \
                "run=#{parsed.caret_slope_run} (at least one must be non-zero)"
        end

        # Validate x max extent
        unless parsed.valid_x_max_extent?
          raise InvalidFontError,
                "Invalid hhea x_max_extent: #{parsed.x_max_extent} (must be > 0)"
        end

        true
      end
    end
  end
end
