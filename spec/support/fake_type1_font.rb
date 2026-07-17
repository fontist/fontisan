# frozen_string_literal: true

module Fontisan
  module SpecHelpers
    # FakeType1Font passes `is_a?(Type1Font)` checks without requiring
    # actual Type 1 font parsing. Used by type1_converter_spec and
    # type1_property_spec.
    class FakeType1Font
      attr_accessor :charstrings, :font_dictionary, :post_script_name,
                    :font_name, :full_name, :family_name

      def initialize(charstrings: nil, font_dictionary: nil,
                     post_script_name: nil)
        @charstrings = charstrings
        @font_dictionary = font_dictionary
        @post_script_name = post_script_name
      end

      def is_a?(klass)
        klass == Fontisan::Type1Font || super
      end
    end

    # FakePrivateDict with all CFF hint fields.
    FakePrivateDict = Struct.new(:nominal_width, :default_width,
                                 :blue_values, :other_blues,
                                 :family_blues, :family_other_blues,
                                 :blue_scale, :blue_shift, :blue_fuzz,
                                 :std_hw, :std_vw, :stem_snap_h, :stem_snap_v,
                                 :force_bold, :language_group,
                                 :expansion_factor, :initial_random_seed,
                                 keyword_init: true)

    # FakeFontDictionary for Type 1 font dictionary.
    FakeFontDictionary = Struct.new(:raw_data) do
      def parse(_data = nil); end
      def parsed?; true; end
    end
  end
end
