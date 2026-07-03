# frozen_string_literal: true

module Fontisan
  class Stitcher
    module PartitionStrategy
      # One slice of a partitioned codepoint set. Each partition names
      # a target subfont and the codepoints + donor mapping that should
      # land in it.
      #
      # {#apply_to} pushes the partition's bindings into a Stitcher via
      # +include_codepoints_map+ (TODO 68). If that API is unavailable
      # (older Stitcher), it falls back to one +include_codepoints+
      # call per donor — but the preferred path is the map API.
      Partition = Struct.new(:name, :cps, :donor_map, keyword_init: true) do
        # @param stitcher [Fontisan::Stitcher]
        # @return [void]
        def apply_to(stitcher)
          slice = cps.to_h { |cp| [cp, donor_map[cp]] }
          stitcher.include_codepoints_map(slice, into: name)
        end
      end
    end
  end
end
