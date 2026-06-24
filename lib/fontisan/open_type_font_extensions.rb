# frozen_string_literal: true

module Fontisan
  # Extension module for {OpenTypeFont} providing table-based construction.
  #
  # Extended into OpenTypeFont from +open_type_font.rb+ so that
  # +OpenTypeFont.from_tables(...)+ is available whenever the class
  # itself is loaded.
  module OpenTypeFontExtensions
    # Create font from hash of tables
    #
    # This is used during font conversion when we have tables but not a file.
    #
    # @param tables [Hash<String, String>] Map of table tag to binary data
    # @return [OpenTypeFont] New font instance
    def from_tables(tables)
      font = new
      font.initialize_storage
      font.loading_mode = LoadingModes::FULL

      font.table_data = tables

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

      font.tables.clear
      tables.each_key do |tag|
        entry = TableDirectory.new
        entry.tag = tag
        entry.checksum = 0
        entry.offset = 0
        entry.table_length = tables[tag].bytesize
        font.tables << entry
      end

      font
    end
  end
end
