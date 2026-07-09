# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Per-subfont stats computed from the loaded, on-disk subfont (not the
    # in-memory UFO target — the compiler may add glyphs, e.g. .notdef).
    SubfontStats = Struct.new(:name, :glyph_count, :codepoint_count,
                              keyword_init: true)

    # Return value of {Stitcher#write_collection}. Carries the output path,
    # total bytes, and one {SubfontStats} per declared subfont.
    CollectionResult = Struct.new(:path, :bytes, :subfonts,
                                  keyword_init: true) do
      def face_count
        subfonts.size
      end
    end
  end
end
