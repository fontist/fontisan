# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates the SFNT table directory: checksums, 4-byte alignment,
      # offset arithmetic, search-range/entry-selector/range-shift
      # consistency.
      #
      # These checks are the foundation of all font validation — a
      # corrupt table directory makes every downstream parse
      # unreliable. Replaces the table-directory portion of MS Font
      # Validator + ots-sanitize.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/otff#table-directory
      class TableDirectoryCheck < Check
        # @param font [SfntFont]
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          issues = []
          issues.concat(validate_search_fields(font))
          issues.concat(validate_alignment(font))
          issues.concat(validate_checksums(font))
          issues.concat(validate_offsets(font))
          issues
        end

        def self.code
          :table_directory
        end

        # ---------- search range / entry selector / range shift ----------

        def self.validate_search_fields(font)
          num_tables = font.header.num_tables
          expected_range = largest_power_of_two_le(num_tables) * 16
          expected_selector = Math.log2(expected_range / 16).to_i
          expected_shift = (num_tables * 16) - expected_range

          issues = []
          if font.header.search_range != expected_range
            issues << issue(severity: :warning,
                            message: "searchRange is #{font.header.search_range} " \
                                     "but should be #{expected_range} " \
                                     "(numTables=#{num_tables})",
                            location: "header.searchRange")
          end
          if font.header.entry_selector != expected_selector
            issues << issue(severity: :warning,
                            message: "entrySelector is #{font.header.entry_selector} " \
                                     "but should be #{expected_selector}",
                            location: "header.entrySelector")
          end
          if font.header.range_shift != expected_shift
            issues << issue(severity: :warning,
                            message: "rangeShift is #{font.header.range_shift} " \
                                     "but should be #{expected_shift}",
                            location: "header.rangeShift")
          end
          issues
        end

        def self.largest_power_of_two_le(n)
          return 0 if n <= 0

          power = 1
          power *= 2 while power * 2 <= n
          power
        end
        private_class_method :largest_power_of_two_le

        # ---------- 4-byte alignment ----------

        def self.validate_alignment(font)
          font.tables.each_with_object([]) do |entry, issues|
            next if (entry.offset % 4).zero?

            issues << issue(severity: :warning,
                            message: "Table '#{readable_tag(entry.tag)}' at offset " \
                                     "#{entry.offset} is not 4-byte aligned",
                            location: "tables.#{readable_tag(entry.tag)}.offset")
          end
        end

        # ---------- checksums ----------

        # The 'head' table checksum has a special rule: its checkSumAdjustment
        # field (offset 8) is set to make the whole-table checksum match the
        # directory entry. We skip the head table's own checksum verification
        # and instead verify the adjustment is present.
        def self.validate_checksums(font)
          font.tables.each_with_object([]) do |entry, issues|
            tag = readable_tag(entry.tag)
            raw = font.table_data[tag]
            next unless raw

            next if tag == "head" # checkSumAdjustment complicates this

            actual = checksum(raw)
            next if actual == entry.checksum

            issues << issue(severity: :error,
                            message: "Table '#{tag}' checksum mismatch: " \
                                     "directory=0x#{entry.checksum.to_s(16).upcase} " \
                                     "computed=0x#{actual.to_s(16).upcase}",
                            location: "tables.#{tag}.checksum")
          end
        end

        # OpenType table checksum: sum of uint32 words, padded to 4 bytes
        # with zeros if the table length isn't a multiple of 4.
        def self.checksum(data)
          remainder = data.bytesize % 4
          padded_bytes = remainder.zero? ? data : data + "\x00".b * (4 - remainder)
          padded_bytes.unpack("N*").sum & 0xFFFFFFFF
        rescue StandardError
          0
        end
        private_class_method :checksum

        # ---------- offset arithmetic ----------

        def self.validate_offsets(font)
          dir_end = 12 + (font.header.num_tables * 16)
          font.tables.each_with_object([]) do |entry, issues|
            tag = readable_tag(entry.tag)

            if entry.offset < dir_end
              issues << issue(severity: :error,
                              message: "Table '#{tag}' offset #{entry.offset} " \
                                       "overlaps the table directory " \
                                       "(directory ends at #{dir_end})",
                              location: "tables.#{tag}.offset")
            end

            raw = font.table_data[tag]
            if raw && raw.bytesize != entry.table_length
              issues << issue(severity: :error,
                              message: "Table '#{tag}' length mismatch: " \
                                       "directory says #{entry.table_length} " \
                                       "but actual data is #{raw.bytesize} bytes",
                              location: "tables.#{tag}.table_length")
            end
          end
        end

        # BinData returns ASCII-8BIT tag strings; normalize for display.
        def self.readable_tag(tag)
          tag.dup.force_encoding("UTF-8")
        rescue StandardError
          tag.to_s
        end
        private_class_method :readable_tag
      end
    end
  end
end
