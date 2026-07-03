# frozen_string_literal: true

module Fontisan
  class Stitcher
    module PartitionStrategy
      # The result of partitioning a codepoint set: an ordered list of
      # {Partition}s. Applying a blueprint to a Stitcher declares one
      # subfont per partition.
      Blueprint = Struct.new(:partitions, keyword_init: true) do
        # @param stitcher [Fontisan::Stitcher]
        # @return [Array<Symbol>] names of subfonts declared
        def apply_to(stitcher)
          partitions.each { |p| p.apply_to(stitcher) }
          partitions.map(&:name)
        end

        # @return [Array<Symbol>]
        def names
          partitions.map(&:name)
        end
      end
    end
  end
end
