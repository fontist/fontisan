# frozen_string_literal: true

module Fontisan
  module SpecHelpers
    FakeStore = Struct.new(:variation_region_list, :item_variation_data_entries,
                           keyword_init: true)

    FakeRegionList = Struct.new(:axis_count, :regions, keyword_init: true)

    FakeRegionAxis = Struct.new(:start_coord, :peak_coord, :end_coord,
                                keyword_init: true)

    FakeFvar = Struct.new(:axes, :instances, keyword_init: true) do
      def axis_count = axes&.length || 0
    end

    FakeMaxp = Struct.new(:num_glyphs, keyword_init: true)
    FakeCff2 = Struct.new(:num_axes, keyword_init: true)
    FakeHvar = Struct.new(:item_variation_store, keyword_init: true)
    FakeMvar = Struct.new(:item_variation_store, keyword_init: true)
  end
end
