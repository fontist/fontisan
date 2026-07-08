# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Plan for the subset of color bitmaps: which source strikes have
      # any surviving glyph, and the per-strike runs of surviving new
      # GIDs. Built once by [ColorBitmapSubsetter] from a CBLC + a
      # GlyphMapping, then used to drive both CBDT and CBLC emission.
      class ColorBitmapSubsetPlan
        attr_reader :strikes, :strike_plans, :placements

        def initialize(mapping)
          @mapping = mapping
          @strikes = []
          @strike_plans = []
          @placements = []
        end

        # Walk every (gid, strike) location in CBLC and capture the
        # ones whose source gid is in the subset. Remaps the gid via
        # the supplied mapping.
        def collect!(cblc)
          cblc.bitmap_sizes.each do |strike|
            strike_plan = ColorBitmapStrikePlan.new(strike)

            cblc.sub_tables_for(strike).each do |sub|
              sub.locations.each do |loc|
                new_gid = @mapping.new_id(loc.glyph_id)
                next unless new_gid

                placement = ColorBitmapPlacement.new(
                  source_gid: loc.glyph_id,
                  new_gid: new_gid,
                  source_offset: loc.cbdt_offset,
                  byte_length: loc.byte_length,
                  image_format: loc.image_format,
                  strike_ppem: strike.ppem,
                )
                @placements << placement
                strike_plan.add(placement)
              end
            end

            next if strike_plan.empty?

            @strikes << strike
            @strike_plans << strike_plan
          end
        end

        def each_placement(&)
          @placements.each(&)
        end

        def each_strike_plan(&)
          @strike_plans.each(&)
        end
      end
    end
  end
end
