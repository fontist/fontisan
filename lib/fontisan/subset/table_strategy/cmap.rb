# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Cmap strategy: rebuild cmap containing only the (codepoint →
      # new GID) mappings for codepoints whose original GID is retained.
      # Emits a format-4 subtable for BMP codepoints and a format-12
      # subtable for supplementary-plane codepoints.
      class Cmap
        # @param context [SubsetContext]
        # @param tag [String] "cmap"
        # @param table [Cmap] parsed cmap table
        # @return [String] binary cmap bytes for the subset
        def self.call(context:, tag:, table:)
          new_mappings = {}
          table.unicode_mappings.each do |char_code, old_gid|
            new_gid = context.mapping.new_id(old_gid)
            new_mappings[char_code] = new_gid if new_gid
          end
          Builder.new(new_mappings).build
        end

        # Builds a minimal valid cmap table from a {codepoint => gid} map.
        # Extracted as a sibling class so [Cmap] stays focused on
        # subsetting dispatch while the binary arithmetic lives
        # separately.
        class Builder
          def initialize(mappings)
            @mappings = mappings
          end

          def build
            @mappings = { 0 => 0 } if @mappings.empty?

            bmp = @mappings.select { |cp, _| cp <= 0xFFFF }
            supp = @mappings.select { |cp, _| cp > 0xFFFF }

            subtables = []
            records = []

            unless bmp.empty?
              subtables << build_format_4(bmp)
              idx = subtables.size - 1
              records << [3, 1, idx] # Windows BMP
              records << [0, 3, idx] # Unicode BMP
            end

            unless supp.empty?
              subtables << build_format_12(@mappings)
              idx = subtables.size - 1
              records << [3, 10, idx] # Windows UCS-4
              records << [0, 4, idx]  # Unicode full
            end

            assemble(records, subtables)
          end

          private

          def assemble(records, subtables)
            num_tables = records.size
            header = [0, num_tables].pack("nn")
            subtable_base = 4 + (8 * num_tables)

            offsets = []
            running = subtable_base
            subtables.each do |st|
              offsets << running
              running += st.bytesize
            end

            record_bytes = +""
            records.each do |pid, eid, idx|
              record_bytes << [pid, eid, offsets[idx]].pack("nnN")
            end

            header + record_bytes + subtables.join
          end

          def build_format_4(bmp_mappings)
            segments = coalesce_segments(bmp_mappings)
            segments << { start_cp: 0xFFFF, end_cp: 0xFFFF, start_gid: 0 }

            seg_count = segments.size
            seg_count_x2 = seg_count * 2
            search_range = 2**Math.log2(seg_count).floor * 2
            search_range = 2 if search_range < 2
            entry_selector = Math.log2(search_range / 2).to_i
            range_shift = seg_count_x2 - search_range

            end_codes = segments.map { |s| s[:end_cp] }
            start_codes = segments.map { |s| s[:start_cp] }
            id_deltas = segments.map do |s|
              (s[:start_gid] - s[:start_cp]) & 0xFFFF
            end
            id_range_offsets = [0] * seg_count

            subtable = +""
            subtable << [4, 0, 0, seg_count_x2,
                         search_range, entry_selector, range_shift].pack("n*")
            subtable << end_codes.pack("n*")
            subtable << [0].pack("n") # reservedPad
            subtable << start_codes.pack("n*")
            subtable << id_deltas.pack("n*")
            subtable << id_range_offsets.pack("n*")

            subtable[2, 2] = [subtable.bytesize].pack("n")
            subtable
          end

          def build_format_12(all_mappings)
            groups = coalesce_segments(all_mappings)
            num_groups = groups.size

            subtable = +""
            subtable << [12, 0, 0, 0, num_groups].pack("nnNNN")
            groups.each do |g|
              subtable << [g[:start_cp], g[:end_cp], g[:start_gid]].pack("NNN")
            end

            subtable[4, 4] = [subtable.bytesize].pack("N")
            subtable
          end

          def coalesce_segments(mappings)
            sorted = mappings.sort_by { |cp, _| cp }
            segments = []
            current = nil
            sorted.each do |cp, gid|
              if current && cp == current[:end_cp] + 1 &&
                  gid == current[:start_gid] + (cp - current[:start_cp])
                current[:end_cp] = cp
              else
                segments << current if current
                current = { start_cp: cp, end_cp: cp, start_gid: gid }
              end
            end
            segments << current if current
            segments
          end
        end
      end
    end
  end
end
