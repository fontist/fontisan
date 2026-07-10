# frozen_string_literal: true

module Fontisan
  module Ufo
    # Group definitions parsed from `groups.plist`. Maps a group name
    # to a list of glyph names belonging to that group:
    #
    #   { "MMK_L_A" => ["A", "Agrave", "Aacute", ...],
    #     "MMK_R_T" => ["T", "Tcommaaccent", ...] }
    #
    # Group pair keys in `kerning.plist` (e.g. `"MMK_L_A MMK_R_T"`)
    # reference these names — kern writer + GPOS builder resolve them
    # to glyph sets before emitting PairPos records.
    class Groups
      attr_reader :groups

      def initialize(values = {})
        @groups = values
      end

      # All group names.
      def names
        @groups.keys
      end

      # Glyph names belonging to +name+. Empty array if unknown.
      def glyphs(name)
        @groups[name] || []
      end

      # Whether +name+ is a known group.
      def include?(name)
        @groups.key?(name)
      end

      def empty?
        @groups.empty?
      end

      def to_plist
        @groups
      end
    end
  end
end
