# frozen_string_literal: true

module Fontisan
  module Collection
    # OffsetCalculator calculates file offsets for TTC/OTC structure
    #
    # Single responsibility: Calculate all file offsets for the collection structure
    # including TTC header, offset table, font directories, and table data.
    # Handles 4-byte alignment requirements.
    #
    # TTC/OTC Structure:
    # - TTC Header (12 bytes)
    # - Offset Table (4 bytes per font)
    # - Font 0 Table Directory
    # - Font 1 Table Directory
    # - ...
    # - Shared Tables
    # - Unique Tables
    #
    # @example Calculate offsets
    #   calculator = OffsetCalculator.new(sharing_map, fonts)
    #   offsets = calculator.calculate
    #   header_offset = offsets[:header_offset]
    #   font_directory_offsets = offsets[:font_directory_offsets]
    class OffsetCalculator
      # Alignment requirement for tables (4 bytes)
      TABLE_ALIGNMENT = 4

      # TTC header size (12 bytes)
      TTC_HEADER_SIZE = 12

      # Size of each font offset entry (4 bytes)
      FONT_OFFSET_SIZE = 4

      # Size of font directory header (12 bytes: sfnt_version, num_tables, searchRange, entrySelector, rangeShift)
      FONT_DIRECTORY_HEADER_SIZE = 12

      # Size of each table directory entry (16 bytes: tag, checksum, offset, length)
      TABLE_DIRECTORY_ENTRY_SIZE = 16

      # Initialize calculator
      #
      # @param sharing_map [Hash] Sharing map from TableDeduplicator
      # @param fonts [Array<TrueTypeFont, OpenTypeFont>] Source fonts
      # @raise [ArgumentError] if parameters are invalid
      def initialize(sharing_map, fonts)
        raise ArgumentError, "sharing_map cannot be nil" if sharing_map.nil?

        if fonts.nil? || fonts.empty?
          raise ArgumentError,
                "fonts cannot be nil or empty"
        end

        @sharing_map = sharing_map
        @fonts = fonts
        @offsets = {}
      end

      # Calculate all offsets for the collection
      #
      # @return [Hash] Complete offset map with:
      #   - :header_offset [Integer] - TTC header offset (always 0)
      #   - :offset_table_offset [Integer] - Offset table offset (always 12)
      #   - :font_directory_offsets [Array<Integer>] - Offset to each font's directory
      #   - :table_offsets [Hash] - Map of canonical_id to file offset
      #   - :font_table_directories [Hash] - Per-font table directory info
      def calculate
        @offsets = {
          header_offset: 0,
          offset_table_offset: TTC_HEADER_SIZE,
          font_directory_offsets: [],
          table_offsets: {},
          font_table_directories: {},
        }

        # Calculate offset after TTC header and offset table
        current_offset = TTC_HEADER_SIZE + (@fonts.size * FONT_OFFSET_SIZE)

        # Calculate offsets for each font's table directory
        calculate_font_directory_offsets(current_offset)

        # Calculate offsets for table data
        calculate_table_data_offsets

        @offsets
      end

      # Get offset for specific font's directory
      #
      # @param font_index [Integer] Font index
      # @return [Integer, nil] Offset or nil if not calculated
      def font_directory_offset(font_index)
        calculate unless @offsets.key?(:font_directory_offsets) && @offsets[:font_directory_offsets].any?
        @offsets[:font_directory_offsets][font_index]
      end

      # Get offset for specific table
      #
      # @param canonical_id [String] Canonical table ID
      # @return [Integer, nil] Offset or nil if not found
      def table_offset(canonical_id)
        calculate unless @offsets.key?(:table_offsets) && @offsets[:table_offsets].any?
        @offsets[:table_offsets][canonical_id]
      end

      private

      # Calculate offsets for each font's table directory
      #
      # Each font directory contains:
      # - Font directory header (12 bytes)
      # - Table directory entries (16 bytes each)
      #
      # @param start_offset [Integer] Starting offset
      # @return [void]
      def calculate_font_directory_offsets(start_offset)
        current_offset = start_offset

        @fonts.each_with_index do |font, font_index|
          # Store this font's directory offset
          @offsets[:font_directory_offsets] << current_offset

          # Calculate size of this font's directory
          num_tables = font.table_names.size
          directory_size = FONT_DIRECTORY_HEADER_SIZE + (num_tables * TABLE_DIRECTORY_ENTRY_SIZE)

          # Store directory info
          @offsets[:font_table_directories][font_index] = {
            offset: current_offset,
            size: directory_size,
            num_tables: num_tables,
            table_tags: font.table_names,
          }

          # Move to next font's directory (with alignment)
          current_offset = align_offset(current_offset + directory_size)
        end

        # Store offset where table data begins
        @table_data_start_offset = current_offset
      end

      # Calculate offsets for all table data
      #
      # Processes tables in two groups:
      # 1. Shared tables (stored once)
      # 2. Unique tables (stored per font)
      #
      # @return [void]
      def calculate_table_data_offsets
        current_offset = @table_data_start_offset

        # Collect all unique canonical tables
        canonical_tables = {}
        @sharing_map.each_value do |tables|
          tables.each do |tag, info|
            canonical_id = info[:canonical_id]
            next if canonical_tables[canonical_id] # Already processed

            canonical_tables[canonical_id] = {
              tag: tag,
              size: info[:size],
              shared: info[:shared],
            }
          end
        end

        # First, assign offsets to shared tables
        # Shared tables are stored once and referenced by multiple fonts
        canonical_tables.each do |canonical_id, info|
          next unless info[:shared]

          @offsets[:table_offsets][canonical_id] = current_offset
          current_offset = align_offset(current_offset + info[:size])
        end

        # Then, assign offsets to unique tables
        # Each font gets its own copy of unique tables
        canonical_tables.each do |canonical_id, info|
          next if info[:shared]

          @offsets[:table_offsets][canonical_id] = current_offset
          current_offset = align_offset(current_offset + info[:size])
        end
      end

      # Align offset to TABLE_ALIGNMENT boundary
      #
      # @param offset [Integer] Unaligned offset
      # @return [Integer] Aligned offset
      def align_offset(offset)
        remainder = offset % TABLE_ALIGNMENT
        return offset if remainder.zero?

        offset + (TABLE_ALIGNMENT - remainder)
      end

      # Calculate search range parameters for font directory header
      #
      # These values are used in the font directory header for binary search:
      # - searchRange: (max power of 2 <= numTables) * 16
      # - entrySelector: log2(max power of 2 <= numTables)
      # - rangeShift: numTables * 16 - searchRange
      #
      # @param num_tables [Integer] Number of tables
      # @return [Hash] Search parameters
      def calculate_search_params(num_tables)
        max_power = 0
        n = num_tables
        while n > 1
          n >>= 1
          max_power += 1
        end

        search_range = (1 << max_power) * 16
        entry_selector = max_power
        range_shift = (num_tables * 16) - search_range

        {
          search_range: search_range,
          entry_selector: entry_selector,
          range_shift: range_shift,
        }
      end
    end
  end
end
