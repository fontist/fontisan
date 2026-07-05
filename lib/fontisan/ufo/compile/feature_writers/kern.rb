# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module FeatureWriters
        # GPOS PairPos (lookup type 2) — kerning pairs.
        #
        # Reads +font.kerning+ (parsed from kerning.plist) and emits
        # a {FeatureOutput} whose +data+ is a structured list of
        # pairs ready for the GPOS PairPos builder. Returns +nil+
        # when the UFO has no kerning data — the compiler then
        # omits the GPOS table entirely.
        #
        # Group-based kerning keys (e.g. +"@MMK_L_A @MMK_R_B"+) are
        # emitted verbatim with +group: true+; the GPOS builder is
        # responsible for resolving group references via the UFO's
        # groups.plist data (TODO: groups.plist support is partial).
        class Kern < Base
          # GPOS lookup type 2 — PairPos (pair-positioning).
          LOOKUP_TYPE = 2
          FEATURE_TAG = "kern"
          TABLE_TAG = "GPOS"

          # @return [FeatureOutput, nil]
          def write
            return nil if font.kerning.nil? || font.kerning.empty?

            pairs = font.kerning.pairs.map do |key, value|
              left, right = key.to_s.split(" ", 2)
              {
                left: left,
                right: right,
                value: value.to_f,
                group_left: left.to_s.start_with?("@"),
                group_right: right.to_s.start_with?("@"),
              }
            end

            FeatureOutput.new(
              table_tag: TABLE_TAG,
              feature_tag: FEATURE_TAG,
              lookup_type: LOOKUP_TYPE,
              data: { pairs: pairs },
            )
          end
        end
      end
    end
  end
end
