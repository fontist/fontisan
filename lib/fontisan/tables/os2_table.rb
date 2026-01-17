# frozen_string_literal: true

require_relative "../sfnt_table"
require_relative "os2"

module Fontisan
  module Tables
    # OOP representation of the 'OS/2' (OS/2 and Windows Metrics) table
    #
    # The OS/2 table contains OS/2 and Windows-specific metrics required by
    # Windows and OS/2, including font metrics, character ranges, vendor
    # information, and embedding permissions.
    #
    # This class extends SfntTable to provide OS/2-specific validation and
    # convenience methods for accessing common OS/2 table fields.
    #
    # @example Accessing OS/2 table data
    #   os2 = font.sfnt_table("OS/2")
    #   os2.weight_class      # => 400 (Normal)
    #   os2.width_class       # => 5 (Medium)
    #   os2.vendor_id         # => "APPL"
    #   os2.embedding_allowed? # => true
    class Os2Table < SfntTable
      # Weight class names (from OpenType spec)
      WEIGHT_NAMES = {
        100 => "Thin",
        200 => "Extra-light (Ultra-light)",
        300 => "Light",
        400 => "Normal (Regular)",
        500 => "Medium",
        600 => "Semi-bold (Demi-bold)",
        700 => "Bold",
        800 => "Extra-bold (Ultra-bold)",
        900 => "Black (Heavy)",
      }.freeze

      # Width class names (from OpenType spec)
      WIDTH_NAMES = {
        1 => "Ultra-condensed",
        2 => "Extra-condensed",
        3 => "Condensed",
        4 => "Semi-condensed",
        5 => "Medium (Normal)",
        6 => "Semi-expanded",
        7 => "Expanded",
        8 => "Extra-expanded",
        9 => "Ultra-expanded",
      }.freeze

      # Selection flags (bit field)
      FS_ITALIC = 1 << 0
      FS_UNDERSCORE = 1 << 1
      FS_NEGATIVE = 1 << 2
      FS_OUTLINED = 1 << 3
      FS_STRIKEOUT = 1 << 4
      FS_BOLD = 1 << 5
      FS_REGULAR = 1 << 6
      FS_USE_TYPO_METRICS = 1 << 7
      FS_WWS = 1 << 8
      FS_OBLIQUE = 1 << 9

      # Get OS/2 table version
      #
      # @return [Integer, nil] Version number (0-5), or nil if not parsed
      def version
        parsed&.version
      end

      # Get weight class
      #
      # @return [Integer, nil] Weight class (100-900), or nil if not parsed
      def weight_class
        parsed&.us_weight_class
      end

      # Get weight class name
      #
      # @return [String, nil] Human-readable weight name, or nil if not parsed
      def weight_class_name
        return nil unless parsed

        WEIGHT_NAMES[parsed.us_weight_class] || "Unknown"
      end

      # Get width class
      #
      # @return [Integer, nil] Width class (1-9), or nil if not parsed
      def width_class
        parsed&.us_width_class
      end

      # Get width class name
      #
      # @return [String, nil] Human-readable width name, or nil if not parsed
      def width_class_name
        return nil unless parsed

        WIDTH_NAMES[parsed.us_width_class] || "Unknown"
      end

      # Get vendor ID
      #
      # @return [String, nil] 4-character vendor identifier, or nil if not parsed
      def vendor_id
        parsed&.vendor_id
      end

      # Check if font is italic
      #
      # @return [Boolean] true if italic flag is set
      def italic?
        parsed && (parsed.fs_selection & FS_ITALIC) != 0
      end

      # Check if font is bold
      #
      # @return [Boolean] true if bold flag is set
      def bold?
        parsed && (parsed.fs_selection & FS_BOLD) != 0
      end

      # Check if font uses regular style
      #
      # @return [Boolean] true if regular flag is set
      def regular?
        parsed && (parsed.fs_selection & FS_REGULAR) != 0
      end

      # Check if font uses typographic metrics
      #
      # @return [Boolean] true if use typo metrics flag is set
      def use_typo_metrics?
        parsed && (parsed.fs_selection & FS_USE_TYPO_METRICS) != 0
      end

      # Check if font is oblique
      #
      # @return [Boolean] true if oblique flag is set
      def oblique?
        parsed && (parsed.fs_selection & FS_OBLIQUE) != 0
      end

      # Get typographic ascent
      #
      # @return [Integer, nil] Typographic ascender, or nil if not parsed
      def typo_ascender
        parsed&.s_typo_ascender
      end

      # Get typographic descent
      #
      # @return [Integer, nil] Typographic descender (negative value), or nil if not parsed
      def typo_descender
        parsed&.s_typo_descender
      end

      # Get typographic line gap
      #
      # @return [Integer, nil] Line gap, or nil if not parsed
      def typo_line_gap
        parsed&.s_typo_line_gap
      end

      # Get Windows ascent
      #
      # @return [Integer, nil] Windows ascender, or nil if not parsed
      def win_ascent
        parsed&.us_win_ascent
      end

      # Get Windows descent
      #
      # @return [Integer, nil] Windows descender, or nil if not parsed
      def win_descent
        parsed&.us_win_descent
      end

      # Get x-height (version 2+)
      #
      # @return [Integer, nil] x-height value, or nil if not available
      def x_height
        parsed&.sx_height
      end

      # Get cap height (version 2+)
      #
      # @return [Integer, nil] Cap height value, or nil if not available
      def cap_height
        parsed&.s_cap_height
      end

      # Check if embedding is allowed
      #
      # @return [Boolean] true if embedding is permitted (fs_type & 0x8 == 0)
      def embedding_allowed?
        return false unless parsed

        # fs_type bit 3 (0x8) = Embedding must not be allowed
        # If bit 3 is NOT set, embedding is allowed
        (parsed.fs_type & 0x8).zero?
      end

      # Check if embedding is restricted
      #
      # @return [Boolean] true if embedding is restricted
      def embedding_restricted?
        !embedding_allowed?
      end

      # Check if preview/print embedding is allowed
      #
      # @return [Boolean] true if preview and print embedding is permitted
      def preview_print_allowed?
        return false unless parsed

        # fs_type bit 1 (0x2) = Preview & Print embedding allowed
        (parsed.fs_type & 0x2) != 0
      end

      # Check if editable embedding is allowed
      #
      # @return [Boolean] true if editable embedding is permitted
      def editable_allowed?
        return false unless parsed

        # fs_type bit 2 (0x4) = Editable embedding allowed
        (parsed.fs_type & 0x4) != 0
      end

      # Check if subsetting is allowed
      #
      # @return [Boolean] true if subsetting is permitted (fs_type bit 8 is NOT set)
      def subsetting_allowed?
        return false unless parsed

        # fs_type bit 8 (0x100) = No subsetting
        (parsed.fs_type & 0x100).zero?
      end

      # Check if bitmap embedding only is allowed
      #
      # @return [Boolean] true if only bitmaps can be embedded
      def bitmap_embedding_only?
        return false unless parsed

        # fs_type bit 9 (0x200) = Bitmap embedding only
        (parsed.fs_type & 0x200) != 0
      end

      # Get PANOSE classification
      #
      # @return [Array<Integer>, nil] Array of 10 PANOSE bytes, or nil if not parsed
      def panose
        parsed&.panose&.to_a
      end

      # Get first character index
      #
      # @return [Integer, nil] First character Unicode value, or nil if not parsed
      def first_char_index
        parsed&.us_first_char_index
      end

      # Get last character index
      #
      # @return [Integer, nil] Last character Unicode value, or nil if not parsed
      def last_char_index
        parsed&.us_last_char_index
      end

      protected

      # Validate the parsed OS/2 table
      #
      # @return [Boolean] true if valid
      # @raise [InvalidFontError] if OS/2 table is invalid
      def validate_parsed_table?
        return true unless parsed

        # Validate version
        unless parsed.valid_version?
          raise InvalidFontError,
                "Invalid OS/2 table version: #{parsed.version} (must be 0-5)"
        end

        # Validate weight class
        unless parsed.valid_weight_class?
          raise InvalidFontError,
                "Invalid OS/2 weight class: #{parsed.us_weight_class} (must be 1-1000)"
        end

        # Validate width class
        unless parsed.valid_width_class?
          raise InvalidFontError,
                "Invalid OS/2 width class: #{parsed.us_width_class} (must be 1-9)"
        end

        # Validate vendor ID
        unless parsed.has_vendor_id?
          raise InvalidFontError,
                "Invalid OS/2 vendor ID: empty or missing"
        end

        # Validate typo metrics
        unless parsed.valid_typo_metrics?
          raise InvalidFontError,
                "Invalid OS/2 typo metrics: ascent=#{parsed.s_typo_ascender}, " \
                "descent=#{parsed.s_typo_descender}, line_gap=#{parsed.s_typo_line_gap}"
        end

        # Validate Win metrics
        unless parsed.valid_win_metrics?
          raise InvalidFontError,
                "Invalid OS/2 Win metrics: win_ascent=#{parsed.us_win_ascent}, " \
                "win_descent=#{parsed.us_win_descent} (both must be positive)"
        end

        # Validate character range
        unless parsed.valid_char_range?
          raise InvalidFontError,
                "Invalid OS/2 character range: first=#{parsed.us_first_char_index}, " \
                "last=#{parsed.us_last_char_index} (first must be <= last)"
        end

        true
      end
    end
  end
end
