# frozen_string_literal: true

module Fontisan
  class Stitcher
    module PartitionStrategy
      # Partition codepoints by Unicode plane (BMP, SMP, SIP, …).
      #
      # For each plane with codepoints:
      #   - if the count fits under +cap+, emit one partition named
      #     +:plane_<n>+ (e.g. +:plane_0+, +:plane_2+);
      #   - otherwise sub-split using the large CJK extension block
      #     boundaries, naming partitions +:plane_<n>_a+, +:plane_<n>_b+,
      #     and so on.
      #
      # If a single CJK extension block alone exceeds +cap+, raises
      # {Fontisan::GlyphLimitExceededError} — the partitioner cannot
      # satisfy the cap and the caller must use a smaller cap, split
      # manually, or switch to a format with a higher glyph limit.
      class ByPlane < Base
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

        # When a plane overflows +cap+, carve it along the large CJK
        # extension block boundaries. The +:other+ bucket (everything
        # outside the known mega-blocks) is split into chunks of +cap+,
        # while each known large block becomes one partition atomically —
        # if a single block alone exceeds +cap+, we cannot sub-split it
        # (its codepoints are contiguous and we don't have finer-grained
        # boundaries to use), so raise.
        def sub_split_by_block(plane_num, entries, cap)
          buckets = bucket_by_large_block(entries)
          partitions = []
          suffix = "a"

          buckets.each do |label, bucket_entries|
            if large_block?(label) && bucket_entries.size > cap
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

        def large_block?(label)
          Fontisan::Unicode::Plane::LARGE_CJK_BLOCKS.key?(label)
        end

        # Split +entries+ into sub-arrays of at most +cap+ each.
        def chunks(entries, cap)
          entries.each_slice(cap).to_a
        end

        # Bucket entries by which large CJK block (or :other) they fall
        # into. Entries outside any known large block go into :other,
        # which is then packed into its own partition(s).
        def bucket_by_large_block(entries)
          buckets = { other: [] }
          Fontisan::Unicode::Plane::LARGE_CJK_BLOCKS.each_key do |label|
            buckets[label] = []
          end

          entries.each do |cp, label|
            block = find_large_block(cp)
            if block
              buckets[block] << [cp, label]
            else
              buckets[:other] << [cp, label]
            end
          end

          # Drop empty buckets; preserve order (other first if non-empty,
          # then CJK blocks in declaration order).
          ordered = []
          ordered << [:other, buckets[:other]] unless buckets[:other].empty?
          Fontisan::Unicode::Plane::LARGE_CJK_BLOCKS.each_key do |label|
            ordered << [label, buckets[label]] unless buckets[label].empty?
          end
          ordered
        end

        def find_large_block(codepoint)
          Fontisan::Unicode::Plane::LARGE_CJK_BLOCKS.find do |_label, range|
            range.include?(codepoint)
          end&.first
        end
      end
    end
  end
end
