# frozen_string_literal: true

module Fontisan
  class Stitcher
    module PartitionStrategy
      # Abstract base. Concrete partitioners (ByPlane, ByBlock, …)
      # implement {#call} and return a {Blueprint}.
      class Base
        # Default cap: 65,535 − .notdef − safety margin. Matches the
        # Stitcher's own +GlyphLimit+ cap for TTF.
        DEFAULT_CAP = 65_484

        # @param cp_map [Hash{Integer=>Object}] codepoint → donor label
        # @param cap [Integer] max codepoints per partition
        # @return [Blueprint]
        def call(cp_map, cap: DEFAULT_CAP)
          raise NotImplementedError,
                "#{self.class} must implement #call"
        end
      end
    end
  end
end
