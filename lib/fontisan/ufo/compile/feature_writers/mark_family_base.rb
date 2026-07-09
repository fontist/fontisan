# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module FeatureWriters
        # Shared base for feature writers that pair "mark" glyphs with
        # "base" glyphs via a paired-anchor convention (Mark uses
        # +_<name>+ ↔ +<name>+; Mkmk uses +_<name>mkmk+ ↔
        # +<name>mkmk+). Concrete subclasses plug in the lookup
        # convention + the lookup type + the feature tag.
        #
        # Reduces duplication between Mark and Mkmk: both walk every
        # glyph, collect its anchor classes (with the convention's
        # prefix + suffix), then pair each class with matching bases.
        class MarkFamilyBase < Base
          # @return [FeatureOutput, nil]
          def write
            marks = collect_marks
            return nil if marks.empty?

            attachments = {}

            marks.each do |(mark_name, classes)|
              classes.each do |class_name, mark_anchor|
                bases = collect_bases_for(class_name)
                next if bases.empty?

                attachments[class_name] ||= new_class_entry
                attachments[class_name][:marks][mark_name] = mark_anchor
                bases.each do |n, a|
                  attachments[class_name][base_bucket_key][n] = a
                end
              end
            end

            return nil if attachments.empty?

            FeatureOutput.new(
              table_tag: table_tag,
              feature_tag: feature_tag,
              lookup_type: lookup_type,
              data: { attachments: attachments },
            )
          end

          private

          # The convention's mark-anchor predicate. Returns the
          # class_name extracted from a mark glyph's anchor name, or
          # +nil+ if the anchor doesn't match the convention.
          #
          # Subclasses implement this — Mark's convention is
          # "_<name>"; Mkmk's is "_<name>mkmk".
          def mark_class_from_anchor(_anchor_name)
            raise NotImplementedError,
                  "#{self.class} must implement #mark_class_from_anchor"
          end

          # Inverse of +mark_class_from_anchor+: given a class name
          # extracted from a mark anchor, what's the matching
          # base-anchor name? Mark's convention is class_name; Mkmk's
          # is "<class_name>mkmk".
          def base_anchor_name_for(_class_name)
            raise NotImplementedError,
                  "#{self.class} must implement #base_anchor_name_for"
          end

          # Subclass overrides — Mark uses :bases, Mkmk uses :base_marks.
          def base_bucket_key
            :bases
          end

          # Build a fresh per-class attachment entry with the right
          # base bucket key. Avoids inline hash-literal ambiguity
          # with dynamic keys.
          def new_class_entry
            { marks: {}, base_bucket_key => {} }
          end

          def table_tag
            "GPOS"
          end

          def feature_tag
            nil
          end

          def lookup_type
            nil
          end

          def collect_marks
            font.glyphs.each_with_object({}) do |(name, glyph), h|
              classes = mark_classes_for(glyph)
              h[name] = classes unless classes.empty?
            end
          end

          def mark_classes_for(glyph)
            glyph.anchors.each_with_object({}) do |anchor, h|
              class_name = mark_class_from_anchor(anchor.name.to_s)
              next unless class_name

              h[class_name] = [anchor.x, anchor.y]
            end
          end

          def collect_bases_for(class_name)
            target = base_anchor_name_for(class_name)
            return {} unless target

            font.glyphs.each_with_object({}) do |(name, glyph), h|
              anchor = glyph.anchors.find { |a| a.name == target }
              next unless anchor

              h[name] = [anchor.x, anchor.y]
            end
          end
        end
      end
    end
  end
end
