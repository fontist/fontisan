# frozen_string_literal: true

module Fontisan
  class Stitcher
    module PartitionStrategy
      # Abstract base. Concrete partitioners (ByPlane, ByBlock, …)
      # implement {#call} and return a {Blueprint}.
      class Base
        # Glyph-cap headroom below the format's hard cap
        # (GlyphLimit::TTF_GLYPH_CAP / OTF_GLYPH_CAP = 65,535). The
        # partitioner must keep each partition's *codepoint* count low
        # enough that compile-time *glyph* expansion still fits under
        # the hard cap.
        #
        # Reserved slots:
        #   - .notdef (1 slot, mandated by OpenType — every font has it
        #     at GID 0 even when no codepoint binds to it)
        #   - composite expansion: compiling adds composites (ligatures,
        #     decomposable glyphs, variant attachments) on top of the
        #     source codepoint count. Empirically ~5% of typical BMP
        #     size for CJK-heavy fonts (≈2,500 composites on a 50k-cp
        #     BMP font). 5,534 slots covers that with margin.
        NOTDEF_RESERVED = 1
        COMPOSITE_HEADROOM = 5_534

        # Derive the partition cap from a format's hard glyph limit.
        # Mirrors GlyphLimit so a future bump (e.g. CFF2 card24 INDEX
        # counts) cascades automatically — no second magic number to
        # keep in sync.
        #
        # @param format [Symbol] :ttf, :otf, or :otf2
        # @return [Integer]
        def self.cap_for(format)
          GlyphLimit.for_format(format) - NOTDEF_RESERVED - COMPOSITE_HEADROOM
        end

        # Default cap for the most common format (TTF, where the glyph
        # cap equals 65,535). Use {.cap_for} when partitioning for a
        # different format.
        DEFAULT_CAP = cap_for(:ttf)

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
