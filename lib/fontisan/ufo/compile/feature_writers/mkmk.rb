# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module FeatureWriters
        # GPOS MarkToMark (lookup type 6) — mark-to-mark attachment.
        #
        # Same shape as MarkToBase, but pairs marks with OTHER marks
        # rather than marks with bases. UFO convention: a mark glyph
        # that can attach to another mark has a +_<name>mkmk+ anchor
        # (the attach-FROM point), and the "base mark" it attaches to
        # has the matching +<name>mkmk+ anchor (the attach-TO point).
        #
        # Pairs every glyph with a +_<name>mkmk+ anchor with every
        # glyph that has the matching +<name>mkmk+ anchor.
        class Mkmk < MarkFamilyBase
          LOOKUP_TYPE = 6
          FEATURE_TAG = "mkmk"
          MKMK_SUFFIX = "mkmk"

          private

          def feature_tag
            FEATURE_TAG
          end

          def lookup_type
            LOOKUP_TYPE
          end

          def base_bucket_key
            :base_marks
          end

          # Mkmk convention: _<name>mkmk → class_name = name (drop
          # underscore prefix + "mkmk" suffix).
          def mark_class_from_anchor(anchor_name)
            return nil unless anchor_name.start_with?("_")
            return nil unless anchor_name.end_with?(MKMK_SUFFIX)

            anchor_name[1..-MKMK_SUFFIX.length - 1]
          end

          # Base-mark convention: class_name + "mkmk" suffix.
          def base_anchor_name_for(class_name)
            "#{class_name}#{MKMK_SUFFIX}"
          end
        end
      end
    end
  end
end
