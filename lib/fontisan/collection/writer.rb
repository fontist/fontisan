# frozen_string_literal: true

require_relative "../constants"
require_relative "../utilities/checksum_calculator"

module Fontisan
  module Collection
    # CollectionWriter writes binary TTC/OTC files
    #
    # Single responsibility: Write complete TTC/OTC binary structure to disk
    # including header, offset table, font directories, and table data.
    # Handles checksums and proper binary formatting.
    #
    # @example Write collection
    #   writer = CollectionWriter.new(fonts, sharing_map, offsets)
    #   writer.write_to_file("output.ttc")
    class Writer
      # TTC signature
      TTC_TAG = "ttcf"

      # TTC version 1.0 (major=1, minor=0)
      VERSION_1_0_MAJOR = 1
      VERSION_1_0_MINOR = 0

      # Initialize writer
      #
      # @param fonts [Array<TrueTypeFont, OpenTypeFont>] Source fonts
      # @param sharing_map [Hash] Sharing map from TableDeduplicator
      # @param offsets [Hash] Offset map from OffsetCalculator
      # @param format [Symbol] Format type (:ttc or :otc)
      # @raise [ArgumentError] if parameters are invalid
      def initialize(fonts, sharing_map, offsets, format: :ttc)
        if fonts.nil? || fonts.empty?
          raise ArgumentError,
                "fonts cannot be nil or empty"
        end
        raise ArgumentError, "sharing_map cannot be nil" if sharing_map.nil?
        raise ArgumentError, "offsets cannot be nil" if offsets.nil?
        raise ArgumentError, "format must be :ttc or :otc" unless %i[ttc
                                                                     otc].include?(format)

        @fonts = fonts
        @sharing_map = sharing_map
        @offsets = offsets
        @format = format
      end

      # Write collection to file
      #
      # @param path [String] Output file path
      # @return [Integer] Number of bytes written
      def write_to_file(path)
        binary = write_collection
        File.binwrite(path, binary)
        binary.bytesize
      end

      # Write collection to binary string
      #
      # @return [String] Complete collection binary
      def write_collection
        binary = String.new(encoding: Encoding::BINARY)

        # Write TTC header
        binary << write_ttc_header

        # Write offset table (offsets to each font's directory)
        binary << write_offset_table

        # Write each font's table directory
        @fonts.each_with_index do |font, font_index|
          # Pad to expected offset
          pad_to_offset(binary, @offsets[:font_directory_offsets][font_index])

          # Write font directory
          binary << write_font_directory(font, font_index)
        end

        # Write table data (shared tables first, then unique tables)
        write_table_data(binary)

        binary
      end

      private

      # Write TTC header (12 bytes)
      #
      # Structure:
      # - TAG: 'ttcf' (4 bytes)
      # - Major version: 1 (2 bytes)
      # - Minor version: 0 (2 bytes)
      # - Number of fonts (4 bytes)
      #
      # @return [String] TTC header binary
      def write_ttc_header
        [
          TTC_TAG,                  # char[4] - tag
          VERSION_1_0_MAJOR,        # uint16 - major version
          VERSION_1_0_MINOR,        # uint16 - minor version
          @fonts.size, # uint32 - number of fonts
        ].pack("a4 n n N")
      end

      # Write offset table
      #
      # Contains N uint32 values, one for each font, indicating the byte offset
      # from the beginning of the file to that font's table directory.
      #
      # @return [String] Offset table binary
      def write_offset_table
        @offsets[:font_directory_offsets].pack("N*")
      end

      # Write font directory for a specific font
      #
      # Structure:
      # - Font directory header (12 bytes: sfnt_version, num_tables, searchRange, entrySelector, rangeShift)
      # - Table directory entries (16 bytes each: tag, checksum, offset, length)
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font object
      # @param font_index [Integer] Font index
      # @return [String] Font directory binary
      def write_font_directory(font, font_index)
        binary = String.new(encoding: Encoding::BINARY)

        # Get font's table tags
        table_tags = font.table_names.sort

        # Write directory header
        binary << write_directory_header(font, table_tags.size)

        # Write table directory entries
        table_tags.each do |tag|
          binary << write_table_directory_entry(font_index, tag)
        end

        binary
      end

      # Write font directory header
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font object
      # @param num_tables [Integer] Number of tables
      # @return [String] Directory header binary
      def write_directory_header(font, num_tables)
        # Get sfnt version from font
        sfnt_version = font.header.sfnt_version

        # Calculate search parameters
        search_params = calculate_search_params(num_tables)

        [
          sfnt_version,                       # uint32 - sfnt version
          num_tables,                         # uint16 - number of tables
          search_params[:search_range],       # uint16 - search range
          search_params[:entry_selector],     # uint16 - entry selector
          search_params[:range_shift], # uint16 - range shift
        ].pack("N n n n n")
      end

      # Write table directory entry
      #
      # @param font_index [Integer] Font index
      # @param tag [String] Table tag
      # @return [String] Table directory entry binary
      def write_table_directory_entry(font_index, tag)
        # Get canonical table info from sharing map
        table_info = @sharing_map[font_index][tag]
        canonical_id = table_info[:canonical_id]

        # Get table offset from offset map
        table_offset = @offsets[:table_offsets][canonical_id]

        # Calculate checksum
        checksum = calculate_table_checksum(table_info[:data])

        [
          tag,                    # char[4] - table tag
          checksum,               # uint32 - checksum
          table_offset,           # uint32 - offset
          table_info[:size], # uint32 - length
        ].pack("a4 N N N")
      end

      # Write all table data
      #
      # Writes shared tables first (once each), then unique tables
      # (once per font). Tables are written at their calculated offsets
      # with proper alignment.
      #
      # @param binary [String] Binary string to append to
      # @return [void]
      def write_table_data(binary)
        # Collect all canonical tables with their offsets
        tables_by_offset = {}

        @offsets[:table_offsets].each do |canonical_id, offset|
          # Find the table data from sharing map
          table_data = find_canonical_table_data(canonical_id)

          tables_by_offset[offset] = {
            canonical_id: canonical_id,
            data: table_data,
          }
        end

        # Write tables in order of their offsets
        tables_by_offset.keys.sort.each do |offset|
          table_info = tables_by_offset[offset]

          # Pad to expected offset
          pad_to_offset(binary, offset)

          # Write table data
          binary << table_info[:data]

          # Pad to 4-byte boundary
          padding = calculate_padding(table_info[:data].bytesize)
          binary << ("\x00" * padding) if padding.positive?
        end
      end

      # Find canonical table data by ID
      #
      # @param canonical_id [String] Canonical table ID
      # @return [String] Table data
      def find_canonical_table_data(canonical_id)
        @sharing_map.each_value do |tables|
          tables.each_value do |info|
            return info[:data] if info[:canonical_id] == canonical_id
          end
        end

        raise "Canonical table not found: #{canonical_id}"
      end

      # Pad binary to specific offset
      #
      # @param binary [String] Binary string to pad
      # @param target_offset [Integer] Target offset
      # @return [void]
      def pad_to_offset(binary, target_offset)
        current_size = binary.bytesize
        return if current_size >= target_offset

        padding_needed = target_offset - current_size
        binary << ("\x00" * padding_needed)
      end

      # Calculate padding needed for 4-byte alignment
      #
      # @param size [Integer] Current size
      # @return [Integer] Padding bytes needed
      def calculate_padding(size)
        remainder = size % 4
        return 0 if remainder.zero?

        4 - remainder
      end

      # Calculate table checksum
      #
      # @param data [String] Table data
      # @return [Integer] Checksum
      def calculate_table_checksum(data)
        # Pad to 4-byte boundary
        padded_data = data.dup
        padding_length = calculate_padding(data.bytesize)
        padded_data << ("\x00" * padding_length) if padding_length.positive?

        # Sum all uint32 values
        sum = 0
        (0...padded_data.bytesize).step(4) do |i|
          value = padded_data[i, 4].unpack1("N")
          sum = (sum + value) & 0xFFFFFFFF
        end

        sum
      end

      # Calculate search parameters for directory header
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
