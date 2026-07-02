# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # CFF2 subroutine utilities — bias calculation and INDEX building.
      #
      # Subroutines are shared charstring sequences referenced by index
      # from the caller. CFF2 supports two kinds:
      #   - GlobalSubr: shared across all CharStrings
      #   - LocalSubr: per Font DICT, referenced via operator 19 (0x13)
      #
      # The bias for callsubr/callgsubr index lookup is:
      #   0-1240       → bias 107
      #   1241-33800   → bias 1131
      #   33801+       → bias 32768
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cff2#charstring-operators
      module Cff2Subrs
        # Calculate the bias for subroutine index lookup.
        # @param count [Integer] number of subroutines in the INDEX
        # @return [Integer] bias
        def self.bias(count)
          return 107 if count <= 1240
          return 1131 if count <= 33800

          32768
        end

        # Build a Subr INDEX (same structure for Global and Local).
        # @param subrs [Array<String>] charstring bytes for each subr
        # @return [String] INDEX binary
        def self.build_index(subrs)
          Tables::Cff2::IndexBuilder.build(subrs.map(&:b))
        end
      end
    end
  end
end
