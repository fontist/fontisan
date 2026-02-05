# frozen_string_literal: true

module Fontisan
  module Type1
    # Type 1 Private Dictionary model
    #
    # [`PrivateDict`](lib/fontisan/type1/private_dict.rb) parses and stores
    # the private dictionary from a Type 1 font, which contains hinting
    # and spacing information used by the CharString interpreter.
    #
    # The private dictionary includes:
    # - BlueValues and OtherBlues (alignment zones for optical consistency)
    # - StdHW and StdVW (standard stem widths)
    # - StemSnapH and StemSnapV (stem snap arrays)
    # - Subrs (local subroutines)
    # - lenIV (CharString encryption IV length)
    #
    # @example Parse private dictionary from decrypted font data
    #   priv = Fontisan::Type1::PrivateDict.parse(decrypted_data)
    #   puts priv.blue_values
    #   puts priv.std_hw
    #
    # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
    class PrivateDict
      # @return [Array<Integer>] BlueValues alignment zones
      attr_accessor :blue_values

      # @return [Array<Integer>] OtherBlues alignment zones
      attr_accessor :other_blues

      # @return [Array<Integer>] FamilyBlues alignment zones
      attr_accessor :family_blues

      # @return [Array<Integer>] FamilyOtherBlues alignment zones
      attr_accessor :family_other_blues

      # @return [Float] BlueScale
      attr_accessor :blue_scale

      # @return [Integer] BlueShift
      attr_accessor :blue_shift

      # @return [Integer] BlueFuzz
      attr_accessor :blue_fuzz

      # @return [Array<Float>] StdHW (standard horizontal width)
      attr_accessor :std_hw

      # @return [Array<Float>] StdVW (standard vertical width)
      attr_accessor :std_vw

      # @return [Array<Float>] StemSnapH (horizontal stem snap array)
      attr_accessor :stem_snap_h

      # @return [Array<Float>] StemSnapV (vertical stem snap array)
      attr_accessor :stem_snap_v

      # @return [Boolean] ForceBold flag
      attr_accessor :force_bold

      # @return [Integer] lenIV (CharString encryption IV length)
      attr_accessor :len_iv

      # @return [Array<String>] Subrs (local subroutines)
      attr_accessor :subrs

      # @return [Integer] LanguageGroup (0 for Latin, 1 for Japanese, etc.)
      attr_accessor :language_group

      # @return [Float] ExpansionFactor for counter widening
      attr_accessor :expansion_factor

      # @return [Integer] InitialRandomSeed for randomization
      attr_accessor :initial_random_seed

      # @return [Hash] Raw dictionary data
      attr_reader :raw_data

      # Parse private dictionary from decrypted Type 1 font data
      #
      # @param data [String] Decrypted Type 1 font data
      # @return [PrivateDict] Parsed private dictionary
      # @raise [Fontisan::Error] If dictionary cannot be parsed
      #
      # @example Parse from decrypted font data
      #   priv = Fontisan::Type1::PrivateDict.parse(decrypted_data)
      def self.parse(data)
        new.parse(data)
      end

      # Initialize a new PrivateDict
      def initialize
        @blue_values = []
        @other_blues = []
        @family_blues = []
        @family_other_blues = []
        @blue_scale = 0.039625
        @blue_shift = 7
        @blue_fuzz = 1
        @std_hw = []
        @std_vw = []
        @stem_snap_h = []
        @stem_snap_v = []
        @force_bold = false
        @len_iv = 4
        @subrs = []
        @language_group = 0
        @expansion_factor = 0.06
        @initial_random_seed = 0
        @raw_data = {}
        @parsed = false
      end

      # Parse private dictionary from decrypted Type 1 font data
      #
      # @param data [String] Decrypted Type 1 font data
      # @return [PrivateDict] Self for method chaining
      def parse(data)
        extract_private_dict(data)
        extract_properties
        @parsed = true
        self
      end

      # Check if dictionary was successfully parsed
      #
      # @return [Boolean] True if dictionary has been parsed
      def parsed?
        @parsed
      end

      # Get raw value from dictionary
      #
      # @param key [String] Dictionary key
      # @return [Object, nil] Value or nil if not found
      def [](key)
        @raw_data[key]
      end

      # Get effective BlueValues for hinting
      #
      # Returns BlueValues adjusted by BlueScale.
      #
      # @return [Array<Float>] Scaled blue values
      def effective_blue_values
        return [] if @blue_values.empty?

        @blue_values.map { |v| v * @blue_scale }
      end

      # Check if font has blues
      #
      # @return [Boolean] True if BlueValues or OtherBlues are defined
      def has_blues?
        !@blue_values.empty? || !@other_blues.empty?
      end

      # Check if font has stem hints
      #
      # @return [Boolean] True if StdHW, StdVW, or StemSnap arrays are defined
      def has_stem_hints?
        !@std_hw.empty? || !@std_vw.empty? ||
          !@stem_snap_h.empty? || !@stem_snap_v.empty?
      end

      # Convert PrivateDict to Type 1 text format
      #
      # Generates the PostScript code for the Private dictionary section
      # of a Type 1 font.
      #
      # @return [String] Type 1 Private dictionary text
      #
      # @example Generate Type 1 format
      #   priv = PrivateDict.new
      #   priv.blue_values = [-10, 0, 470, 480]
      #   puts priv.to_type1_format
      def to_type1_format
        result = []
        unless @blue_values.empty?
          result << array_to_type1(:BlueValues,
                                   @blue_values)
        end
        unless @other_blues.empty?
          result << array_to_type1(:OtherBlues,
                                   @other_blues)
        end
        unless @family_blues.empty?
          result << array_to_type1(:FamilyBlues,
                                   @family_blues)
        end
        unless @family_other_blues.empty?
          result << array_to_type1(:FamilyOtherBlues,
                                   @family_other_blues)
        end
        result << scalar_to_type1(:BlueScale, @blue_scale)
        result << scalar_to_type1(:BlueShift, @blue_shift)
        result << scalar_to_type1(:BlueFuzz, @blue_fuzz)
        result << array_to_type1(:StdHW, @std_hw) unless @std_hw.empty?
        result << array_to_type1(:StdVW, @std_vw) unless @std_vw.empty?
        unless @stem_snap_h.empty?
          result << array_to_type1(:StemSnapH,
                                   @stem_snap_h)
        end
        unless @stem_snap_v.empty?
          result << array_to_type1(:StemSnapV,
                                   @stem_snap_v)
        end
        unless @force_bold == false
          result << boolean_to_type1(:ForceBold,
                                     @force_bold)
        end
        result << scalar_to_type1(:lenIV, @len_iv)

        result.join("\n")
      end

      # Format an array value for Type 1 output
      #
      # @param name [Symbol] Array name
      # @param value [Array] Array value
      # @return [String] Formatted Type 1 array definition
      def array_to_type1(name, value)
        "/#{name} [#{value.join(' ')}] def"
      end

      # Format a scalar value for Type 1 output
      #
      # @param name [Symbol] Value name
      # @param value [Numeric] Numeric value
      # @return [String] Formatted Type 1 scalar definition
      def scalar_to_type1(name, value)
        "/#{name} #{value} def"
      end

      # Format a boolean value for Type 1 output
      #
      # @param name [Symbol] Value name
      # @param value [Boolean] Boolean value
      # @return [String] Formatted Type 1 boolean definition
      def boolean_to_type1(name, value)
        "/#{name} #{value} def"
      end

      private

      # Extract private dictionary from data
      #
      # @param data [String] Decrypted Type 1 font data
      def extract_private_dict(data)
        # Find the Private dictionary definition
        # Type 1 fonts have: /Private <dict_size> dict def ... end

        # Look for /Private dict def pattern - use safer pattern
        # Match until we find the matching 'end' keyword
        private_match = data.match(%r{/Private\s+\d+\s+dict\s+def\b(.*)end}m)
        return if private_match.nil?

        private_text = private_match[1]
        @raw_data = parse_private_dict_text(private_text)
      end

      # Parse private dictionary text
      #
      # @param text [String] Private dictionary text
      # @return [Hash] Parsed key-value pairs
      def parse_private_dict_text(text)
        result = {}

        # Parse BlueValues array
        if (match = text.match(/\/BlueValues\s*\[([^\]]+)\]\s+def/m))
          result[:blue_values] = parse_array(match[1])
        end

        # Parse OtherBlues array
        if (match = text.match(/\/OtherBlues\s*\[([^\]]+)\]\s+def/m))
          result[:other_blues] = parse_array(match[1])
        end

        # Parse FamilyBlues array
        if (match = text.match(/\/FamilyBlues\s*\[([^\]]+)\]\s+def/m))
          result[:family_blues] = parse_array(match[1])
        end

        # Parse FamilyOtherBlues array
        if (match = text.match(/\/FamilyOtherBlues\s*\[([^\]]+)\]\s+def/m))
          result[:family_other_blues] = parse_array(match[1])
        end

        # Parse BlueScale
        if (match = text.match(/\/BlueScale\s+([0-9.-]+)\s+def/m))
          result[:blue_scale] = match[1].to_f
        end

        # Parse BlueShift
        if (match = text.match(/\/BlueShift\s+(\d+)\s+def/m))
          result[:blue_shift] = match[1].to_i
        end

        # Parse BlueFuzz
        if (match = text.match(/\/BlueFuzz\s+(\d+)\s+def/m))
          result[:blue_fuzz] = match[1].to_i
        end

        # Parse StdHW array
        if (match = text.match(/\/StdHW\s*\[([^\]]+)\]\s+def/m))
          result[:std_hw] = parse_array(match[1]).map(&:to_f)
        end

        # Parse StdVW array
        if (match = text.match(/\/StdVW\s*\[([^\]]+)\]\s+def/m))
          result[:std_vw] = parse_array(match[1]).map(&:to_f)
        end

        # Parse StemSnapH array
        if (match = text.match(/\/StemSnapH\s*\[([^\]]+)\]\s+def/m))
          result[:stem_snap_h] = parse_array(match[1]).map(&:to_f)
        end

        # Parse StemSnapV array
        if (match = text.match(/\/StemSnapV\s*\[([^\]]+)\]\s+def/m))
          result[:stem_snap_v] = parse_array(match[1]).map(&:to_f)
        end

        # Parse ForceBold
        if (match = text.match(/\/ForceBold\s+(true|false)\s+def/m))
          result[:force_bold] = match[1] == "true"
        end

        # Parse lenIV
        if (match = text.match(/\/lenIV\s+(\d+)\s+def/m))
          result[:len_iv] = match[1].to_i
        end

        result
      end

      # Parse array from string
      #
      # @param str [String] Array string (e.g., "1 2 3 4")
      # @return [Array<Integer>] Parsed integers
      def parse_array(str)
        str.strip.split.map(&:strip).reject(&:empty?).map(&:to_i)
      end

      # Extract properties from raw data
      def extract_properties
        @blue_values = @raw_data[:blue_values] || []
        @other_blues = @raw_data[:other_blues] || []
        @family_blues = @raw_data[:family_blues] || []
        @family_other_blues = @raw_data[:family_other_blues] || []
        @blue_scale = @raw_data[:blue_scale] || 0.039625
        @blue_shift = @raw_data[:blue_shift] || 7
        @blue_fuzz = @raw_data[:blue_fuzz] || 1
        @std_hw = @raw_data[:std_hw] || []
        @std_vw = @raw_data[:std_vw] || []
        @stem_snap_h = @raw_data[:stem_snap_h] || []
        @stem_snap_v = @raw_data[:stem_snap_v] || []
        @force_bold = @raw_data[:force_bold] || false
        @len_iv = @raw_data[:len_iv] || 4
      end
    end
  end
end
