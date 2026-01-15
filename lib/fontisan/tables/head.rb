# frozen_string_literal: true

require_relative "../binary/base_record"

module Fontisan
  module Tables
    # BinData structure for the 'head' (Font Header) table
    #
    # The head table contains global information about the font, including
    # metadata about the font file, bounding box, and indexing information.
    #
    # Reference: OpenType specification, head table
    #
    # @example Reading a head table
    #   data = File.binread("font.ttf", 54, head_offset)
    #   head = Fontisan::Tables::Head.read(data)
    #   puts head.units_per_em  # => 2048
    #   puts head.version_number  # => 1.0
    class Head < Binary::BaseRecord
      # Magic number that must be present in the head table
      MAGIC_NUMBER = 0x5F0F3CF5

      # Version as 16.16 fixed-point (stored as int32)
      int32 :version_raw

      # Font revision as 16.16 fixed-point (stored as int32)
      int32 :font_revision_raw

      uint32 :checksum_adjustment
      uint32 :magic_number
      uint16 :flags
      uint16 :units_per_em

      # Created date as 64-bit signed integer (seconds since 1904-01-01)
      int64 :created_raw

      # Modified date as 64-bit signed integer (seconds since 1904-01-01)
      int64 :modified_raw

      int16 :x_min
      int16 :y_min
      int16 :x_max
      int16 :y_max
      uint16 :mac_style
      uint16 :lowest_rec_ppem
      int16 :font_direction_hint
      int16 :index_to_loc_format
      int16 :glyph_data_format

      # Convert version from fixed-point to float
      #
      # @return [Float] Version number (e.g., 1.0)
      def version
        fixed_to_float(version_raw)
      end

      # Convert font revision from fixed-point to float
      #
      # @return [Float] Font revision number
      def font_revision
        fixed_to_float(font_revision_raw)
      end

      # Convert created timestamp to Time object
      #
      # @return [Time] Creation time
      def created
        longdatetime_to_time(created_raw)
      end

      # Convert modified timestamp to Time object
      #
      # @return [Time] Modification time
      def modified
        longdatetime_to_time(modified_raw)
      end

      # Validate that the magic number is correct
      #
      # @return [Boolean] True if magic number is valid
      def valid?
        magic_number == MAGIC_NUMBER
      end

      # Validation helper: Check if magic number is valid
      #
      # @return [Boolean] True if magic number equals 0x5F0F3CF5
      def valid_magic?
        magic_number == MAGIC_NUMBER
      end

      # Validation helper: Check if version is valid
      #
      # OpenType spec requires version to be 1.0
      #
      # @return [Boolean] True if version is 1.0
      def valid_version?
        version_raw == 0x00010000 # Version 1.0
      end

      # Validation helper: Check if units per em is valid
      #
      # Units per em should be a power of 2 between 16 and 16384
      #
      # @return [Boolean] True if units_per_em is valid
      def valid_units_per_em?
        return false if units_per_em.nil? || units_per_em.zero?

        # Must be between 16 and 16384
        return false unless units_per_em.between?(16, 16384)

        # Should be a power of 2 (recommended but not required)
        # Common values: 1000, 1024, 2048
        # We'll allow any value in range for flexibility
        true
      end

      # Validation helper: Check if bounding box is valid
      #
      # The bounding box should have xMin < xMax and yMin < yMax
      #
      # @return [Boolean] True if bounding box coordinates are valid
      def valid_bounding_box?
        x_min < x_max && y_min < y_max
      end

      # Validation helper: Check if index_to_loc_format is valid
      #
      # Must be 0 (short) or 1 (long)
      #
      # @return [Boolean] True if format is 0 or 1
      def valid_index_to_loc_format?
        [0, 1].include?(index_to_loc_format)
      end

      # Validation helper: Check if glyph_data_format is valid
      #
      # Must be 0 for current format
      #
      # @return [Boolean] True if format is 0
      def valid_glyph_data_format?
        glyph_data_format.zero?
      end

      # Validate magic number and raise error if invalid
      #
      # @raise [Fontisan::CorruptedTableError] If magic number is invalid
      def validate_magic_number!
        return if valid?

        message = "Invalid magic number in head table: " \
                  "expected 0x#{MAGIC_NUMBER.to_s(16).upcase}, " \
                  "got 0x#{magic_number.to_s(16).upcase}"
        error = Fontisan::CorruptedTableError.new(message)
        error.set_backtrace(caller)
        Kernel.raise(error)
      end

      # Alias for backward compatibility
      alias validate! validate_magic_number!

      private

      # Convert LONGDATETIME to Ruby Time
      #
      # @param seconds [Integer] Seconds since 1904-01-01 00:00:00
      # @return [Time] Ruby Time object
      def longdatetime_to_time(seconds)
        # Difference between 1904 and 1970 (Unix epoch) is 2082844800 seconds
        Time.at(seconds - 2_082_844_800)
      end
    end
  end
end
