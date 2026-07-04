# frozen_string_literal: true

module Fontisan
  class Stitcher
    module PartitionStrategy
      # Abstract base. Concrete partitioners (ByPlane, ByBlock, …)
      # implement {#call} and return a {Blueprint}.
      class Base
        # Default cap: 65,535 − .notdef − composite-expansion margin.
        # The Stitcher's +GlyphLimit+ hard-caps at 65,535 glyphs, but
        # compile adds composites + variants on top of the codepoint
        # count — empirically ~5% for CJK-heavy fonts. 60,000 leaves
        # ~5,500 slots of headroom for composites before the post-
        # compile glyph count trips GlyphLimit.
        DEFAULT_CAP = 60_000

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
