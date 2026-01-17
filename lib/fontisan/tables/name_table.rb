# frozen_string_literal: true

require_relative "../sfnt_table"
require_relative "name"

module Fontisan
  module Tables
    # OOP representation of the 'name' (Naming) table
    #
    # The name table contains all naming strings for the font, including
    # font family name, style name, designer, license, etc.
    #
    # This class extends SfntTable to provide name-specific convenience
    # methods for accessing common name records.
    #
    # @example Accessing name table data
    #   name = font.table("name")  # Returns SfntTable instance
    #   name.family_name  # => "Noto Sans"
    #   name.subfamily_name  # => "Regular"
    #   name.full_name  # => "Noto Sans Regular"
    #   name.postscript_name  # => "NotoSans-Regular"
    class NameTable < SfntTable
      # Name record identifiers
      #
      # These are the name IDs defined in the OpenType spec
      FAMILY = 1
      SUBFAMILY = 2
      FULL_NAME = 4
      POSTSCRIPT_NAME = 6
      PREFERRED_FAMILY = 16
      PREFERRED_SUBFAMILY = 17
      WWS_FAMILY = 21
      WWS_SUBFAMILY = 22

      # Platform IDs
      PLATFORM_UNICODE = 0
      PLATFORM_MACINTOSH = 1
      PLATFORM_WINDOWS = 3

      # Get font family name
      #
      # Attempts to get the preferred family name, falling back to the
      # standard family name if preferred is not available.
      #
      # @return [String, nil] Family name or nil if not found
      def family_name
        english_name(PREFERRED_FAMILY) || english_name(FAMILY)
      end

      # Get font subfamily name
      #
      # Attempts to get the preferred subfamily name, falling back to the
      # standard subfamily name if preferred is not available.
      #
      # @return [String, nil] Subfamily name or nil if not found
      def subfamily_name
        english_name(PREFERRED_SUBFAMILY) || english_name(SUBFAMILY)
      end

      # Get full font name
      #
      # @return [String, nil] Full name or nil if not found
      def full_name
        english_name(FULL_NAME)
      end

      # Get PostScript name
      #
      # @return [String, nil] PostScript name or nil if not found
      def postscript_name
        english_name(POSTSCRIPT_NAME)
      end

      # Get preferred family name
      #
      # @return [String, nil] Preferred family name or nil if not found
      def preferred_family_name
        english_name(PREFERRED_FAMILY)
      end

      # Get preferred subfamily name
      #
      # @return [String, nil] Preferred subfamily name or nil if not found
      def preferred_subfamily_name
        english_name(PREFERRED_SUBFAMILY)
      end

      # Get English name for a specific name ID
      #
      # Searches for an English name record with the given name ID.
      # Prefers Windows (platform 3) over Mac (platform 1) over Unicode (platform 0).
      #
      # @param name_id [Integer] The name record ID
      # @return [String, nil] The name string, or nil if not found
      def english_name(name_id)
        return nil unless parsed

        # Find all name records with this name_id
        records = parsed.name_records.select { |nr| nr.name_id == name_id }
        return nil if records.empty?

        # Try to find English Windows name first (platform 3, language 0x409)
        windows = records.find do |nr|
          nr.platform_id == PLATFORM_WINDOWS && nr.language_id == 0x409
        end
        return windows.string if windows&.string

        # Try Mac English (platform 1, language 0)
        mac = records.find do |nr|
          nr.platform_id == PLATFORM_MACINTOSH && nr.language_id.zero?
        end
        return mac.string if mac&.string

        # Try any English Unicode name (platform 0, language 0)
        unicode = records.find do |nr|
          nr.platform_id == PLATFORM_UNICODE && nr.language_id.zero?
        end
        return unicode.string if unicode&.string

        # Fallback to first record with this name_id
        first = records.first
        first&.string
      end

      # Get all name records
      #
      # @return [Array<NameRecord>, nil] Array of name records, or nil if not parsed
      def name_records
        parsed&.name_records
      end

      # Get all names for a specific name ID
      #
      # @param name_id [Integer] The name record ID
      # @return [Array<Hash>] Array of hashes with platform, encoding, language, and string
      def all_names_for(name_id)
        return [] unless parsed

        parsed.name_records
          .select { |nr| nr.name_id == name_id }
          .map do |nr|
            {
              platform_id: nr.platform_id,
              encoding_id: nr.encoding_id,
              language_id: nr.language_id,
              string: nr.string,
            }
          end
      end

      protected

      # Validate the parsed name table
      #
      # @return [Boolean] true if valid
      # @raise [InvalidFontError] if format identifier is invalid
      def validate_parsed_table?
        return true unless parsed

        # Validate format selector
        unless [0, 1].include?(parsed.format)
          raise InvalidFontError,
                "Invalid name table format: #{parsed.format} (must be 0 or 1)"
        end

        # Validate that we have at least some name records
        if parsed.name_records.empty?
          raise InvalidFontError,
                "Name table has no name records"
        end

        true
      end
    end
  end
end
