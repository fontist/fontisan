# frozen_string_literal: true

module Fontisan
  module Commands
    # Command to list all tables in a font file.
    #
    # This command extracts metadata about all tables present in a font file,
    # including their tags, lengths, offsets, and checksums.
    #
    # @example List font tables
    #   command = TablesCommand.new("path/to/font.ttf")
    #   table_info = command.run
    #   puts "Tables: #{table_info.num_tables}"
    class TablesCommand < BaseCommand
      # Extract table information from the font.
      #
      # @return [Models::TableInfo] Font table metadata
      def run
        table_info = Models::TableInfo.new
        table_info.sfnt_version = format_sfnt_version(font.header.sfnt_version)
        table_info.num_tables = font.tables.length

        table_info.tables = font.tables.map do |entry|
          Models::TableEntry.new(
            tag: entry.tag,
            length: entry.table_length,
            offset: entry.offset,
            checksum: entry.checksum,
          )
        end

        table_info
      end

      private

      # Format the SFNT version into a human-readable string.
      #
      # @param version [Integer] SFNT version number
      # @return [String] Formatted version string
      def format_sfnt_version(version)
        if version == 0x00010000
          "TrueType (0x00010000)"
        elsif version == 0x4F54544F # 'OTTO'
          "OpenType CFF (OTTO)"
        else
          format("0x%08X", version)
        end
      end
    end
  end
end
