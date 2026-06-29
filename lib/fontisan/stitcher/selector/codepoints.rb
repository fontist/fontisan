# frozen_string_literal: true

module Fontisan
  class Stitcher
    module Selector
      # Include an explicit list of codepoints.
      class Codepoints
        attr_reader :codepoints

        def initialize(codepoints)
          @codepoints = codepoints
        end

        def apply(source, bindings)
          @codepoints.each do |cp|
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
