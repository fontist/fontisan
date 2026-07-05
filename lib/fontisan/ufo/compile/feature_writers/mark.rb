# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module FeatureWriters
        # GPOS MarkToBase (lookup type 4) + MarkToLigature (type 5).
        #
        # Builds mark attachments from the UFO's per-glyph anchors.
        # Pair every mark glyph (one whose anchors include a
        # +_<name>+ entry, e.g. +_top+) with every base glyph that
        # has the matching non-underscore anchor (e.g. +top+).
        #
        # Prerequisite: {Filters::PropagateAnchors} should have run
        # first so composite glyphs carry their inherited anchors.
        class Mark < MarkFamilyBase
          LOOKUP_TYPE = 4
          FEATURE_TAG = "mark"

          private

          def feature_tag
            FEATURE_TAG
          end

          def lookup_type
            LOOKUP_TYPE
          end

          # Mark convention: _<name> → class_name = name (drop underscore).
          def mark_class_from_anchor(anchor_name)
            return nil unless anchor_name.start_with?("_")

            anchor_name[1..]
          end

          # Base convention: class_name is the anchor name verbatim.
          def base_anchor_name_for(class_name)
            class_name
          end
        end
      end
    end
  end
end
