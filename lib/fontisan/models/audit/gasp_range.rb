# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # One entry from the TrueType `gasp` (Grid-fitting And Scan-conversion
      # Procedure) table.
      #
      # Each entry describes the hinting/smoothing policy that applies up to
      # the given `max_ppem` (pixels-per-em). The OpenType spec defines four
      # single-bit flags; the high 12 bits of the raw rangeFlags uint16 are
      # reserved.
      #
      # Construct via {.from_flags} from the raw uint16 pair; never hand-build
      # the bit decoding at call sites.
      class GaspRange < Lutaml::Model::Serializable
        # OpenType gasp rangeFlags bit masks.
        GRIDFIT             = 0x0001
        DO_GRAY             = 0x0002
        SYMMETRIC_GRIDFIT   = 0x0004
        SYMMETRIC_SMOOTHING = 0x0008

        attribute :max_ppem,            :integer
        attribute :gridfit,             Lutaml::Model::Type::Boolean
        attribute :do_gray,             Lutaml::Model::Type::Boolean
        attribute :symmetric_gridfit,   Lutaml::Model::Type::Boolean
        attribute :symmetric_smoothing, Lutaml::Model::Type::Boolean

        key_value do
          map "max_ppem",            to: :max_ppem
          map "gridfit",             to: :gridfit
          map "do_gray",             to: :do_gray
          map "symmetric_gridfit",   to: :symmetric_gridfit
          map "symmetric_smoothing", to: :symmetric_smoothing
        end

        # Build a GaspRange from the raw uint16 pair stored in the gasp table.
        #
        # @param max_ppem [Integer] rangeMaxPPEM (exclusive upper bound)
        # @param flags [Integer] raw rangeFlags bitfield
        # @return [GaspRange]
        def self.from_flags(max_ppem, flags)
          new(
            max_ppem: max_ppem,
            gridfit: (flags & GRIDFIT).positive?,
            do_gray: (flags & DO_GRAY).positive?,
            symmetric_gridfit: (flags & SYMMETRIC_GRIDFIT).positive?,
            symmetric_smoothing: (flags & SYMMETRIC_SMOOTHING).positive?,
          )
        end

        # Derived: both gridfit and do_gray are set. Mac historically treated
        # this combination as "do everything". Not serialized — compute on
        # demand.
        def gridfit_and_smoothing?
          gridfit && do_gray
        end
      end
    end
  end
end
