# frozen_string_literal: true

module Fontisan
  module Ucd
    # Turns a parsed Models::Ucd::Ucd instance into two compact
    # run-length-encoded indices (blocks + scripts), and persists them to
    # the cache for future Index loads.
    #
    # Index layout on disk (YAML):
    #
    #   <root>/<version>/index/
    #     blocks.yml
    #     scripts.yml
    #
    # Each file is an array of `{ first_cp:, last_cp:, name: }` hashes,
    # sorted by first_cp, disjoint.
    module IndexBuilder
      class << self
        # Build + persist both indices for a cached version.
        # @param version [String]
        # @return [Array(Index, Index)] blocks_index, scripts_index
        def build(version)
          ucd = load_ucd(version)
          blocks, scripts = build_from_ucd(ucd)
          CacheManager.index_dir(version).mkpath
          blocks.save(CacheManager.blocks_index_path(version))
          scripts.save(CacheManager.scripts_index_path(version))
          [blocks, scripts]
        end

        # Pure: build both indices from an in-memory Ucd model.
        # @param ucd [Models::Ucd::Ucd]
        # @return [Array(Index, Index)]
        def build_from_ucd(ucd)
          blocks_runs = collect_runs(ucd, :block)
          scripts_runs = collect_runs(ucd, :script)
          [Index.new(to_entries(blocks_runs)), Index.new(to_entries(scripts_runs))]
        end

        private

        def load_ucd(version)
          path = CacheManager.ucdxml_path(version)
          xml = File.read(path)
          Models::Ucd::Ucd.from_xml(xml)
        end

        # Walk all UcdChar entries, group by the given property
        # (:block or :script), and accumulate codepoint ranges per name.
        # Returns Hash<String, Array<[Integer, Integer]>>.
        def collect_runs(ucd, property)
          runs_by_name = Hash.new { |h, k| h[k] = [] }

          ucd.chars.each do |char|
            name = char.public_send(property)
            next if name.nil? || name.empty?

            ranges_for_char(char).each do |first, last|
              runs_by_name[name] << [first, last]
            end
          end

          runs_by_name.each_value { |runs| coalesce!(runs) }
          runs_by_name
        end

        # Returns Array<[Integer, Integer]> — the codepoint range(s) this
        # char covers.
        def ranges_for_char(char)
          if char.range?
            [[char.first_cp.to_i(16), char.last_cp.to_i(16)]]
          elsif char.cp
            cp_int = char.cp.to_i(16)
            [[cp_int, cp_int]]
          else
            []
          end
        end

        # Sort + merge adjacent/overlapping ranges in place.
        # Input: Array<[Integer, Integer]>, mutated.
        def coalesce!(runs)
          return if runs.empty?

          runs.sort!
          merged = [runs.first]
          runs[1..].each do |first, last|
            prev = merged.last
            if first <= prev[1] + 1
              prev[1] = [prev[1], last].max
            else
              merged << [first, last]
            end
          end
          runs.replace(merged)
        end

        # Flatten {name => [[first,last],...]} into Array<RangeEntry>.
        def to_entries(runs_by_name)
          runs_by_name.flat_map do |name, runs|
            runs.map { |first, last| RangeEntry.new(first, last, name) }
          end
        end
      end
    end
  end
end
