# frozen_string_literal: true

require_relative "../binary/base_record"

module Fontisan
  module Tables
    # BinData structure for the 'maxp' (Maximum Profile) table
    #
    # The maxp table contains memory and complexity limits for the font.
    # It provides the number of glyphs and various maximum values needed
    # for font rendering and processing.
    #
    # The table has two versions:
    # - Version 0.5 (0x00005000): CFF fonts - only version and numGlyphs
    # - Version 1.0 (0x00010000): TrueType fonts - includes additional fields
    #
    # Version 1.0 fields provide information about:
    # - Glyph outline complexity (points, contours)
    # - Composite glyph structure
    # - TrueType instruction limitations
    #
    # Reference: OpenType specification, maxp table
    # https://docs.microsoft.com/en-us/typography/opentype/spec/maxp
    #
    # @example Reading a maxp table
    #   data = File.binread("font.ttf", size, maxp_offset)
    #   maxp = Fontisan::Tables::Maxp.read(data)
    #   puts maxp.num_glyphs       # => 512
    #   puts maxp.version          # => 1.0 or 0.5
    #   puts maxp.truetype?        # => true or false
    class Maxp < Binary::BaseRecord
      # Version 0.5 constant (CFF fonts)
      VERSION_0_5 = 0x00005000

      # Version 1.0 constant (TrueType fonts)
      VERSION_1_0 = 0x00010000

      # Minimum table size for version 0.5 (4 + 2 = 6 bytes)
      TABLE_SIZE_V0_5 = 6

      # Full table size for version 1.0 (4 + 2 + 13×2 = 32 bytes)
      TABLE_SIZE_V1_0 = 32

      # Version as 16.16 fixed-point (stored as int32)
      # 0x00010000 for version 1.0 (TrueType)
      # 0x00005000 for version 0.5 (CFF)
      int32 :version_raw

      # Total number of glyphs in the font
      # Must be >= 1 (at minimum, .notdef must be present)
      uint16 :num_glyphs

      # The following fields are only present in version 1.0 (TrueType fonts)

      # Maximum points in a non-composite glyph
      uint16 :max_points, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum contours in a non-composite glyph
      uint16 :max_contours, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum points in a composite glyph
      uint16 :max_composite_points, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum contours in a composite glyph
      uint16 :max_composite_contours, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum zones (1 or 2, depending on instructions)
      # 1 = no twilight zone, 2 = twilight zone present
      uint16 :max_zones, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum points used in twilight zone (Z0)
      uint16 :max_twilight_points, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum storage area locations
      uint16 :max_storage, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum function definitions
      uint16 :max_function_defs, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum instruction definitions
      uint16 :max_instruction_defs, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum stack depth
      uint16 :max_stack_elements, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum byte count for glyph instructions
      uint16 :max_size_of_instructions, onlyif: -> {
        version_raw == VERSION_1_0
      }

      # Maximum component elements in a composite glyph
      uint16 :max_component_elements, onlyif: -> { version_raw == VERSION_1_0 }

      # Maximum levels of recursion in composite glyphs
      # 0 if font has no composite glyphs
      uint16 :max_component_depth, onlyif: -> { version_raw == VERSION_1_0 }

      # Convert version from fixed-point to float
      #
      # Version 0.5 (0x00005000) is a special case, not standard 16.16 fixed-point
      #
      # @return [Float] Version number (1.0 or 0.5)
      def version
        case version_raw
        when VERSION_0_5
          0.5
        when VERSION_1_0
          1.0
        else
          fixed_to_float(version_raw)
        end
      end

      # Check if this is version 1.0 (TrueType)
      #
      # @return [Boolean] True if version 1.0, false otherwise
      def version_1_0?
        version_raw == VERSION_1_0
      end

      # Check if this is version 0.5 (CFF)
      #
      # @return [Boolean] True if version 0.5, false otherwise
      def version_0_5?
        version_raw == VERSION_0_5
      end

      # Check if this is a TrueType font (alias for version_1_0?)
      #
      # @return [Boolean] True if TrueType font, false otherwise
      def truetype?
        version_1_0?
      end

      # Check if this is a CFF font (alias for version_0_5?)
      #
      # @return [Boolean] True if CFF font, false otherwise
      def cff?
        version_0_5?
      end

      # Check if the table is valid
      #
      # @return [Boolean] True if valid, false otherwise
      def valid?
        # Version must be either 0.5 or 1.0
        return false unless version_0_5? || version_1_0?

        # Number of glyphs must be at least 1
        return false unless num_glyphs >= 1

        # For version 1.0, maxZones must be 1 or 2
        if version_1_0? && max_zones && !(max_zones >= 1 && max_zones <= 2)
          return false
        end

        true
      end

      # Validation helper: Check if version is valid (0.5 or 1.0)
      #
      # @return [Boolean] True if version is 0.5 or 1.0
      def valid_version?
        version_0_5? || version_1_0?
      end

      # Validation helper: Check if number of glyphs is valid
      #
      # Must be at least 1 (.notdef glyph must exist)
      #
      # @return [Boolean] True if num_glyphs >= 1
      def valid_num_glyphs?
        num_glyphs && num_glyphs >= 1
      end

      # Validation helper: Check if maxZones is valid (version 1.0 only)
      #
      # For TrueType fonts, maxZones must be 1 or 2
      #
      # @return [Boolean] True if maxZones is valid or not applicable
      def valid_max_zones?
        return true if version_0_5? # Not applicable for CFF

        max_zones&.between?(1, 2)
      end

      # Validation helper: Check if all TrueType metrics are present
      #
      # For version 1.0, all max* fields should be present
      #
      # @return [Boolean] True if all required fields are present
      def has_truetype_metrics?
        version_1_0? &&
          !max_points.nil? &&
          !max_contours.nil? &&
          !max_composite_points.nil? &&
          !max_composite_contours.nil?
      end

      # Validation helper: Check if metrics are reasonable
      #
      # Checks that values don't exceed reasonable limits
      #
      # @return [Boolean] True if metrics are within reasonable bounds
      def reasonable_metrics?
        # num_glyphs should not exceed 65535
        return false if num_glyphs > 65535

        if version_1_0?
          # Check reasonable limits for TrueType metrics
          # These are generous limits to allow for complex fonts
          return false if max_points && max_points > 50000
          return false if max_contours && max_contours > 10000
          return false if max_stack_elements && max_stack_elements > 1000
        end

        true
      end

      # Validate the table and raise error if invalid
      #
      # @raise [Fontisan::CorruptedTableError] If table is invalid
      def validate_structure!
        unless version_0_5? || version_1_0?
          raise Fontisan::CorruptedTableError,
                "Invalid maxp version: expected 0x00005000 (0.5) or " \
                "0x00010000 (1.0), got 0x#{version_raw.to_s(16).upcase}"
        end

        unless num_glyphs >= 1
          raise Fontisan::CorruptedTableError,
                "Invalid number of glyphs: must be >= 1, got #{num_glyphs}"
        end

        if version_1_0? && max_zones && (max_zones < 1 || max_zones > 2)
          raise Fontisan::CorruptedTableError,
                "Invalid maxZones: must be 1 or 2, got #{max_zones}"
        end
      end

      # Alias for compatibility
      alias validate! validate_structure!

      # Get the expected table size based on version
      #
      # @return [Integer] Expected size in bytes
      def expected_size
        version_1_0? ? TABLE_SIZE_V1_0 : TABLE_SIZE_V0_5
      end
    end
  end
end
