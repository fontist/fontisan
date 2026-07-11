# frozen_string_literal: true

require "stringio"

module Fontisan
  module Audit
    module Checks
      # Validates cmap subtable invariants per the OpenType spec:
      #
      #   - At least one Unicode-encoded subtable is present
      #   - Format 4: segCountX2 must equal segCount × 2
      #   - Format 4: the last segment must have endCode 0xFFFF
      #   - Format 4: reservedPad must be 0
      #   - Format 12: groups must be sorted and non-overlapping
      #   - Format 12: each group startCharCode ≤ endCharCode
      #   - Subtable offsets must be within the cmap table bounds
      #
      # Catches the most common real-world cmap bugs that renderers and
      # text shapers reject silently.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cmap
      class CmapCheck < Check
        # @param font [SfntFont]
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          return [] unless font.has_table?("cmap")

          raw = font.table_data["cmap"]
          return [] unless raw

          issues = []
          issues.concat(validate_header(raw))
          return issues unless issues.empty?

          records = read_encoding_records(raw)
          issues.concat(validate_unicode_presence(records))
          issues.concat(validate_subtables(raw, records))
          issues
        end

        def self.code
          :cmap
        end

        # ---------- header ----------

        def self.validate_header(raw)
          issues = []
          version, num_tables = raw.unpack("nn")
          if version != 0
            issues << issue(severity: :error,
                            message: "cmap version is #{version} but must be 0",
                            location: "cmap.version")
          end
          if num_tables.zero?
            issues << issue(severity: :error,
                            message: "cmap has no encoding records",
                            location: "cmap.numTables")
          end
          issues
        end
        private_class_method :validate_header

        # ---------- encoding records ----------

        def self.read_encoding_records(raw)
          num_tables = raw.unpack1("x2n")
          offset = 4
          Array.new(num_tables) do |i|
            break if offset + 8 > raw.bytesize

            platform_id, encoding_id, subtable_offset = raw[offset, 8].unpack("nnN")
            offset += 8
            {
              index: i,
              platform_id: platform_id,
              encoding_id: encoding_id,
              subtable_offset: subtable_offset,
            }
          end
        end
        private_class_method :read_encoding_records

        def self.validate_unicode_presence(records)
          has_unicode = records.any? do |r|
            unicode_platform?(r[:platform_id], r[:encoding_id])
          end
          return [] if has_unicode

          [issue(severity: :warning,
                 message: "cmap has no Unicode-encoded subtable " \
                          "(expected platform 0 or 3 with encoding 1 or 10)",
                 location: "cmap.encoding_records")]
        end
        private_class_method :validate_unicode_presence

        def self.unicode_platform?(platform_id, encoding_id)
          platform_id.zero? ||
            (platform_id == 3 && [1, 10].include?(encoding_id))
        end
        private_class_method :unicode_platform?

        # ---------- per-subtable validation ----------

        def self.validate_subtables(raw, records)
          records.flat_map { |r| validate_one_subtable(raw, r) }
        end
        private_class_method :validate_subtables

        def self.validate_one_subtable(raw, record)
          off = record[:subtable_offset]
          if off + 2 > raw.bytesize
            return [issue(severity: :error,
                          message: "cmap subtable at record #{record[:index]} " \
                                   "has offset #{off} beyond the table end",
                          location: "cmap.encoding_records.#{record[:index]}")]
          end

          format = raw[off, 2].unpack1("n")
          case format
          when 0 then validate_format0(raw, off, record)
          when 4 then validate_format4(raw, off, record)
          when 6 then validate_format6(raw, off, record)
          when 12 then validate_format12(raw, off, record)
          when 14 then [] # format 14 (Unicode Variation Sequences) — skip for now
          else
            [issue(severity: :warning,
                   message: "cmap subtable at record #{record[:index]} uses " \
                            "unknown format #{format}",
                   location: "cmap.encoding_records.#{record[:index]}")]
          end
        end
        private_class_method :validate_one_subtable

        # Format 4 validation: segCountX2 consistency, sentinel, reservedPad.
        def self.validate_format4(raw, off, record)
          issues = []
          return issues unless off + 14 <= raw.bytesize

          _format, _, _lang, seg_count_x2, _search, _sel, _shift,
            = raw[off, 16].unpack("nnnnnnnn")
          seg_count = seg_count_x2 / 2

          if seg_count_x2.odd? || seg_count_x2 != seg_count * 2
            issues << issue(severity: :error,
                            message: "cmap format 4 (record #{record[:index]}): " \
                                     "segCountX2=#{seg_count_x2} is inconsistent " \
                                     "with segCount=#{seg_count}",
                            location: "cmap.encoding_records.#{record[:index]}")
          end

          # Read the last endCode (the sentinel segment)
          end_codes_start = off + 14
          if seg_count.positive? && end_codes_start + (seg_count * 2) <= raw.bytesize
            last_end = raw[end_codes_start + ((seg_count - 1) * 2), 2].unpack1("n")
            if last_end != 0xFFFF
              issues << issue(severity: :warning,
                              message: "cmap format 4 (record #{record[:index]}): " \
                                       "last segment endCode is 0x#{last_end.to_s(16)} " \
                                       "but should be 0xFFFF (sentinel)",
                              location: "cmap.encoding_records.#{record[:index]}")
            end
          end

          # reservedPad check
          reserved_pad_off = end_codes_start + (seg_count * 2)
          if reserved_pad_off + 2 <= raw.bytesize
            reserved_pad = raw[reserved_pad_off, 2].unpack1("n")
            unless reserved_pad.zero?
              issues << issue(severity: :error,
                              message: "cmap format 4 (record #{record[:index]}): " \
                                       "reservedPad is #{reserved_pad} but must be 0",
                              location: "cmap.encoding_records.#{record[:index]}")
            end
          end

          issues
        end
        private_class_method :validate_format4

        # Format 12 validation: groups sorted, non-overlapping, ordered.
        def self.validate_format12(raw, off, record)
          issues = []
          return issues unless off + 16 <= raw.bytesize

          _format, _reserved, _length, _lang, num_groups = raw[off, 16].unpack("nnNnN")
          groups_start = off + 16
          return issues if num_groups.zero?
          return issues unless groups_start + (num_groups * 12) <= raw.bytesize

          prev_end = nil
          num_groups.times do |g|
            entry_off = groups_start + (g * 12)
            start_cp, end_cp, _gid = raw[entry_off, 12].unpack("NNN")

            if start_cp > end_cp
              issues << issue(severity: :error,
                              message: "cmap format 12 (record #{record[:index]}): " \
                                       "group #{g} has startCharCode 0x#{start_cp.to_s(16)} " \
                                       "> endCharCode 0x#{end_cp.to_s(16)}",
                              location: "cmap.encoding_records.#{record[:index]}")
            end

            if prev_end && start_cp <= prev_end
              issues << issue(severity: :error,
                              message: "cmap format 12 (record #{record[:index]}): " \
                                       "group #{g} overlaps or is out of order " \
                                       "(startCharCode 0x#{start_cp.to_s(16)} ≤ " \
                                       "previous endCharCode 0x#{prev_end.to_s(16)})",
                              location: "cmap.encoding_records.#{record[:index]}")
            end
            prev_end = end_cp
          end
          issues
        end
        private_class_method :validate_format12

        def self.validate_format0(raw, off, record)
          # Format 0: 262 bytes (header 6 + 256-byte glyphIdArray)
          if off + 262 > raw.bytesize
            [issue(severity: :error,
                   message: "cmap format 0 (record #{record[:index]}): " \
                            "subtable is truncated (need 262 bytes)",
                   location: "cmap.encoding_records.#{record[:index]}")]
          else
            []
          end
        end
        private_class_method :validate_format0

        def self.validate_format6(raw, off, record)
          return [] unless off + 10 <= raw.bytesize

          _fmt, _len, _lang, first, count = raw[off, 10].unpack("nnnnn")
          needed = off + 10 + (count * 2)
          if needed > raw.bytesize
            [issue(severity: :error,
                   message: "cmap format 6 (record #{record[:index]}): " \
                            "subtable truncated (first=#{first}, count=#{count})",
                   location: "cmap.encoding_records.#{record[:index]}")]
          else
            []
          end
        end
        private_class_method :validate_format6
      end
    end
  end
end
