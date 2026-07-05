# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module FeatureWriters
        # Extended kerning (format 2 / Device-table variant of PairPos).
        #
        # Same data shape as the basic {Kern} writer, but emits the
        # extended format that supports:
        #   - device tables (sub-pixel kerning)
        #   - cross-stream kerning (y-direction adjustments)
        #   - per-pair value-format overrides
        #
        # The current implementation extracts the same kerning.pairs
        # data as Kern; the differentiation is in how the GPOS table
        # builder encodes the value format (Format1 vs Format2, plus
        # device tables). Writers do not need to know about that —
        # they just emit the structured data; the table builder
        # picks the encoding.
        #
        # Downstream consumers (compilers) choose between Kern and
        # Kern2 based on whether they need device tables. Most don't;
        # basic Kern is sufficient for the common case.
        class Kern2 < Base
          LOOKUP_TYPE = 2
          FEATURE_TAG = "kern"
          TABLE_TAG = "GPOS"
          FORMAT = 2

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
              data: { format: FORMAT, pairs: pairs },
            )
          end
        end
      end
    end
  end
end
