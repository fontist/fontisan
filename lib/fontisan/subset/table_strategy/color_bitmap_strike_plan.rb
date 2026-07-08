# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Plan for one strike emitted by [ColorBitmapSubsetter]: the source
      # BitmapSize plus the list of contiguous new-gid runs (each run
      # becomes one IndexSubTable in the output CBLC).
      class ColorBitmapStrikePlan
        attr_reader :source_strike, :subtable_plans

        def initialize(source_strike)
          @source_strike = source_strike
          @subtable_plans = []
        end

        # Add a placement, grouping into contiguous new-gid runs. A new
        # run starts when the new gid skips, the ppem changes, or the
        # image format changes.
        def add(placement)
          current = @subtable_plans.last

          if current && placement.new_gid == current.last_new_gid + 1
            current.add(placement)
          else
            sub = ColorBitmapSubtablePlan.new(
              strike_ppem: placement.strike_ppem,
              image_format: placement.image_format,
            )
            sub.add(placement)
            @subtable_plans << sub
          end
        end

        def empty?
          @subtable_plans.empty?
        end

        def subtable_count
          @subtable_plans.size
        end
      end
    end
  end
end
