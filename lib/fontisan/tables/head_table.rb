# frozen_string_literal: true

require_relative "../sfnt_table"
require_relative "head"

module Fontisan
  module Tables
    # OOP representation of the 'head' (Font Header) table
    #
    # The head table contains global information about the font, including
    # metadata about the font file, bounding box, and indexing information.
    #
    # This class extends SfntTable to provide head-specific validation and
    # convenience methods for accessing common head table fields.
    #
    # @example Accessing head table data
    #   head = font.table("head")  # Returns SfntTable instance
    #   head.magic_number_valid?  # => true
    #   head.units_per_em  # => 2048
    #   head.bounding_box  # => {x_min: -123, y_min: -456, ...}
    class HeadTable < SfntTable
      # Check if magic number is valid
      #
      # @return [Boolean] true if magic number is 0x5F0F3CF5
      def magic_number_valid?
        parsed && parsed.magic_number == Tables::Head::MAGIC_NUMBER
      end

      # Get units per em
      #
      # @return [Integer, nil] Units per em value, or nil if not parsed
      def units_per_em
        parsed&.units_per_em
      end

      # Get font bounding box
      #
      # @return [Hash, nil] Bounding box hash, or nil if not parsed
      def bounding_box
        return nil unless parsed

        {
          x_min: parsed.x_min,
          y_min: parsed.y_min,
          x_max: parsed.x_max,
          y_max: parsed.y_max,
        }
      end

      # Get index to loc format
      #
      # @return [Integer, nil] IndexToLocFormat value, or nil if not parsed
      def index_to_loc_format
        parsed&.index_to_loc_format
      end

      # Check if using long loca format
      #
      # @return [Boolean] true if using 32-bit loca offsets
      def long_loca_format?
        index_to_loc_format == 1
      end

      # Get font version
      #
      # @return [Float, nil] Font version as Fixed-point number
      def version
        parsed&.version
      end

      # Get font revision
      #
      # @return [Float, nil] Font revision as Fixed-point number
      def font_revision
        parsed&.font_revision
      end

      protected

      # Validate the parsed head table
      #
      # @return [Boolean] true if valid
      # @raise [InvalidFontError] if magic number is invalid
      def validate_parsed_table?
        return true unless parsed

        unless magic_number_valid?
          raise InvalidFontError,
                "Invalid head table magic number: expected 0x#{Tables::Head::MAGIC_NUMBER.to_s(16).upcase}, " \
                "got 0x#{parsed.magic_number.to_s(16).upcase}"
        end

        # Validate units_per_em is power of 2
        upem = parsed.units_per_em
        unless upem&.positive? && (upem & (upem - 1)).zero?
          raise InvalidFontError,
                "Invalid head table units_per_em: #{upem} (must be power of 2)"
        end

        # Validate index_to_loc_format
        ilf = parsed.index_to_loc_format
        unless [0, 1].include?(ilf)
          raise InvalidFontError,
                "Invalid head table indexToLocFormat: #{ilf} (must be 0 or 1)"
        end

        true
      end
    end
  end
end
