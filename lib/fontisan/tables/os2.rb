# frozen_string_literal: true

module Fontisan
  module Tables
    # Parser for the 'OS/2' (OS/2 and Windows Metrics) table
    #
    # The OS/2 table contains OS/2 and Windows-specific metrics that are
    # required by Windows and OS/2. This includes font metrics, character
    # ranges, vendor information, and embedding permissions.
    #
    # The table has evolved through multiple versions (0-5), with newer
    # versions adding additional fields while maintaining backward
    # compatibility.
    #
    # Reference: OpenType specification, OS/2 table
    class Os2 < Binary::BaseRecord
      endian :big

      # Version 0 fields (all versions have these)
      uint16 :version
      int16 :x_avg_char_width
      uint16 :us_weight_class
      uint16 :us_width_class
      uint16 :fs_type
      int16 :y_subscript_x_size
      int16 :y_subscript_y_size
      int16 :y_subscript_x_offset
      int16 :y_subscript_y_offset
      int16 :y_superscript_x_size
      int16 :y_superscript_y_size
      int16 :y_superscript_x_offset
      int16 :y_superscript_y_offset
      int16 :y_strikeout_size
      int16 :y_strikeout_position
      int16 :s_family_class

      # PANOSE - 10 bytes
      array :panose, type: :uint8, initial_length: 10

      # Unicode ranges
      uint32 :ul_unicode_range1
      uint32 :ul_unicode_range2
      uint32 :ul_unicode_range3
      uint32 :ul_unicode_range4

      # Vendor ID - 4 bytes
      string :ach_vend_id, length: 4

      # Selection flags and character indices
      uint16 :fs_selection
      uint16 :us_first_char_index
      uint16 :us_last_char_index
      int16 :s_typo_ascender
      int16 :s_typo_descender
      int16 :s_typo_line_gap
      uint16 :us_win_ascent
      uint16 :us_win_descent

      # Version 1+ fields
      uint32 :ul_code_page_range1, onlyif: -> { version >= 1 }
      uint32 :ul_code_page_range2, onlyif: -> { version >= 1 }

      # Version 2+ fields
      int16 :sx_height, onlyif: -> { version >= 2 }
      int16 :s_cap_height, onlyif: -> { version >= 2 }
      uint16 :us_default_char, onlyif: -> { version >= 2 }
      uint16 :us_break_char, onlyif: -> { version >= 2 }
      uint16 :us_max_context, onlyif: -> { version >= 2 }

      # Version 5+ fields
      uint16 :us_lower_optical_point_size, onlyif: -> { version >= 5 }
      uint16 :us_upper_optical_point_size, onlyif: -> { version >= 5 }

      # Override conditional field accessors to return nil when not present
      # BinData's onlyif fields return default values even when not read,
      # so we need to check the version before accessing them
      def ul_code_page_range1
        return nil unless version >= 1

        super
      end

      def ul_code_page_range2
        return nil unless version >= 1

        super
      end

      def sx_height
        return nil unless version >= 2

        super
      end

      def s_cap_height
        return nil unless version >= 2

        super
      end

      def us_default_char
        return nil unless version >= 2

        super
      end

      def us_break_char
        return nil unless version >= 2

        super
      end

      def us_max_context
        return nil unless version >= 2

        super
      end

      def us_lower_optical_point_size
        return nil unless version >= 5

        super
      end

      def us_upper_optical_point_size
        return nil unless version >= 5

        super
      end

      # Get the vendor ID as a trimmed string
      #
      # @return [String] The vendor ID with trailing spaces and nulls removed
      def vendor_id
        return "" unless ach_vend_id

        ach_vend_id.gsub(/[\x00\s]+$/, "")
      end

      # Get the embedding type flags
      #
      # @return [Integer] The fs_type value (embedding permissions)
      def type_flags
        fs_type
      end

      # Check if optical point size information is available
      #
      # @return [Boolean] True if version >= 5
      def has_optical_point_size?
        version >= 5
      end

      # Get the lower optical point size
      #
      # @return [Float, nil] The lower optical point size in points, or nil
      #   if not available
      def lower_optical_point_size
        return nil unless has_optical_point_size?

        us_lower_optical_point_size / 20.0
      end

      # Get the upper optical point size
      #
      # @return [Float, nil] The upper optical point size in points, or nil
      #   if not available
      def upper_optical_point_size
        return nil unless has_optical_point_size?

        us_upper_optical_point_size / 20.0
      end

      # Validation helper: Check if version is valid
      #
      # Valid versions are 0 through 5
      #
      # @return [Boolean] True if version is 0-5
      def valid_version?
        version && version.between?(0, 5)
      end

      # Validation helper: Check if weight class is valid
      #
      # Valid values are 1-1000, common values are multiples of 100
      #
      # @return [Boolean] True if weight class is valid
      def valid_weight_class?
        us_weight_class && us_weight_class.between?(1, 1000)
      end

      # Validation helper: Check if width class is valid
      #
      # Valid values are 1-9
      #
      # @return [Boolean] True if width class is 1-9
      def valid_width_class?
        us_width_class && us_width_class.between?(1, 9)
      end

      # Validation helper: Check if vendor ID is present
      #
      # Vendor ID should be a 4-character code
      #
      # @return [Boolean] True if vendor ID exists and is non-empty
      def has_vendor_id?
        !vendor_id.empty?
      end

      # Validation helper: Check if typo metrics are reasonable
      #
      # Ascent should be positive, descender negative, line gap non-negative
      #
      # @return [Boolean] True if typo metrics have correct signs
      def valid_typo_metrics?
        s_typo_ascender > 0 && s_typo_descender < 0 && s_typo_line_gap >= 0
      end

      # Validation helper: Check if Win metrics are valid
      #
      # Both should be positive (unsigned in spec)
      #
      # @return [Boolean] True if Win ascent and descent are positive
      def valid_win_metrics?
        us_win_ascent > 0 && us_win_descent > 0
      end

      # Validation helper: Check if Unicode ranges are set
      #
      # At least one Unicode range bit should be set
      #
      # @return [Boolean] True if any Unicode range bits are set
      def has_unicode_ranges?
        (ul_unicode_range1 | ul_unicode_range2 | ul_unicode_range3 | ul_unicode_range4) != 0
      end

      # Validation helper: Check if PANOSE data is present
      #
      # All PANOSE values should not be zero
      #
      # @return [Boolean] True if PANOSE seems to be set
      def has_panose?
        panose && panose.any? { |val| val != 0 }
      end

      # Validation helper: Check if embedding permissions are set
      #
      # fs_type indicates embedding and subsetting permissions
      #
      # @return [Boolean] True if embedding permissions are defined
      def has_embedding_permissions?
        !fs_type.nil?
      end

      # Validation helper: Check if selection flags are valid
      #
      # Checks for valid combinations of selection flags
      #
      # @return [Boolean] True if fs_selection has valid flags
      def valid_selection_flags?
        return false if fs_selection.nil?

        # Bits 0-9 are defined, others should be zero
        (fs_selection & 0xFC00).zero?
      end

      # Validation helper: Check if x_height and cap_height are present (v2+)
      #
      # For version 2+, these should be set
      #
      # @return [Boolean] True if metrics are present (or not required)
      def has_x_height_cap_height?
        return true if version < 2  # Not required for v0-1

        !sx_height.nil? && !s_cap_height.nil? && sx_height > 0 && s_cap_height > 0
      end

      # Validation helper: Check if first/last char indices are reasonable
      #
      # first should be <= last
      #
      # @return [Boolean] True if character range is valid
      def valid_char_range?
        us_first_char_index <= us_last_char_index
      end
    end
  end
end
