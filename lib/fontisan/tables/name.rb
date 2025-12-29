# frozen_string_literal: true

require_relative "../binary/base_record"

module Fontisan
  module Tables
    # BinData structure for a single name record
    #
    # Represents metadata about a string in the name table,
    # including platform, encoding, language, and offset information.
    class NameRecord < Binary::BaseRecord
      uint16 :platform_id
      uint16 :encoding_id
      uint16 :language_id
      uint16 :name_id
      uint16 :string_length
      uint16 :string_offset

      # The decoded string value (set after reading from string storage)
      attr_accessor :string

      # Get the length of the string (for backward compatibility)
      #
      # @return [Integer] String length in bytes
      def length
        string_length
      end

      # Decode the string data based on platform and encoding
      #
      # @param data [String] Raw binary string data
      def decode_string(data)
        @string = case platform_id
                  when Name::PLATFORM_MACINTOSH
                    # Platform 1 (Mac): ASCII/MacRoman
                    data.dup.force_encoding("ASCII-8BIT").encode("UTF-8",
                                                                 invalid: :replace,
                                                                 undef: :replace)
                  when Name::PLATFORM_WINDOWS
                    # Platform 3 (Windows): UTF-16BE
                    data.dup.force_encoding("UTF-16BE").encode("UTF-8",
                                                               invalid: :replace,
                                                               undef: :replace)
                  when Name::PLATFORM_UNICODE
                    # Platform 0 (Unicode): UTF-16BE
                    data.dup.force_encoding("UTF-16BE").encode("UTF-8",
                                                               invalid: :replace,
                                                               undef: :replace)
                  else
                    # Unknown platform: try UTF-8
                    data.dup.force_encoding("UTF-8")
                  end
      end
    end

    # BinData structure for the 'name' (Naming Table) table
    #
    # The name table allows multilingual strings to be associated with the font.
    # These strings can represent copyright notices, font names, family names,
    # style names, and other information.
    #
    # Reference: OpenType specification, name table
    #
    # @example Reading a name table
    #   data = File.binread("font.ttf", length, name_offset)
    #   name = Fontisan::Tables::Name.read(data)
    #   puts name.english_name(Fontisan::Tables::Name::FAMILY)
    class Name < Binary::BaseRecord
      # Name ID constants for common name records
      COPYRIGHT = 0
      FAMILY = 1
      SUBFAMILY = 2
      UNIQUE_ID = 3
      FULL_NAME = 4
      VERSION = 5
      POSTSCRIPT_NAME = 6
      TRADEMARK = 7
      MANUFACTURER = 8
      DESIGNER = 9
      DESCRIPTION = 10
      VENDOR_URL = 11
      DESIGNER_URL = 12
      LICENSE_DESCRIPTION = 13
      LICENSE_URL = 14
      PREFERRED_FAMILY = 16
      PREFERRED_SUBFAMILY = 17
      COMPATIBLE_FULL = 18
      SAMPLE_TEXT = 19
      POSTSCRIPT_CID = 20
      WWS_FAMILY = 21
      WWS_SUBFAMILY = 22

      # Platform IDs
      PLATFORM_UNICODE = 0
      PLATFORM_MACINTOSH = 1
      PLATFORM_WINDOWS = 3

      # Windows language ID for US English
      WINDOWS_LANGUAGE_EN_US = 0x0409

      # Mac language ID for English
      MAC_LANGUAGE_ENGLISH = 0

      uint16 :format
      uint16 :record_count
      uint16 :string_offset
      array :name_records, type: :name_record, initial_length: :record_count
      rest :string_storage

      # Cache for decoded names
      attr_accessor :decoded_names_cache

      # Hook that gets called after all fields are read
      def after_read_hook
        # Don't decode anything yet - wait for request
        @decoded_names_cache = {}
      end

      # Make sure we call our hook after BinData finishes reading
      def do_read(io)
        super
        after_read_hook
      end

      # Get the count of name records (for backward compatibility)
      #
      # @return [Integer] Number of name records
      def count
        record_count
      end

      # Decode all strings from the string storage area
      #
      # This method can be called explicitly to decode all name records upfront.
      # Useful for testing or when you know you'll need all strings.
      # By default, strings are decoded lazily on demand.
      #
      # @return [void]
      def decode_all_strings
        # Get the raw string storage as a plain Ruby binary string
        storage_bytes = string_storage.to_s.b

        return if storage_bytes.empty?

        name_records.each do |record|
          # Extract string data from storage using offset and length
          offset = record.string_offset
          length = record.string_length

          # Validate bounds
          next if offset.nil? || length.nil?
          next if offset + length > storage_bytes.bytesize
          next if length.zero?

          # Slice the bytes from storage
          string_data = storage_bytes.byteslice(offset, length)
          record.decode_string(string_data) if string_data && !string_data.empty?
        end
      end

      # Find an English name for the given name ID
      #
      # Priority: Platform 3 (Windows) with language 0x0409 (US English)
      # Fallback: Platform 1 (Mac) with language 0
      #
      # @param name_id [Integer] The name ID to search for
      # @return [String, nil] The decoded string or nil if not found
      def english_name(name_id)
        # Check cache first
        return @decoded_names_cache[name_id] if @decoded_names_cache.key?(name_id)

        # Find record (don't decode yet)
        record = find_name_record(
          name_id,
          platform: PLATFORM_WINDOWS,
          language: WINDOWS_LANGUAGE_EN_US,
        )

        record ||= find_name_record(
          name_id,
          platform: PLATFORM_MACINTOSH,
          language: MAC_LANGUAGE_ENGLISH,
        )

        return nil unless record

        # Decode only this one record
        decoded = decode_name_record(record)
        @decoded_names_cache[name_id] = decoded
        decoded
      end

      # Validate the table
      #
      # @return [Boolean] True if the table is valid
      def valid?
        !format.nil?
      rescue StandardError
        false
      end

      private

      # Find a name record matching the criteria
      #
      # @param name_id [Integer] The name ID to search for
      # @param platform [Integer] The platform ID
      # @param language [Integer] The language ID
      # @return [NameRecord, nil] The matching record or nil
      def find_name_record(name_id, platform:, language:)
        name_records.find do |rec|
          rec.name_id == name_id &&
            rec.platform_id == platform &&
            rec.language_id == language
        end
      end

      # Decode a single name record on demand
      #
      # @param record [NameRecord] The record to decode
      # @return [String] The decoded string
      def decode_name_record(record)
        # Get raw string storage
        storage_bytes = string_storage.to_s.b

        # Extract this record's string
        offset = record.string_offset
        length = record.string_length

        return nil if offset + length > storage_bytes.bytesize
        return nil if length.zero?

        string_data = storage_bytes.byteslice(offset, length)

        # Decode based on platform
        decoded = case record.platform_id
                  when PLATFORM_WINDOWS, PLATFORM_UNICODE
                    string_data.dup.force_encoding("UTF-16BE")
                      .encode("UTF-8", invalid: :replace, undef: :replace)
                  when PLATFORM_MACINTOSH
                    string_data.dup.force_encoding("ASCII-8BIT")
                      .encode("UTF-8", invalid: :replace, undef: :replace)
                  else
                    string_data.dup.force_encoding("UTF-8")
                  end

        # Intern common strings to reduce memory usage
        interned = Fontisan::Constants.intern_string(decoded)

        # Also populate the record's string attribute for backward compatibility
        record.string = interned

        interned
      end
    end
  end
end
