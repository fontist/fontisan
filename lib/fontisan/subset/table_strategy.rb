# frozen_string_literal: true

# Autoload hub for the Fontisan::Subset::TableStrategy namespace.
#
# Each table tag handled by the subsetter has a corresponding strategy
# class (e.g. `TableStrategy::Maxp` for the "maxp" tag). Strategies are
# stateless — they receive a [SubsetContext] + tag + table and return
# the subset table's binary bytes. Unknown tags fall back to
# [TableStrategy::PassThrough], which preserves the source bytes.
#
# Registering a new tag is a one-line change: add the autoload here and
# an entry in REGISTRY. No edits to TableSubsetter required (Open/Closed).

module Fontisan
  module Subset
    module TableStrategy
      autoload :Cblc, "fontisan/subset/table_strategy/cblc"
      autoload :Cbdt, "fontisan/subset/table_strategy/cbdt"
      autoload :Cmap, "fontisan/subset/table_strategy/cmap"
      autoload :ColorBitmapPlacement,
               "fontisan/subset/table_strategy/color_bitmap_placement"
      autoload :ColorBitmapStrikePlan,
               "fontisan/subset/table_strategy/color_bitmap_strike_plan"
      autoload :ColorBitmapSubsetPlan,
               "fontisan/subset/table_strategy/color_bitmap_subset_plan"
      autoload :ColorBitmapSubsetter,
               "fontisan/subset/table_strategy/color_bitmap_subsetter"
      autoload :ColorBitmapSubtablePlan,
               "fontisan/subset/table_strategy/color_bitmap_subtable_plan"
      autoload :Glyf, "fontisan/subset/table_strategy/glyf"
      autoload :GlyfLocaBuilder,
               "fontisan/subset/table_strategy/glyf_loca_builder"
      autoload :Head, "fontisan/subset/table_strategy/head"
      autoload :Hhea, "fontisan/subset/table_strategy/hhea"
      autoload :Hmtx, "fontisan/subset/table_strategy/hmtx"
      autoload :Loca, "fontisan/subset/table_strategy/loca"
      autoload :Maxp, "fontisan/subset/table_strategy/maxp"
      autoload :Name, "fontisan/subset/table_strategy/name"
      autoload :Os2, "fontisan/subset/table_strategy/os2"
      autoload :PassThrough, "fontisan/subset/table_strategy/pass_through"
      autoload :Post, "fontisan/subset/table_strategy/post"

      # Tag → strategy class name (resolved lazily via const_get to keep
      # this file loadable in any order). Add new subsetting logic by
      # adding one autoload + one entry here, plus a strategy file under
      # `lib/fontisan/subset/table_strategy/`.
      REGISTRY = {
        "maxp" => :Maxp,
        "hhea" => :Hhea,
        "hmtx" => :Hmtx,
        "loca" => :Loca,
        "glyf" => :Glyf,
        "cmap" => :Cmap,
        "post" => :Post,
        "name" => :Name,
        "head" => :Head,
        "OS/2" => :Os2,
        "CBDT" => :Cbdt,
        "CBLC" => :Cblc,
      }.freeze

      # Resolve a table tag to its strategy class. Returns PassThrough
      # for any tag without an explicit registration.
      #
      # @param tag [String] OpenType table tag (e.g. "maxp", "CBDT")
      # @return [Class] a strategy class responding to `.call`
      def self.for(tag)
        const_name = REGISTRY[tag]
        return PassThrough unless const_name

        const_get(const_name)
      end
    end
  end
end
