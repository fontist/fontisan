# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `CFF2` table with subroutine (subr) support
      # for charstring compression.
      #
      # Subroutines are shared charstring sequences referenced by index
      # from the caller. CFF2 supports two kinds:
      #   - GlobalSubr: shared across all CharStrings (no Private DICT ref)
      #   - LocalSubr: per Font DICT, referenced via the Private DICT
      #     operator 19 (0x13) → LocalSubr INDEX offset
      #
      # The bias for callsubr/callgsubr index lookup is:
      #   0-1240       → bias 107
      #   1241-33800   → bias 1131
      #   33801+       → bias 32768
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cff2#charstring-operators
      class Cff2Subrs
        # Calculate the bias for subroutine index lookup.
        # @param count [Integer] number of subroutines in the INDEX
        # @return [Integer] bias
        def self.bias(count)
          return 107 if count <= 1240
          return 1131 if count <= 33800

          32768
        end

        # Build an empty GlobalSubr INDEX (no subroutines).
        # @return [String] empty INDEX binary
        def self.empty_global_subr_index
          [0].pack("N")
        end

        # Build a GlobalSubr INDEX from a list of charstring subroutines.
        # @param subrs [Array<String>] charstring bytes for each subr
        # @return [String] INDEX binary
        def self.global_subr_index(subrs)
          Tables::Cff2::IndexBuilder.build(subrs.map(&:b))
        end

        # Build a LocalSubr INDEX for a single Font DICT.
        # @param subrs [Array<String>] charstring bytes for each subr
        # @return [String] INDEX binary
        def self.local_subr_index(subrs)
          Tables::Cff2::IndexBuilder.build(subrs.map(&:b))
        end
      end
    end
  end
end
