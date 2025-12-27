# frozen_string_literal: true

require "fileutils"
require_relative "constants"

module Fontisan
  # FontWriter handles writing font binaries from table data
  #
  # This class assembles a complete font binary from individual table data,
  # including:
  # - Writing the sfnt header (offset table)
  # - Building the table directory
  # - Writing table data with proper 4-byte alignment
  # - Calculating all checksums
  # - Updating the head table's checksumAdjustment field
  #
  # @example Write font from tables
  #   tables = {
  #     'head' => head_data,
  #     'hhea' => hhea_data,
  #     'maxp' => maxp_data,
  #     'hmtx' => hmtx_data,
  #     'cmap' => cmap_data
  #   }
  #   binary = FontWriter.write_font(tables)
  #   File.binwrite('subset.ttf', binary)
  #
  # @example Write to file directly
  #   FontWriter.write_to_file(tables, 'subset.ttf')
  #
  # Reference: OpenType spec section on font file structure
  class FontWriter
    # OpenType/TrueType table ordering (recommended order)
    TRUETYPE_TABLE_ORDER = %w[
      head hhea maxp OS/2 hmtx LTSH VDMX hdmx cmap fpgm prep cvt
      loca glyf kern name post gasp PCLT DSIG
    ].freeze

    # OpenType/CFF table ordering (recommended order)
    OPENTYPE_TABLE_ORDER = %w[
      head hhea maxp OS/2 name cmap post CFF CFF2
    ].freeze

    # Write complete font binary from table data
    #
    # @param tables_hash [Hash<String, String>] Map of table tag to binary data
    # @param sfnt_version [Integer, nil] Font sfnt version (0x00010000 for TrueType,
    #   0x4F54544F for OpenType/CFF). If nil, auto-detects based on tables.
    # @return [String] Complete font binary
    #
    # @example
    #   binary = FontWriter.write_font(tables_hash)
    #   binary = FontWriter.write_font(tables_hash, sfnt_version: 0x4F54544F)
    def self.write_font(tables_hash, sfnt_version: nil)
      # Auto-detect sfnt version if not provided
      sfnt_version ||= detect_sfnt_version(tables_hash)
      new(tables_hash, sfnt_version: sfnt_version).write
    end

    # Detect sfnt version based on table presence
    #
    # @param tables_hash [Hash<String, String>] Map of table tag to binary data
    # @return [Integer] Detected sfnt version
    def self.detect_sfnt_version(tables_hash)
      if tables_hash.key?("CFF ") || tables_hash.key?("CFF2")
        0x4F54544F # 'OTTO' for OpenType/CFF
      else
        0x00010000 # 1.0 for TrueType
      end
    end

    # Write font binary to file
    #
    # @param tables_hash [Hash<String, String>] Map of table tag to binary data
    # @param path [String] Output file path
    # @param sfnt_version [Integer, nil] Font sfnt version. If nil, auto-detects.
    # @return [Integer] Number of bytes written
    #
    # @example
    #   FontWriter.write_to_file(tables_hash, 'output.ttf')
    def self.write_to_file(tables_hash, path, sfnt_version: nil)
      binary = write_font(tables_hash, sfnt_version: sfnt_version)

      # Create parent directories if they don't exist
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

      File.binwrite(path, binary)
    end

    # Initialize writer with table data
    #
    # @param tables_hash [Hash<String, String>] Map of table tag to binary data
    # @param sfnt_version [Integer] Font sfnt version
    def initialize(tables_hash, sfnt_version: 0x00010000)
      @tables = tables_hash
      @sfnt_version = sfnt_version
    end

    # Write the complete font binary
    #
    # @return [String] Complete font binary
    def write
      # Order tables according to format
      ordered_tags = order_tables

      # Calculate table offsets
      table_entries = calculate_table_entries(ordered_tags)

      # Build font binary
      font_data = String.new(encoding: Encoding::BINARY)

      # Write offset table (sfnt header)
      font_data << write_offset_table(table_entries.size)

      # Write table directory (ALL entries first)
      table_entries.each do |entry|
        font_data << write_table_entry(entry)
      end

      # Write table data (ALL data after directory)
      table_entries.each do |entry|
        font_data << entry[:data]
        font_data << entry[:padding]
      end

      # Calculate and update head table checksum adjustment
      update_checksum_adjustment!(font_data, table_entries)

      font_data
    end

    private

    # Order tables according to recommended order
    #
    # @return [Array<String>] Ordered table tags
    def order_tables
      # Determine if this is OpenType/CFF or TrueType
      is_cff = @tables.key?("CFF ") || @tables.key?("CFF2")
      order = is_cff ? OPENTYPE_TABLE_ORDER : TRUETYPE_TABLE_ORDER

      # Start with tables in recommended order that exist
      ordered = order.select { |tag| @tables.key?(tag) }

      # Add any remaining tables not in the recommended order
      remaining = @tables.keys - ordered
      ordered + remaining.sort
    end

    # Calculate table directory entries with offsets
    #
    # @param tags [Array<String>] Ordered table tags
    # @return [Array<Hash>] Table entries with offsets, checksums, data
    def calculate_table_entries(tags)
      # Calculate offset for first table
      # Offset table (12 bytes) + table directory (16 bytes per table)
      offset = 12 + (tags.size * 16)

      entries = []

      tags.each do |tag|
        data = @tables[tag]
        checksum = calculate_table_checksum(data)

        # Calculate padding to 4-byte boundary
        padding_length = (4 - (data.bytesize % 4)) % 4
        padding = "\0" * padding_length

        entries << {
          tag: tag,
          checksum: checksum,
          offset: offset,
          length: data.bytesize,
          data: data,
          padding: padding,
        }

        # Update offset for next table
        offset += data.bytesize + padding_length
      end

      entries
    end

    # Write offset table (sfnt header)
    #
    # @param num_tables [Integer] Number of tables
    # @return [String] Offset table binary data
    def write_offset_table(num_tables)
      # Calculate search range, entry selector, and range shift
      # searchRange = (maximum power of 2 <= num_tables) * 16
      # entrySelector = log2(maximum power of 2 <= num_tables)
      # rangeShift = num_tables * 16 - searchRange

      max_power = 0
      n = num_tables
      while n > 1
        n >>= 1
        max_power += 1
      end

      search_range = (1 << max_power) * 16
      entry_selector = max_power
      range_shift = (num_tables * 16) - search_range

      [
        @sfnt_version,    # uint32 - sfnt version
        num_tables,       # uint16 - number of tables
        search_range,     # uint16 - search range
        entry_selector,   # uint16 - entry selector
        range_shift, # uint16 - range shift
      ].pack("N n n n n")
    end

    # Write a table directory entry
    #
    # @param entry [Hash] Table entry with tag, checksum, offset, length
    # @return [String] Table directory entry binary data
    def write_table_entry(entry)
      [
        entry[:tag],       # char[4] - table tag
        entry[:checksum],  # uint32 - checksum
        entry[:offset],    # uint32 - offset
        entry[:length], # uint32 - length
      ].pack("a4 N N N")
    end

    # Calculate checksum for a table
    #
    # The checksum is calculated by summing all uint32 values in the table.
    # The table is padded with zeros to a multiple of 4 bytes if necessary.
    #
    # @param data [String] Table binary data
    # @return [Integer] Table checksum
    def calculate_table_checksum(data)
      # Pad to 4-byte boundary
      padded_data = data.dup
      padding_length = (4 - (data.bytesize % 4)) % 4
      padded_data << ("\0" * padding_length) if padding_length.positive?

      # Sum all uint32 values
      sum = 0
      (0...padded_data.bytesize).step(4) do |i|
        value = padded_data[i, 4].unpack1("N")
        sum = (sum + value) & 0xFFFFFFFF
      end

      sum
    end

    # Update head table checksum adjustment
    #
    # The checksumAdjustment field in the head table (at offset 8) must be
    # set such that the sum of all uint32 values in the entire font equals
    # the magic number 0xB1B0AFBA.
    #
    # @param font_data [String] Complete font binary (modified in place)
    # @param table_entries [Array<Hash>] Table entries
    # @return [void]
    def update_checksum_adjustment!(font_data, table_entries)
      # Find head table entry
      head_entry = table_entries.find { |e| e[:tag] == "head" }
      return unless head_entry

      # Zero out checksumAdjustment field (offset 8 in head table) before calculating
      # This ensures we calculate the correct checksum regardless of source font's value
      head_offset = head_entry[:offset]
      checksum_offset = head_offset + 8
      font_data[checksum_offset, 4] = "\x00\x00\x00\x00"

      # Calculate font checksum (with head checksumAdjustment zeroed)
      font_checksum = calculate_font_checksum(font_data)

      # Calculate adjustment
      adjustment = (Constants::CHECKSUM_ADJUSTMENT_MAGIC - font_checksum) & 0xFFFFFFFF

      # Write adjustment as uint32 big-endian
      font_data[checksum_offset, 4] = [adjustment].pack("N")
    end

    # Calculate checksum of entire font file
    #
    # @param data [String] Complete font binary
    # @return [Integer] Font checksum
    def calculate_font_checksum(data)
      # Pad to 4-byte boundary
      padded_data = data.dup
      padding_length = (4 - (data.bytesize % 4)) % 4
      padded_data << ("\0" * padding_length) if padding_length.positive?

      # Sum all uint32 values
      sum = 0
      (0...padded_data.bytesize).step(4) do |i|
        value = padded_data[i, 4].unpack1("N")
        sum = (sum + value) & 0xFFFFFFFF
      end

      sum
    end
  end
end
