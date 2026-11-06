# frozen_string_literal: true

module Fontisan
  module Tables
    # Common structures shared between GSUB and GPOS tables
    module LayoutCommon
      # ScriptRecord structure
      class ScriptRecord < Binary::BaseRecord
        string :script_tag, length: 4
        uint16 :script_offset
      end

      # ScriptList table
      class ScriptList < Binary::BaseRecord
        uint16 :script_count
        array :script_records, type: ScriptRecord,
                               initial_length: -> { script_count }

        def script_tags
          script_records.map(&:script_tag)
        end
      end

      # LangSysRecord structure
      class LangSysRecord < Binary::BaseRecord
        string :lang_sys_tag, length: 4
        uint16 :lang_sys_offset
      end

      # Script table
      class Script < Binary::BaseRecord
        uint16 :default_lang_sys_offset
        uint16 :lang_sys_count
        array :lang_sys_records, type: LangSysRecord,
                                 initial_length: -> { lang_sys_count }
      end

      # LangSys table
      class LangSys < Binary::BaseRecord
        uint16 :lookup_order_offset # Reserved, set to NULL
        uint16 :required_feature_index
        uint16 :feature_index_count
        array :feature_indices, type: :uint16,
                                initial_length: -> { feature_index_count }
      end

      # FeatureRecord structure
      class FeatureRecord < Binary::BaseRecord
        string :feature_tag, length: 4
        uint16 :feature_offset
      end

      # FeatureList table
      class FeatureList < Binary::BaseRecord
        uint16 :feature_count
        array :feature_records, type: FeatureRecord,
                                initial_length: -> { feature_count }

        def feature_tags
          feature_records.map(&:feature_tag)
        end
      end

      # Feature table
      class Feature < Binary::BaseRecord
        uint16 :feature_params_offset # Reserved, set to NULL
        uint16 :lookup_index_count
        array :lookup_list_indices, type: :uint16,
                                    initial_length: -> { lookup_index_count }
      end

      # Scripts paired with their feature tags, from one parse of the
      # ScriptList and FeatureList instead of re-reading both per script.
      #
      # Gives exactly the answers of calling `scripts` and then
      # `features(script_tag:)` for each (the first record of a tag decides;
      # any short read yields []), but its total LangSys work is capped at
      # {WORK_PER_BYTE} x the table length, so a table whose scripts each
      # re-walk thousands of overlapping LangSys arrays cannot take minutes.
      # Scripts reached after the budget is gone read as failed ([]), the
      # same outcome as any other bad read. Mirrors the native tiers'
      # `LayoutTable::script_features`.
      class ScriptFeatures
        # Work units per byte of table; a well-formed font spends a small
        # fraction of one.
        WORK_PER_BYTE = 2

        # A short read or an exhausted budget: the script reads as [].
        class Failed < StandardError; end

        # @param table [Gsub, Gpos]
        def initialize(table)
          @table = table
          @data = table.table_data
          @budget = @data.bytesize * WORK_PER_BYTE
        end

        # @return [Hash{String=>Array<String>}] script tag => feature tags,
        #   in record order
        def call
          return {} if @table.script_list_offset.zero?

          list_data = slice_from(@data, @table.script_list_offset - 10)
          return {} if list_data.nil? || list_data.empty?

          records = ScriptList.read(list_data).script_records
          features = feature_tags
          records.each_with_object({}) do |record, result|
            tag = record.script_tag
            next if result.key?(tag)

            result[tag] = script_feature_tags(list_data, record.script_offset,
                                              features)
          end
        rescue StandardError
          {}
        end

        private

        # Ruby `String#[start..]`: negative starts count from the end.
        def slice_from(string, start)
          string[start..]
        end

        # FeatureList tags, or nil when every script must read as [].
        def feature_tags
          return nil if @table.script_list_offset.zero? ||
            @table.feature_list_offset.zero?

          data = slice_from(@data, @table.feature_list_offset - 10)
          return nil if data.nil? || data.empty?

          FeatureList.read(data).feature_tags
        rescue StandardError
          nil
        end

        def script_feature_tags(list_data, offset, features)
          return [] unless features

          indices = feature_indices(list_data, offset)
          indices.filter_map { |index| features[index] }.uniq
        rescue StandardError
          []
        end

        # Feature indices of one Script table: its default LangSys and every
        # LangSys record, deduplicated in first-seen order.
        def feature_indices(list_data, offset)
          data = slice_from(list_data, offset)
          return [] if data.nil? || data.empty?

          default_offset, count = read_header(data)
          spend(count)
          offsets = lang_sys_offsets(data, count)
          collector = IndexCollector.new(data)
          ([default_offset] + offsets).each do |lang_offset|
            next if lang_offset.zero? || lang_offset >= data.bytesize

            collector.add(lang_offset) { |units| spend(units) }
          end
          collector.indices
        end

        def read_header(data)
          raise Failed if data.bytesize < 4

          data.unpack("nn")
        end

        def lang_sys_offsets(data, count)
          raise Failed if data.bytesize < 4 + (6 * count)

          Array.new(count) { |i| data.byteslice(8 + (6 * i), 2).unpack1("n") }
        end

        def spend(units)
          raise Failed if units > @budget

          @budget -= units
        end
      end

      # Distinct feature indices of many LangSys tables in first-seen order,
      # reading every u16 word once. A LangSys index array is a run of words at
      # a fixed byte parity inside the Script table, so hostile overlapping
      # arrays would otherwise re-read the same words again and again; a word
      # already collected is skipped (a "next unread slot" union-find per
      # parity), which leaves the result and its order unchanged.
      class IndexCollector
        attr_reader :indices

        def initialize(data)
          @data = data
          @skip = [{}, {}]
          @seen = {}
          @indices = []
        end

        # LangSys at +offset+: reserved, required index, count, count x u16.
        # Yields the work units it costs (1 per table, 1 per word read).
        def add(offset)
          raise ScriptFeatures::Failed if @data.bytesize < offset + 6

          count = @data.byteslice(offset + 4, 2).unpack1("n")
          raise ScriptFeatures::Failed if @data.bytesize < offset + 6 + (2 * count)

          yield(1)
          first = offset + 6
          parity = first & 1
          slot = find(parity, first >> 1)
          limit = (first + (2 * count)) >> 1
          while slot < limit
            yield(1)
            collect(@data.byteslice((slot * 2) + parity, 2).unpack1("n"))
            @skip[parity][slot] = slot + 1
            slot = find(parity, slot + 1)
          end
        end

        private

        def collect(index)
          return if @seen.key?(index)

          @seen[index] = true
          @indices << index
        end

        def find(parity, slot)
          skip = @skip[parity]
          root = slot
          root = skip[root] while skip.key?(root)
          while slot != root
            following = skip[slot]
            skip[slot] = root
            slot = following
          end
          root
        end
      end
    end
  end
end
