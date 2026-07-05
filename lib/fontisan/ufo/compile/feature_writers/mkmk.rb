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
        class Mkmk < Base
          LOOKUP_TYPE = 6
          FEATURE_TAG = "mkmk"
          TABLE_TAG = "GPOS"

          MKMK_SUFFIX = "mkmk"

          # @return [FeatureOutput, nil]
          def write
            mark_marks = collect_mark_glyphs
            return nil if mark_marks.empty?

            attachments = {}

            mark_marks.each do |(mark_name, classes)|
              classes.each do |class_name, mark_anchor|
                base_marks = base_mark_glyphs_for(class_name)
                next if base_marks.empty?

                attachments[class_name] ||= { marks: {}, base_marks: {} }
                attachments[class_name][:marks][mark_name] = mark_anchor
                base_marks.each { |n, a| attachments[class_name][:base_marks][n] = a }
              end
            end

            return nil if attachments.empty?

            FeatureOutput.new(
              table_tag: TABLE_TAG,
              feature_tag: FEATURE_TAG,
              lookup_type: LOOKUP_TYPE,
              data: { attachments: attachments },
            )
          end

          private

          # { mark_name => { class_name => [x, y] } } for every glyph
          # with at least one +_<name>mkmk+ anchor.
          def collect_mark_glyphs
            font.glyphs.each_with_object({}) do |(name, glyph), h|
              classes = mkmk_classes_for(glyph)
              h[name] = classes unless classes.empty?
            end
          end

          def mkmk_classes_for(glyph)
            glyph.anchors.each_with_object({}) do |anchor, h|
              name = anchor.name.to_s
              next unless name.start_with?("_") && name.end_with?(MKMK_SUFFIX)

              # Strip leading underscore and trailing "mkmk" → class name.
              class_name = name[1..-MKMK_SUFFIX.length - 1]
              h[class_name] = [anchor.x, anchor.y]
            end
          end

          # For a class_name (e.g. "top"), find every glyph with the
          # +<class_name>mkmk+ anchor (no underscore prefix).
          def base_mark_glyphs_for(class_name)
            target_name = "#{class_name}#{MKMK_SUFFIX}"

            font.glyphs.each_with_object({}) do |(name, glyph), h|
              anchor = glyph.anchors.find { |a| a.name == target_name }
              next unless anchor

              h[name] = [anchor.x, anchor.y]
            end
          end
        end
      end
    end
  end
end
