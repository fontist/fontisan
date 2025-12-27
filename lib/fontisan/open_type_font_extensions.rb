# frozen_string_literal: true

module Fontisan
  # Extensions to OpenTypeFont for table-based construction
  class OpenTypeFont
    # Create font from hash of tables
    #
    # This is used during font conversion when we have tables but not a file.
    #
    # @param tables [Hash<String, String>] Map of table tag to binary data
    # @return [OpenTypeFont] New font instance
    def self.from_tables(tables)
      # Create minimal header structure
      font = new
      font.initialize_storage
      font.loading_mode = LoadingModes::FULL

      # Store table data
      font.table_data = tables

      # Build header from tables
      num_tables = tables.size
      max_power = 0
      n = num_tables
      while n > 1
        n >>= 1
        max_power += 1
      end

      search_range = (1 << max_power) * 16
      entry_selector = max_power
      range_shift = (num_tables * 16) - search_range

      font.header.sfnt_version = 0x4F54544F # 'OTTO' for OpenType/CFF
      font.header.num_tables = num_tables
      font.header.search_range = search_range
      font.header.entry_selector = entry_selector
      font.header.range_shift = range_shift

      # Build table directory
      font.tables.clear
      tables.each_key do |tag|
        entry = TableDirectory.new
        entry.tag = tag
        entry.checksum = 0 # Will be calculated on write
        entry.offset = 0 # Will be calculated on write
        entry.table_length = tables[tag].bytesize
        font.tables << entry
      end

      font
    end
  end
end
