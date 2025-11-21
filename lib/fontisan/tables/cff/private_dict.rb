# frozen_string_literal: true

require_relative "dict"

module Fontisan
  module Tables
    class Cff
      # CFF Private DICT structure
      #
      # The Private DICT contains glyph-specific hinting and width data.
      # Each font has its own Private DICT (or multiple for CIDFonts).
      #
      # Private DICT Operators:
      # - blue_values: Alignment zones for overshoot suppression
      # - other_blues: Additional alignment zones
      # - family_blues: Family-wide alignment zones
      # - family_other_blues: Family-wide additional alignment zones
      # - blue_scale: Point size for overshoot suppression
      # - blue_shift: Pixels to shift alignment zones
      # - blue_fuzz: Tolerance for alignment zones
      # - std_hw: Standard horizontal stem width
      # - std_vw: Standard vertical stem width
      # - stem_snap_h: Horizontal stem snap widths
      # - stem_snap_v: Vertical stem snap widths
      # - force_bold: Force bold flag
      # - language_group: Language group (0=Latin, 1=CJK)
      # - expansion_factor: Expansion factor for counters
      # - initial_random_seed: Random seed for Type 1 hinting
      # - subrs: Offset to Local Subr INDEX (relative to Private DICT)
      # - default_width_x: Default glyph width
      # - nominal_width_x: Nominal glyph width
      #
      # Reference: CFF specification section 10 "Private DICT"
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
      #
      # @example Parsing a Private DICT
      #   private_size, private_offset = top_dict.private
      #   private_data = cff.raw_data[private_offset, private_size]
      #   private_dict = Fontisan::Tables::Cff::PrivateDict.new(private_data)
      #   puts private_dict[:blue_values]  # => [array of blue values]
      #   puts private_dict.default_width_x  # => default glyph width
      class PrivateDict < Dict
        # Private DICT specific operators
        #
        # These extend the common operators defined in the base Dict class
        PRIVATE_DICT_OPERATORS = {
          6 => :blue_values,
          7 => :other_blues,
          8 => :family_blues,
          9 => :family_other_blues,
          [12, 9] => :blue_scale,
          [12, 10] => :blue_shift,
          [12, 11] => :blue_fuzz,
          10 => :std_hw,
          11 => :std_vw,
          [12, 12] => :stem_snap_h,
          [12, 13] => :stem_snap_v,
          [12, 14] => :force_bold,
          [12, 17] => :language_group,
          [12, 18] => :expansion_factor,
          [12, 19] => :initial_random_seed,
          19 => :subrs,
          20 => :default_width_x,
          21 => :nominal_width_x,
        }.freeze

        # Default values for Private DICT operators
        #
        # These are used when an operator is not present in the DICT
        DEFAULTS = {
          blue_scale: 0.039625,
          blue_shift: 7,
          blue_fuzz: 1,
          force_bold: false,
          language_group: 0,
          expansion_factor: 0.06,
          initial_random_seed: 0,
          default_width_x: 0,
          nominal_width_x: 0,
        }.freeze

        # Get a value with default fallback
        #
        # @param key [Symbol] Operator name
        # @return [Object] Value or default value
        def fetch(key, default = nil)
          @dict.fetch(key, DEFAULTS.fetch(key, default))
        end

        # Get the blue values (alignment zones)
        #
        # Blue values define vertical zones for overshoot suppression
        #
        # @return [Array<Integer>, nil] Array of blue values (pairs of bottom/top)
        def blue_values
          @dict[:blue_values]
        end

        # Get the other blue values
        #
        # Additional alignment zones beyond the baseline and cap height
        #
        # @return [Array<Integer>, nil] Array of other blue values
        def other_blues
          @dict[:other_blues]
        end

        # Get the family blue values
        #
        # Family-wide alignment zones shared across fonts in a family
        #
        # @return [Array<Integer>, nil] Array of family blue values
        def family_blues
          @dict[:family_blues]
        end

        # Get the family other blue values
        #
        # @return [Array<Integer>, nil] Array of family other blue values
        def family_other_blues
          @dict[:family_other_blues]
        end

        # Get the blue scale
        #
        # Point size at which overshoot suppression is maximum
        #
        # @return [Float] Blue scale value
        def blue_scale
          fetch(:blue_scale)
        end

        # Get the blue shift
        #
        # Number of device pixels to shift alignment zones
        #
        # @return [Integer] Blue shift in pixels
        def blue_shift
          fetch(:blue_shift)
        end

        # Get the blue fuzz
        #
        # Tolerance for alignment zone matching
        #
        # @return [Integer] Blue fuzz in font units
        def blue_fuzz
          fetch(:blue_fuzz)
        end

        # Get the standard horizontal width
        #
        # Dominant horizontal stem width
        #
        # @return [Integer, nil] Standard horizontal width
        def std_hw
          value = @dict[:std_hw]
          # std_hw is stored as an array with one element
          value.is_a?(Array) ? value.first : value
        end

        # Get the standard vertical width
        #
        # Dominant vertical stem width
        #
        # @return [Integer, nil] Standard vertical width
        def std_vw
          value = @dict[:std_vw]
          # std_vw is stored as an array with one element
          value.is_a?(Array) ? value.first : value
        end

        # Get the horizontal stem snap widths
        #
        # Array of horizontal stem widths for stem snapping
        #
        # @return [Array<Integer>, nil] Horizontal stem snap widths
        def stem_snap_h
          @dict[:stem_snap_h]
        end

        # Get the vertical stem snap widths
        #
        # Array of vertical stem widths for stem snapping
        #
        # @return [Array<Integer>, nil] Vertical stem snap widths
        def stem_snap_v
          @dict[:stem_snap_v]
        end

        # Check if force bold is enabled
        #
        # @return [Boolean] True if force bold is enabled
        def force_bold?
          fetch(:force_bold)
        end

        # Get the language group
        #
        # 0 = Latin/Greek/Cyrillic, 1 = CJK
        #
        # @return [Integer] Language group (0 or 1)
        def language_group
          fetch(:language_group)
        end

        # Get the expansion factor
        #
        # Controls horizontal counter expansion
        #
        # @return [Float] Expansion factor
        def expansion_factor
          fetch(:expansion_factor)
        end

        # Get the initial random seed
        #
        # Seed for pseudo-random number generation in Type 1 hinting
        #
        # @return [Integer] Initial random seed
        def initial_random_seed
          fetch(:initial_random_seed)
        end

        # Get the Local Subr INDEX offset
        #
        # Offset is relative to the beginning of the Private DICT
        #
        # @return [Integer, nil] Offset to Local Subr INDEX
        def subrs
          @dict[:subrs]
        end

        # Get the default glyph width
        #
        # Used when width is not explicitly specified in CharString
        #
        # @return [Integer] Default width in font units
        def default_width_x
          fetch(:default_width_x)
        end

        # Get the nominal glyph width
        #
        # Base value for width calculations in CharStrings
        #
        # @return [Integer] Nominal width in font units
        def nominal_width_x
          fetch(:nominal_width_x)
        end

        # Check if this Private DICT has local subroutines
        #
        # @return [Boolean] True if subrs offset is present
        def has_local_subrs?
          !subrs.nil?
        end

        # Check if this Private DICT has blue values defined
        #
        # @return [Boolean] True if blue values are present
        def has_blue_values?
          !blue_values.nil? && !blue_values.empty?
        end

        # Check if this is for CJK language group
        #
        # @return [Boolean] True if language group is 1 (CJK)
        def cjk?
          language_group == 1
        end

        private

        # Get Private DICT specific operators
        #
        # @return [Hash] Private DICT operators merged with base operators
        def derived_operators
          PRIVATE_DICT_OPERATORS
        end
      end
    end
  end
end
