# frozen_string_literal: true

require "stringio"

module Fontisan
  # Builds an SFNT (TrueType/OpenType) binary from a flavor + per-tag table
  # data. Used whenever WOFF2-derived table data needs to be reassembled
  # into a parseable SFNT (single-font decoding, WOFF2 collection → font).
  #
  # Single source of truth for the SFNT byte layout: 12-byte offset table,
  # 16-byte table directory entries, padded table data.
  module SfntBuilder
    # @param flavor [Integer] SFNT version (Constants::SFNT_VERSION_TRUETYPE
    #   or Constants::SFNT_VERSION_OTTO)
    # @param tables [Hash<String => String>] tag → table bytes
    # @return [String] SFNT binary
    def self.build(flavor:, tables:)
      num_tables = tables.length
      entry_selector = (Math.log(num_tables) / Math.log(2)).floor
      search_range = (2**entry_selector) * 16
      range_shift = (num_tables * 16) - search_range

      out = String.new(encoding: Encoding::BINARY)
      # Offset table (12 bytes)
      out << [flavor].pack("N")
      out << [num_tables].pack("n")
      out << [search_range].pack("n")
      out << [entry_selector].pack("n")
      out << [range_shift].pack("n")

      # Compute layout for table directory + table data with 4-byte padding
      data_start = 12 + (num_tables * 16)
      cursor = data_start
      records = tables.map do |tag, data|
        length = data.bytesize
        checksum = Utilities::ChecksumCalculator.calculate_table_checksum(data)
        padding = (4 - (length % 4)) % 4
        record = { tag:, checksum:, offset: cursor, length:, data:, padding: }
        cursor += length + padding
        record
      end

      # Write all table directory entries first (16 bytes each, sorted
      # alphabetically per SFNT convention for stable output), then all
      # table data with 4-byte padding. The directory entries' offset
      # fields were precomputed assuming this layout.
      sorted = records.sort_by { |r| r[:tag] }
      sorted.each do |r|
        out << r[:tag].ljust(4, "\x00")
        out << [r[:checksum]].pack("N")
        out << [r[:offset]].pack("N")
        out << [r[:length]].pack("N")
      end

      sorted.each do |r|
        out << r[:data]
        out << ("\x00" * r[:padding])
      end

      out
    end
  end
end
