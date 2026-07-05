# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module FeatureWriters
        # GDEF GlyphClassDef — classifies every glyph into one of
        # the four OpenType glyph classes:
        #
        #   1 — Base glyph
        #   2 — Ligature glyph
        #   3 — Combining mark
        #   4 — Glyph spacing variant (e.g. alternate space)
        #
        # The classification drives how GSUB/GPOS lookups apply. UFO
        # sources carry this in the glyph's +lib+ plist under the
        # +public.openTypeCategory+ key; this writer translates that
        # into the structured form the GDEF builder expects.
        class Gdef < Base
          TABLE_TAG = "GDEF"

          # Map UFO public.openTypeCategory values → OpenType glyph
          # class integers. Glyphs whose category isn't listed get
          # class 0 (unclassified — the GDEF ClassDef omits them).
          CATEGORY_TO_CLASS = {
            "base" => 1,
            "ligature" => 2,
            "mark" => 3,
            "component" => 3, # UFO treats component as mark for GDEF
            "spacing" => 4,
          }.freeze

          # @return [FeatureOutput]
          def write
            classifications = {}

            font.glyphs.each_value do |glyph|
              cls = classify(glyph)
              classifications[glyph.name] = cls if cls
            end

            # A GDEF without any classified glyphs is meaningless —
            # return nil so the compiler skips the table.
            return nil if classifications.empty?

            FeatureOutput.new(
              table_tag: TABLE_TAG,
              feature_tag: nil,
              lookup_type: nil,
              data: { classes: classifications },
            )
          end

          private

          # Resolve a glyph's GDEF class. Prefer the explicit
          # +public.openTypeCategory+ lib entry; fall back to a
          # heuristic (glyphs with anchors named "top"/"bottom" are
          # marks; glyphs with component references are ligatures
          # only if their name has a +.liga+ suffix).
          def classify(glyph)
            category = glyph_lib_category(glyph)
            return CATEGORY_TO_CLASS[category] if category && CATEGORY_TO_CLASS.key?(category)

            heuristic_class(glyph)
          end

          def glyph_lib_category(glyph)
            return nil unless glyph.lib

            lib = glyph.lib
            return lib["public.openTypeCategory"] if lib["public.openTypeCategory"]

            categories = lib["public.openTypeCategories"]
            categories[glyph.name] if categories.is_a?(Hash)
          end

          def heuristic_class(glyph)
            anchor_names = glyph.anchors.map(&:name)
            mark_anchor_pattern = /\A_[a-zA-Z]+\z/
            return 3 if anchor_names.any? { |n| mark_anchor_pattern.match?(n.to_s) }
            return 2 if glyph.name.to_s.end_with?(".liga")

            nil
          end
        end
      end
    end
  end
end
