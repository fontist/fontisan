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
        class Mark < Base
          # GPOS lookup types
          MARK_TO_BASE = 4
          MARK_TO_LIGATURE = 5
          FEATURE_TAG = "mark"
          TABLE_TAG = "GPOS"

          # @return [FeatureOutput, nil]
          def write
            marks = mark_glyphs
            return nil if marks.empty?

            attachments = mark_glyphs.each_with_object({}) do |(mark_name, mark_classes), h|
              mark_classes.each do |class_name, mark_anchor|
                bases = base_glyphs_with(class_name)
                bases.each do |base_name, base_anchor|
                  h[class_name] ||= { marks: {}, bases: {} }
                  h[class_name][:marks][mark_name] = mark_anchor
                  h[class_name][:bases][base_name] = base_anchor
                end
              end
            end

            return nil if attachments.empty?

            FeatureOutput.new(
              table_tag: TABLE_TAG,
              feature_tag: FEATURE_TAG,
              lookup_type: MARK_TO_BASE,
              data: { attachments: attachments },
            )
          end

          private

          # Returns { mark_glyph_name => { class_name => [x, y] } }
          # for every glyph that has at least one +_<name>+ anchor.
          def mark_glyphs
            font.glyphs.each_with_object({}) do |(name, glyph), h|
              classes = mark_classes_for(glyph)
              h[name] = classes unless classes.empty?
            end
          end

          def mark_classes_for(glyph)
            glyph.anchors.each_with_object({}) do |anchor, h|
              next unless anchor.name.to_s.start_with?("_")

              class_name = anchor.name[1..]
              h[class_name] = [anchor.x, anchor.y]
            end
          end

          # For a given class_name (e.g. "top"), find every glyph
          # that has a +<class_name>+ anchor (without underscore).
          def base_glyphs_with(class_name)
            font.glyphs.each_with_object({}) do |(name, glyph), h|
              anchor = glyph.anchors.find { |a| a.name == class_name }
              next unless anchor

              h[name] = [anchor.x, anchor.y]
            end
          end
        end
      end
    end
  end
end
