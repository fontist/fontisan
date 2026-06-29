# frozen_string_literal: true

module Fontisan
  class Stitcher
    module Selector
      # Include every codepoint in a Range (e.g. 0x41..0x5A = A-Z).
      # Glyphs missing from the source are silently skipped.
      class Range
        attr_reader :range

        def initialize(range)
          @range = range
        end

        def apply(source, bindings)
          @range.each do |cp|
            gid = source.gid_for_codepoint(cp)
            next unless gid

            bindings << {
              codepoint: cp,
              source: source,
              donor_gid: gid,
            }
          end
        end
      end
    end
  end
end
