# frozen_string_literal: true

require "fontisan/font_builder/outline"
require "fontisan/font_builder/glyph_entry"
require "fontisan/font_builder/name_record"

module Fontisan
  module FontBuilder
    # In-memory font model. Pure data — no serialization logic.
    # Tables::* classes read this and produce byte sequences.
    class FontModel
      attr_accessor :cmap, :glyphs, :names, :font_version,
                    :units_per_em, :created, :modified

      def initialize
        @cmap = {}
        @glyphs = { 0 => GlyphEntry.new } # gid 0 = .notdef
        @names = []
        @font_version = "Version 0.1.0"
        @units_per_em = 1000
        @created = Time.now.to_i
        @modified = Time.now.to_i
      end

      def num_glyphs
        glyphs.keys.max.to_i + 1
      end

      def allocate_gid
        gid = num_glyphs
        glyphs[gid] = GlyphEntry.new
        gid
      end

      def assign_codepoint(cp)
        return cmap[cp] if cmap.key?(cp)

        gid = allocate_gid
        cmap[cp] = gid
        gid
      end

      def sorted_codepoints
        cmap.keys.sort
      end

      def cp_for_gid(gid)
        @cmap_inverted ||= cmap.invert
        @cmap_inverted[gid]
      end

      def invalidate_caches
        @cmap_inverted = nil
      end
    end
  end
end
