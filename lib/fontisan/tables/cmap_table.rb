# frozen_string_literal: true

require_relative "../sfnt_table"
require_relative "cmap"

module Fontisan
  module Tables
    # OOP representation of the 'cmap' (Character to Glyph Index Mapping) table
    #
    # The cmap table maps character codes to glyph indices, supporting multiple
    # encoding formats for different character sets and Unicode planes.
    #
    # This class extends SfntTable to provide cmap-specific validation and
    # convenience methods for character-to-glyph mapping.
    #
    # @example Mapping characters to glyphs
    #   cmap = font.sfnt_table("cmap")
    #   cmap.glyph_for('A')        # => 36
    #   cmap.glyph_for(0x0041)     # => 36 (same as 'A')
    #   cmap.has_glyph?('€')       # => true
    #   cmap.character_count       # => 1234
    class CmapTable < SfntTable
      # Get Unicode character to glyph index mappings
      #
      # @return [Hash<Integer, Integer>] Mapping from Unicode codepoints to glyph IDs
      def unicode_mappings
        return {} unless parsed

        parsed.unicode_mappings || {}
      end

      # Get glyph ID for a character
      #
      # @param char [String, Integer] Character (string or Unicode codepoint)
      # @return [Integer, nil] Glyph ID, or nil if character not mapped
      def glyph_for(char)
        codepoint = char.is_a?(String) ? char.ord : char
        unicode_mappings[codepoint]
      end

      # Check if a character has a glyph mapping
      #
      # @param char [String, Integer] Character (string or Unicode codepoint)
      # @return [Boolean] true if character is mapped to a glyph
      def has_glyph?(char)
        !glyph_for(char).nil?
      end

      # Check if multiple characters have glyph mappings
      #
      # @param chars [Array<String, Integer>] Characters to check
      # @return [Boolean] true if all characters are mapped
      def has_glyphs?(*chars)
        chars.all? { |char| has_glyph?(char) }
      end

      # Get the number of mapped characters
      #
      # @return [Integer] Number of unique character mappings
      def character_count
        unicode_mappings.size
      end

      # Get all mapped character codes
      #
      # @return [Array<Integer>] Array of Unicode codepoints
      def character_codes
        unicode_mappings.keys.sort
      end

      # Get all mapped glyphs
      #
      # @return [Array<Integer>] Array of glyph IDs
      def glyph_ids
        unicode_mappings.values.uniq.sort
      end

      # Check if BMP (Basic Multilingual Plane) coverage exists
      #
      # @return [Boolean] true if BMP characters (U+0000-U+FFFF) are mapped
      def has_bmp_coverage?
        return false unless parsed

        parsed.has_bmp_coverage?
      end

      # Check if specific required characters are mapped
      #
      # @param chars [Array<Integer>] Unicode codepoints that must be present
      # @return [Boolean] true if all required characters are mapped
      def has_required_characters?(*chars)
        return false unless parsed

        parsed.has_required_characters?(*chars)
      end

      # Check if space character is mapped
      #
      # @return [Boolean] true if U+0020 (space) is mapped
      def has_space?
        has_glyph?(0x0020)
      end

      # Check if common Latin characters are mapped
      #
      # @return [Boolean] true if A-Z, a-z are mapped
      def has_basic_latin?
        # Check uppercase A-Z
        return false unless has_glyphs?(*(0x0041..0x005A).to_a)

        # Check lowercase a-z
        has_glyphs?(*(0x0061..0x007A).to_a)
      end

      # Check if digits are mapped
      #
      # @return [Boolean] true if 0-9 are mapped
      def has_digits?
        has_glyphs?(*(0x0030..0x0039).to_a)
      end

      # Check if common punctuation is mapped
      #
      # @return [Boolean] true if common punctuation marks are mapped
      def has_basic_punctuation?
        required = [0x0020, 0x0021, 0x0022, 0x0027, 0x0028, 0x0029, 0x002C, 0x002E,
                    0x003A, 0x003B, 0x003F, 0x005F] # space !"()',.:;?_
        has_required_characters?(*required)
      end

      # Get glyph IDs for a string of characters
      #
      # @param text [String] Text string
      # @return [Array<Integer>] Array of glyph IDs
      def glyphs_for_text(text)
        text.chars.map { |char| glyph_for(char) || 0 }
      end

      # Create a simple text rendering glyph sequence
      #
      # @param text [String] Text string
      # @return [Array<Integer>] Array of glyph IDs for rendering
      def glyph_sequence_for(text)
        glyphs_for_text(text)
      end

      # Get the highest Unicode codepoint mapped
      #
      # @return [Integer, nil] Maximum codepoint, or nil if no mappings
      def max_codepoint
        codes = character_codes
        codes.last unless codes.empty?
      end

      # Get the lowest Unicode codepoint mapped
      #
      # @return [Integer, nil] Minimum codepoint, or nil if no mappings
      def min_codepoint
        codes = character_codes
        codes.first unless codes.empty?
      end

      # Check if font has full Unicode coverage
      #
      # @return [Boolean] true if characters beyond BMP are mapped
      def has_full_unicode?
        max_cp = max_codepoint
        !max_cp.nil? && max_cp > 0xFFFF
      end

      # Get mapping statistics
      #
      # @return [Hash] Statistics about the character mapping
      def statistics
        {
          character_count: character_count,
          glyph_count: glyph_ids.size,
          min_codepoint: min_codepoint,
          max_codepoint: max_codepoint,
          has_bmp: has_bmp_coverage?,
          has_full_unicode: has_full_unicode?,
          has_space: has_space?,
          has_basic_latin: has_basic_latin?,
          has_digits: has_digits?,
        }
      end

      protected

      # Validate the parsed cmap table
      #
      # @return [Boolean] true if valid
      # @raise [InvalidFontError] if cmap table is invalid
      def validate_parsed_table?
        return true unless parsed

        # Validate version
        unless parsed.valid_version?
          raise InvalidFontError,
                "Invalid cmap table version: #{parsed.version} (must be 0)"
        end

        # Validate subtables exist
        unless parsed.has_subtables?
          raise InvalidFontError,
                "Invalid cmap table: no subtables found (num_tables=#{parsed.num_tables})"
        end

        # Validate Unicode mapping exists
        unless parsed.has_unicode_mapping?
          raise InvalidFontError,
                "Invalid cmap table: no Unicode mappings found"
        end

        # Validate BMP coverage (required for fonts)
        unless parsed.has_bmp_coverage?
          raise InvalidFontError,
                "Invalid cmap table: no BMP character coverage found"
        end

        # Validate required characters (space at minimum)
        unless parsed.has_required_characters?(0x0020)
          raise InvalidFontError,
                "Invalid cmap table: missing required character U+0020 (space)"
        end

        true
      end
    end
  end
end
