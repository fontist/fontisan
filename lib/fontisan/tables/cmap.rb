# frozen_string_literal: true

require_relative "../binary/base_record"

module Fontisan
  module Tables
    # Parser for the 'cmap' (Character to Glyph Index Mapping) table
    #
    # The cmap table maps character codes to glyph indices. It supports
    # multiple encoding formats to accommodate different character sets and
    # Unicode planes.
    #
    # This implementation focuses on:
    # - Format 4: Segment mapping for BMP (Basic Multilingual Plane, U+0000-U+FFFF)
    # - Format 12: Segmented coverage for full Unicode support
    #
    # Reference: OpenType specification, cmap table
    class Cmap < Binary::BaseRecord
      # Platform IDs
      PLATFORM_UNICODE = 0
      PLATFORM_MACINTOSH = 1
      PLATFORM_MICROSOFT = 3

      # Microsoft Encoding IDs
      ENC_MS_UNICODE_BMP = 1    # Unicode BMP (UCS-2)
      ENC_MS_UNICODE_UCS4 = 10  # Unicode full repertoire (UCS-4)

      endian :big

      uint16 :version
      uint16 :num_tables
      rest :remaining_data

      # Parse encoding records and subtables
      def unicode_mappings
        @unicode_mappings ||= parse_mappings
      end

      private

      # Parse all encoding records and extract Unicode mappings
      def parse_mappings
        mappings = {}

        # Get the full binary data
        data = to_binary_s

        # Read encoding records
        records = read_encoding_records(data)

        # Try to find the best Unicode subtable
        # Prefer Microsoft Unicode UCS-4 (format 12), then Unicode BMP (format 4)
        subtable_data = find_best_unicode_subtable(records, data)

        return mappings unless subtable_data

        # Parse the subtable based on its format
        format = subtable_data[0, 2].unpack1("n")

        case format
        when 4
          parse_format_4(subtable_data, mappings)
        when 12
          parse_format_12(subtable_data, mappings)
        end

        mappings
      end

      # Read encoding records from the beginning of the table
      def read_encoding_records(data)
        records = []
        offset = 4 # Skip version and numTables

        num_tables.times do
          break if offset + 8 > data.length

          platform_id = data[offset, 2].unpack1("n")
          encoding_id = data[offset + 2, 2].unpack1("n")
          subtable_offset = data[offset + 4, 4].unpack1("N")

          records << {
            platform_id: platform_id,
            encoding_id: encoding_id,
            offset: subtable_offset,
          }

          offset += 8
        end

        records
      end

      # Find the best Unicode subtable from encoding records
      def find_best_unicode_subtable(records, data)
        # Try in priority order: UCS-4, BMP, Unicode
        find_ucs4_subtable(records, data) ||
          find_bmp_subtable(records, data) ||
          find_unicode_subtable(records, data)
      end

      # Find Microsoft Unicode UCS-4 subtable (full Unicode)
      def find_ucs4_subtable(records, data)
        record = records.find do |r|
          r[:platform_id] == PLATFORM_MICROSOFT &&
            r[:encoding_id] == ENC_MS_UNICODE_UCS4
        end
        extract_subtable_data(record, data)
      end

      # Find Microsoft Unicode BMP subtable
      def find_bmp_subtable(records, data)
        record = records.find do |r|
          r[:platform_id] == PLATFORM_MICROSOFT &&
            r[:encoding_id] == ENC_MS_UNICODE_BMP
        end
        extract_subtable_data(record, data)
      end

      # Find Unicode platform subtable (any encoding)
      def find_unicode_subtable(records, data)
        record = records.find { |r| r[:platform_id] == PLATFORM_UNICODE }
        extract_subtable_data(record, data)
      end

      # Extract subtable data if record exists and offset is valid
      def extract_subtable_data(record, data)
        return nil unless record
        return nil unless record[:offset] < data.length

        data[record[:offset]..]
      end

      # Parse Format 4 subtable (segment mapping to delta values)
      # Format 4 is the most common format for BMP Unicode fonts
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def parse_format_4(data, mappings)
        return if data.length < 14

        # Format 4 header
        format = data[0, 2].unpack1("n")
        return unless format == 4

        length = data[2, 2].unpack1("n")
        return if length > data.length

        seg_count_x2 = data[6, 2].unpack1("n")
        seg_count = seg_count_x2 / 2

        # Arrays start at offset 14
        offset = 14

        # Read endCode array
        end_codes = []
        seg_count.times do
          break if offset + 2 > length

          end_codes << data[offset, 2].unpack1("n")
          offset += 2
        end

        # Skip reservedPad (2 bytes)
        offset += 2

        # Read startCode array
        start_codes = []
        seg_count.times do
          break if offset + 2 > length

          start_codes << data[offset, 2].unpack1("n")
          offset += 2
        end

        # Read idDelta array
        id_deltas = []
        seg_count.times do
          break if offset + 2 > length

          id_deltas << data[offset, 2].unpack1("n")
          offset += 2
        end

        # Read idRangeOffset array
        id_range_offsets = []
        id_range_offset_pos = offset
        seg_count.times do
          break if offset + 2 > length

          id_range_offsets << data[offset, 2].unpack1("n")
          offset += 2
        end

        # Process each segment
        seg_count.times do |i|
          start_code = start_codes[i]
          end_code = end_codes[i]
          id_delta = id_deltas[i]
          id_range_offset = id_range_offsets[i]

          # Skip the final segment (0xFFFF)
          next if start_code == 0xFFFF

          if id_range_offset.zero?
            # Use idDelta directly
            (start_code..end_code).each do |code|
              glyph_index = (code + id_delta) & 0xFFFF
              mappings[code] = glyph_index if glyph_index != 0
            end
          else
            # Use glyphIdArray
            (start_code..end_code).each do |code|
              # Calculate position in glyphIdArray
              array_offset = id_range_offset_pos + (i * 2) + id_range_offset
              array_offset += (code - start_code) * 2

              next if array_offset + 2 > length

              glyph_index = data[array_offset, 2].unpack1("n")
              next if glyph_index.zero?

              glyph_index = (glyph_index + id_delta) & 0xFFFF
              mappings[code] = glyph_index if glyph_index != 0
            end
          end
        end
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      # Parse Format 12 subtable (segmented coverage)
      # Format 12 supports full Unicode range
      def parse_format_12(data, mappings)
        header = parse_format_12_header(data)
        return unless header

        parse_format_12_groups(data, header[:num_groups], header[:length], mappings)
      end

      # Parse Format 12 header
      def parse_format_12_header(data)
        return nil if data.length < 16

        format = data[0, 2].unpack1("n")
        return nil unless format == 12

        length = data[4, 4].unpack1("N")
        return nil if length > data.length

        num_groups = data[12, 4].unpack1("N")

        { length: length, num_groups: num_groups }
      end

      # Parse Format 12 sequential map groups
      def parse_format_12_groups(data, num_groups, length, mappings)
        offset = 16
        num_groups.times do
          break if offset + 12 > length

          start_char_code = data[offset, 4].unpack1("N")
          end_char_code = data[offset + 4, 4].unpack1("N")
          start_glyph_id = data[offset + 8, 4].unpack1("N")

          map_character_range(start_char_code, end_char_code, start_glyph_id, mappings)

          offset += 12
        end
      end

      # Map a range of characters to glyphs
      def map_character_range(start_char, end_char, start_glyph, mappings)
        (start_char..end_char).each do |code|
          glyph_index = start_glyph + (code - start_char)
          mappings[code] = glyph_index if glyph_index != 0
        end
      end
    end
  end
end
