# frozen_string_literal: true

require_relative "../sfnt_table"
require_relative "maxp"

module Fontisan
  module Tables
    # OOP representation of the 'maxp' (Maximum Profile) table
    #
    # The maxp table contains memory and complexity limits for the font,
    # providing the number of glyphs and various maximum values needed
    # for font rendering and processing.
    #
    # This class extends SfntTable to provide maxp-specific validation and
    # convenience methods for accessing font complexity metrics.
    #
    # @example Accessing maxp table data
    #   maxp = font.sfnt_table("maxp")
    #   maxp.num_glyphs        # => 512
    #   maxp.version           # => 1.0 or 0.5
    #   maxp.truetype?         # => true or false
    class MaxpTable < SfntTable
      # Version 0.5 constant (CFF fonts)
      VERSION_0_5 = 0x00005000

      # Version 1.0 constant (TrueType fonts)
      VERSION_1_0 = 0x00010000

      # Get maxp table version
      #
      # @return [Float, nil] Version number (0.5 or 1.0), or nil if not parsed
      def version
        return nil unless parsed

        parsed.version
      end

      # Get number of glyphs
      #
      # @return [Integer, nil] Total number of glyphs, or nil if not parsed
      def num_glyphs
        parsed&.num_glyphs
      end

      # Check if this is a TrueType font (version 1.0)
      #
      # @return [Boolean] true if version 1.0
      def truetype?
        return false unless parsed

        parsed.truetype?
      end

      # Check if this is a CFF font (version 0.5)
      #
      # @return [Boolean] true if version 0.5
      def cff?
        return false unless parsed

        parsed.cff?
      end

      # Get maximum points in a non-composite glyph (version 1.0)
      #
      # @return [Integer, nil] Maximum points, or nil if not available
      def max_points
        return nil unless parsed&.version_1_0?

        parsed.max_points
      end

      # Get maximum contours in a non-composite glyph (version 1.0)
      #
      # @return [Integer, nil] Maximum contours, or nil if not available
      def max_contours
        return nil unless parsed&.version_1_0?

        parsed.max_contours
      end

      # Get maximum points in a composite glyph (version 1.0)
      #
      # @return [Integer, nil] Maximum composite points, or nil if not available
      def max_composite_points
        return nil unless parsed&.version_1_0?

        parsed.max_composite_points
      end

      # Get maximum contours in a composite glyph (version 1.0)
      #
      # @return [Integer, nil] Maximum composite contours, or nil if not available
      def max_composite_contours
        return nil unless parsed&.version_1_0?

        parsed.max_composite_contours
      end

      # Get maximum zones (version 1.0)
      #
      # @return [Integer, nil] Maximum zones (1 or 2), or nil if not available
      def max_zones
        return nil unless parsed&.version_1_0?

        parsed.max_zones
      end

      # Get maximum twilight zone points (version 1.0)
      #
      # @return [Integer, nil] Maximum twilight points, or nil if not available
      def max_twilight_points
        return nil unless parsed&.version_1_0?

        parsed.max_twilight_points
      end

      # Get maximum storage area locations (version 1.0)
      #
      # @return [Integer, nil] Maximum storage, or nil if not available
      def max_storage
        return nil unless parsed&.version_1_0?

        parsed.max_storage
      end

      # Get maximum function definitions (version 1.0)
      #
      # @return [Integer, nil] Maximum function defs, or nil if not available
      def max_function_defs
        return nil unless parsed&.version_1_0?

        parsed.max_function_defs
      end

      # Get maximum instruction definitions (version 1.0)
      #
      # @return [Integer, nil] Maximum instruction defs, or nil if not available
      def max_instruction_defs
        return nil unless parsed&.version_1_0?

        parsed.max_instruction_defs
      end

      # Get maximum stack depth (version 1.0)
      #
      # @return [Integer, nil] Maximum stack elements, or nil if not available
      def max_stack_elements
        return nil unless parsed&.version_1_0?

        parsed.max_stack_elements
      end

      # Get maximum byte count for glyph instructions (version 1.0)
      #
      # @return [Integer, nil] Maximum instruction size, or nil if not available
      def max_size_of_instructions
        return nil unless parsed&.version_1_0?

        parsed.max_size_of_instructions
      end

      # Get maximum component elements in composite glyph (version 1.0)
      #
      # @return [Integer, nil] Maximum component elements, or nil if not available
      def max_component_elements
        return nil unless parsed&.version_1_0?

        parsed.max_component_elements
      end

      # Get maximum levels of recursion in composite glyphs (version 1.0)
      #
      # @return [Integer, nil] Maximum component depth, or nil if not available
      def max_component_depth
        return nil unless parsed&.version_1_0?

        parsed.max_component_depth
      end

      # Check if font uses composite glyphs
      #
      # @return [Boolean] true if max_component_elements > 0
      def has_composite_glyphs?
        max_comp = max_component_elements
        !max_comp.nil? && max_comp.positive?
      end

      # Check if font uses twilight zone
      #
      # @return [Boolean] true if max_zones == 2
      def has_twilight_zone?
        max_zones == 2
      end

      # Get complexity statistics
      #
      # @return [Hash] Statistics about font complexity
      def statistics
        stats = {
          num_glyphs: num_glyphs,
          version: version,
          truetype: truetype?,
          cff: cff?,
        }

        if truetype?
          stats[:max_points] = max_points
          stats[:max_contours] = max_contours
          stats[:max_composite_points] = max_composite_points
          stats[:max_composite_contours] = max_composite_contours
          stats[:max_component_elements] = max_component_elements
          stats[:max_component_depth] = max_component_depth
          stats[:has_composite_glyphs] = has_composite_glyphs?
          stats[:has_twilight_zone] = has_twilight_zone?
        end

        stats
      end

      protected

      # Validate the parsed maxp table
      #
      # @return [Boolean] true if valid
      # @raise [InvalidFontError] if maxp table is invalid
      def validate_parsed_table?
        return true unless parsed

        # Validate version
        unless parsed.valid_version?
          raise InvalidFontError,
                "Invalid maxp table version: #{parsed.version} " \
                "(must be 0.5 or 1.0)"
        end

        # Validate number of glyphs
        unless parsed.valid_num_glyphs?
          raise InvalidFontError,
                "Invalid maxp num_glyphs: #{parsed.num_glyphs} (must be >= 1)"
        end

        # Validate max zones
        unless parsed.valid_max_zones?
          raise InvalidFontError,
                "Invalid maxp max_zones: #{parsed.max_zones} (must be 1 or 2)"
        end

        # Validate metrics are reasonable
        unless parsed.reasonable_metrics?
          raise InvalidFontError,
                "Invalid maxp metrics: values exceed reasonable limits"
        end

        true
      end
    end
  end
end
