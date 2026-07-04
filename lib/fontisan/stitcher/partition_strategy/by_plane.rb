# frozen_string_literal: true

module Fontisan
  class Stitcher
    module PartitionStrategy
      # Partition codepoints by Unicode plane (BMP, SMP, SIP, …).
      #
      # For each plane with codepoints:
      #   - if the count fits under +cap+, emit one partition named
      #     +:plane_<n>+ (e.g. +:plane_0+, +:plane_2+);
      #   - otherwise sub-split along the recognized sub-plane block
      #     boundaries (+RECOGNIZED_BLOCKS+), naming partitions
      #     +:plane_<n>_a+, +:plane_<n>_b+, and so on.
      #
      # If a single +ATOMIC_BLOCKS+ entry alone exceeds +cap+, raises
      # {Fontisan::PartitionCapExceededError} — the partitioner cannot
      # satisfy the cap and the caller must use a smaller cap, split
      # manually, or switch to a format with a higher glyph limit.
      # +CARVE_OUT_BLOCKS+ entries are chunkable and will be sliced
      # like +:other+ if they exceed +cap+.
      class ByPlane < Base
        # Atomic sub-plane blocks: cannot be sub-split further because
        # no finer-grained Unicode boundary exists inside them. If one
        # alone exceeds +cap+, raise PartitionCapExceededError.
        #
        # Labels follow the Unicode Blocks.txt block names with spaces
        # replaced by underscores.
        ATOMIC_BLOCKS = {
          "CJK_Ext_B" => 0x2A700..0x2B73F,
          "CJK_Ext_C" => 0x2B740..0x2B81F,
          "CJK_Ext_D" => 0x2B820..0x2CEAF,
          "CJK_Ext_E" => 0x2CEB0..0x2EBEF,
          "CJK_Ext_F" => 0x2EBF0..0x2EE5F,
        }.freeze

        # Carve-out boundaries: sub-plane regions large enough to
        # warrant their own partition bucket when a plane overflows
        # +cap+. Unlike atomic blocks, these are chunkable — if one
        # alone exceeds +cap+, it gets sliced into +cap+-sized chunks
        # like +:other+ does, never raised.
        CARVE_OUT_BLOCKS = {
          "CJK_Unified_Ideographs" => 0x4E00..0x9FFF,
          "Hangul_Syllables" => 0xAC00..0xD7AF,
        }.freeze

        # Every codepoint range recognized as a distinct sub-plane
        # bucket. Atomic blocks first, then carve-out blocks. Used by
        # the bucketing pass to decide what gets its own partition vs.
        # falls into +:other+.
        RECOGNIZED_BLOCKS = ATOMIC_BLOCKS.merge(CARVE_OUT_BLOCKS).freeze

        # @param cp_map [Hash{Integer=>Object}] codepoint → donor label
        # @param cap [Integer] max codepoints per partition
        # @return [Blueprint]
        def call(cp_map, cap: DEFAULT_CAP)
          grouped = group_by_plane(cp_map)
          partitions = grouped.flat_map do |plane_num, entries|
            build_partitions_for_plane(plane_num, entries, cap)
          end
          Blueprint.new(partitions: partitions)
        end

        private

        def group_by_plane(cp_map)
          cp_map.group_by { |cp, _label| Fontisan::Unicode::Plane.of(cp) }
        end

        def build_partitions_for_plane(plane_num, entries, cap)
          if entries.size <= cap
            return [single_partition(plane_num, entries)]
          end

          sub_split_by_block(plane_num, entries, cap)
        end

        def single_partition(plane_num, entries)
          Partition.new(
            name: :"plane_#{plane_num}",
            cps: entries.map(&:first),
            donor_map: entries.to_h,
          )
        end

        # When a plane overflows +cap+, carve it along the recognized
        # sub-plane block boundaries. The +:other+ bucket (everything
        # outside +RECOGNIZED_BLOCKS+) and any +CARVE_OUT_BLOCKS+ entries
        # are split into chunks of +cap+. +ATOMIC_BLOCKS+ entries become
        # one partition atomically — if a single atomic block alone
        # exceeds +cap+, we cannot sub-split it (its codepoints are
        # contiguous and we don't have finer-grained boundaries to use),
        # so raise.
        def sub_split_by_block(plane_num, entries, cap)
          buckets = bucket_by_recognized_block(entries)
          partitions = []
          suffix = "a"

          buckets.each do |label, bucket_entries|
            if atomic_block?(label) && bucket_entries.size > cap
              raise PartitionCapExceededError.new(
                block_label: label,
                actual: bucket_entries.size,
                cap: cap,
              )
            end

            chunks(bucket_entries, cap).each do |chunk|
              partitions << Partition.new(
                name: :"plane_#{plane_num}_#{suffix}",
                cps: chunk.map(&:first),
                donor_map: chunk.to_h,
              )
              suffix = suffix.succ
            end
          end
          partitions
        end

        def atomic_block?(label)
          ATOMIC_BLOCKS.key?(label)
        end

        # Split +entries+ into sub-arrays of at most +cap+ each.
        def chunks(entries, cap)
          entries.each_slice(cap).to_a
        end

        # Bucket entries by which recognized sub-plane block (or :other)
        # they fall into. Entries outside any known block go into :other,
        # which is then packed into its own partition(s). Order: :other
        # first if non-empty, then recognized blocks in declaration order.
        def bucket_by_recognized_block(entries)
          buckets = { other: [] }
          RECOGNIZED_BLOCKS.each_key { |label| buckets[label] = [] }

          entries.each do |cp, label|
            block = find_recognized_block(cp)
            if block
              buckets[block] << [cp, label]
            else
              buckets[:other] << [cp, label]
            end
          end

          ordered = []
          ordered << [:other, buckets[:other]] unless buckets[:other].empty?
          RECOGNIZED_BLOCKS.each_key do |label|
            ordered << [label, buckets[label]] unless buckets[label].empty?
          end
          ordered
        end

        def find_recognized_block(codepoint)
          RECOGNIZED_BLOCKS.find do |_label, range|
            range.include?(codepoint)
          end&.first
        end
      end
    end
  end
end
