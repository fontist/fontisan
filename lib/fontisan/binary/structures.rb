# frozen_string_literal: true

require_relative "base_record"

module Fontisan
  module Binary
    # OpenType Offset Table (Font Header)
    #
    # This structure appears at the beginning of every OpenType font file.
    # It contains metadata about the table directory.
    #
    # Structure:
    # - uint32: sfnt_version (0x00010000 for TrueType, 'OTTO' for CFF)
    # - uint16: num_tables (number of tables in font)
    # - uint16: search_range (maximum power of 2 <= num_tables) * 16
    # - uint16: entry_selector (log2 of maximum power of 2 <= num_tables)
    # - uint16: range_shift (num_tables * 16 - search_range)
    class OffsetTable < BaseRecord
      uint32 :sfnt_version
      uint16 :num_tables
      uint16 :search_range
      uint16 :entry_selector
      uint16 :range_shift

      # Check if this is a TrueType font (version 0x00010000 or 'true')
      #
      # @return [Boolean] True if TrueType font
      def truetype?
        [0x00010000, 0x74727565].include?(sfnt_version) # 'true'
      end

      # Check if this is an OpenType/CFF font (version 'OTTO')
      #
      # @return [Boolean] True if CFF font
      def cff?
        sfnt_version == 0x4F54544F # 'OTTO'
      end

      # Get sfnt version as a tag string
      #
      # @return [String] Version tag ('OTTO' or version number)
      def version_tag
        if cff?
          "OTTO"
        elsif truetype?
          "TrueType"
        else
          format("0x%08X", sfnt_version)
        end
      end
    end

    # OpenType Table Directory Entry
    #
    # Each entry describes one table in the font file.
    #
    # Structure:
    # - char[4]: tag (table identifier)
    # - uint32: checksum (checksum for this table)
    # - uint32: offset (byte offset from beginning of font file)
    # - uint32: table_length (length of table in bytes)
    class TableDirectoryEntry < BaseRecord
      string :tag, length: 4
      uint32 :checksum
      uint32 :offset
      uint32 :table_length

      # Convert tag to Tag object for comparison
      #
      # @return [Parsers::Tag] Tag object
      def tag_object
        Parsers::Tag.new(tag)
      end

      # Check if this entry has a specific tag
      #
      # @param other_tag [String, Parsers::Tag] Tag to compare
      # @return [Boolean] True if tags match
      def tag?(other_tag)
        tag_object == (other_tag.is_a?(Parsers::Tag) ? other_tag : Parsers::Tag.new(other_tag))
      end
    end
  end
end
