# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module FeatureWriters
        # GPOS Cursive (lookup type 3) — cursive attachment.
        #
        # Pairs glyphs via their entry and exit anchors for cursive
        # (joining) scripts. UFO convention: a glyph's +<name>entry+
        # and +<name>exit+ anchors define where it connects to its
        # neighbors.
        #
        # Pairs every glyph that has at least one +entry+ anchor with
        # every glyph that has the corresponding +exit+ anchor.
        # Multiple entry/exit class names are supported.
        class Curs < Base
          LOOKUP_TYPE = 3
          FEATURE_TAG = "curs"
          TABLE_TAG = "GPOS"

          # @return [FeatureOutput, nil]
          def write
            attachments = {}

            entry_glyphs = glyphs_with_anchor(/entry\z/)
            exit_glyphs = glyphs_with_anchor(/exit\z/)

            return nil if entry_glyphs.empty? && exit_glyphs.empty?

            # Cursive attachment: each glyph can be both a "previous"
            # (with exit anchor) and "next" (with entry anchor) in
            # a cursive chain. The GPOS builder handles the
            # cross-references; we emit every glyph with its entry
            # and/or exit anchor positions.
            font.glyphs.each_value do |glyph|
              entry = find_anchor(glyph, /entry\z/)
              exit = find_anchor(glyph, /exit\z/)
              next unless entry || exit

              attachments[glyph.name] = {
                entry: entry && [entry.x, entry.y],
                exit: exit && [exit.x, exit.y],
              }
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

          def glyphs_with_anchor(pattern)
            font.glyphs.select do |_name, glyph|
              glyph.anchors.any? { |a| pattern.match?(a.name.to_s) }
            end
          end

          def find_anchor(glyph, pattern)
            glyph.anchors.find { |a| pattern.match?(a.name.to_s) }
          end
        end
      end
    end
  end
end
