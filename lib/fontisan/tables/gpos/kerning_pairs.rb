# frozen_string_literal: true

require "fontisan/tables/gpos/pair_position"

module Fontisan
  module Tables
    class Gpos
      # Glyph-ID pair queries with explicit bounds for class-based enumeration.
      class KerningPairs
        include Enumerable

        def initialize(table, script_tag:, feature_tag:, glyph_count:)
          if !glyph_count.nil? && (!glyph_count.is_a?(Integer) || !glyph_count.between?(0, 65536))
            raise ArgumentError, "glyph_count must be an integer from 0 to 65536"
          end

          @glyph_count = glyph_count
          @view = BinaryView.new(table.raw_data.dup.freeze)
          @lookups = selected_lookups(table, script_tag, feature_tag).freeze
          @view.freeze
        end

        def [](pair)
          unless pair.is_a?(Array) && pair.size == 2 && pair.all? { |gid| gid.is_a?(Integer) && gid.between?(0, 65535) }
            raise ArgumentError, "Expected two glyph IDs from 0 to 65535"
          end

          @lookups.sum do |subtables|
            value = nil
            subtables.each do |subtable|
              value = subtable.adjustment(*pair)
              break unless value.nil?
            end
            value || 0
          end
        end

        def each
          return enum_for(:each) unless block_given?

          if @glyph_count.nil? && @lookups.flatten.any?(&:class_based?)
            raise ArgumentError, "glyph_count is required to enumerate class-based kerning"
          end

          subtables = @lookups.flatten.uniq
          left_glyphs(subtables).each do |left|
            candidates(subtables, left).each do |right|
              pair = [left, right]
              value = self[pair]
              yield pair, value unless value.zero?
            end
          end
          self
        end

        private

        def candidates(subtables, left)
          matching = subtables.select { |subtable| subtable.covers?(left) }
          return (0...@glyph_count) if matching.any?(&:class_based?)

          union(matching.map { |subtable| subtable.right_glyphs(left, @glyph_count) })
        end

        def left_glyphs(subtables)
          union(subtables.map(&:left_glyphs))
        end

        def union(sequences)
          glyphs = {}
          sequences.each do |sequence|
            sequence.each do |glyph|
              break if @glyph_count && glyph >= @glyph_count

              glyphs[glyph] = true
            end
          end
          glyphs.keys.sort
        end

        def selected_lookups(table, script_tag, feature_tag)
          return [] if table.script_list_offset.zero? || table.feature_list_offset.zero?

          indices = feature_indices(table.script_list_offset.to_i, script_tag)
          return [] if indices.empty?

          features = @view.child(table.feature_list_offset.to_i, minimum: 10)
          list = features.record(LayoutCommon::FeatureList, header: 2, count_offset: 0, item_size: 6)
          feature_offsets = indices.filter_map do |index|
            raise ParseError, "Invalid GPOS feature index #{index}" if index >= list.feature_count

            record = list.feature_records[index]
            record.feature_offset.to_i if record.feature_tag == feature_tag
          end
          lookup_indices = feature_lookup_indices(features, feature_offsets.uniq,
                                                  2 + list.feature_count.to_i * 6,
                                                  table.lookup_list_offset.to_i)
          return [] if lookup_indices.empty?

          lookups(table.lookup_list_offset.to_i, lookup_indices)
        end

        def feature_lookup_indices(features, offsets, minimum, lookup_list_offset)
          ranges = feature_ranges(features, offsets, minimum)
          return [] if ranges.empty?

          lookup_count = @view.child(lookup_list_offset, minimum: 10).uint16(0)
          indices = {}
          ranges.group_by { |first, _last| first % 2 }.each_value do |spans|
            previous = -1
            spans.sort.each do |first, last|
              [first, previous + 2].max.step(last, 2) do |position|
                lookup_index = features.uint16(position)
                raise ParseError, "Invalid GPOS lookup index #{lookup_index}" if lookup_index >= lookup_count

                indices[lookup_index] = true
              end
              previous = [previous, last].max
            end
          end
          indices.keys.sort
        end

        def feature_ranges(features, offsets, minimum)
          offsets.filter_map do |offset|
            feature = features.child(offset, minimum: minimum)
            count = feature.uint16(2)
            feature.bytes(2 + count * 2, 2)
            [offset + 4, offset + 2 + count * 2] unless count.zero?
          end
        end

        def feature_indices(offset, script_tag)
          scripts = @view.child(offset, minimum: 10)
          list = scripts.record(LayoutCommon::ScriptList, header: 2, count_offset: 0, item_size: 6)
          record = list.script_records.find { |item| item.script_tag == script_tag }
          return [] unless record

          script = scripts.child(record.script_offset.to_i, minimum: 2 + list.script_count.to_i * 6)
          header = script.record(LayoutCommon::Script, header: 4, count_offset: 2, item_size: 6)
          return [] if header.default_lang_sys_offset.zero?

          lang = script.child(header.default_lang_sys_offset.to_i, minimum: 4 + header.lang_sys_count.to_i * 6)
          record = lang.record(LayoutCommon::LangSys, header: 6, count_offset: 4, item_size: 2)
          indices = record.feature_indices.map(&:to_i)
          indices << record.required_feature_index.to_i unless record.required_feature_index == 0xffff
          indices.uniq
        end

        def lookups(offset, indices)
          list = @view.child(offset, minimum: 10)
          count = list.uint16(0)
          offsets = list.array(2, count)
          indices.filter_map do |index|
            lookup = list.child(offsets[index], minimum: 2 + count * 2)
            next unless lookup.uint16(0) == 2

            subtable_count = lookup.uint16(4)
            subtable_offsets = lookup.array(6, subtable_count)
            header = 6 + subtable_count * 2
            header += 2 unless (lookup.uint16(2) & 16).zero?
            lookup.bytes(0, header)
            subtable_offsets.uniq.map do |subtable_offset|
              view = lookup.child(subtable_offset, minimum: header)
              view.cached(:pair_position) { PairPosition.new(view) }
            end.freeze
          end
        end
      end

      private_constant :KerningPairs
    end
  end
end
