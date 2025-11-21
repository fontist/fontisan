# frozen_string_literal: true

require_relative "index"
require_relative "charstring"

module Fontisan
  module Tables
    class Cff
      # CharStrings INDEX wrapper
      #
      # This class wraps the CharStrings INDEX to provide convenient access
      # to individual CharString objects. The CharStrings INDEX contains the
      # glyph outline programs (Type 2 CharStrings) for each glyph in the font.
      #
      # CharStrings Format:
      # - INDEX structure containing binary CharString data
      # - Each entry is a Type 2 CharString program
      # - Number of entries typically matches the number of glyphs
      # - Index 0 is typically .notdef glyph
      #
      # Usage:
      # 1. Create from raw CharStrings INDEX data
      # 2. Provide Private DICT and subroutine INDEXes for interpretation
      # 3. Access individual CharStrings by glyph index
      #
      # Reference: CFF specification section 16 "Local/Global Subrs INDEXes"
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
      #
      # @example Using CharStringsIndex
      #   # Get CharStrings INDEX from CFF table
      #   charstrings_offset = top_dict.charstrings
      #   io = StringIO.new(cff.raw_data)
      #   io.seek(charstrings_offset)
      #   charstrings_index = CharstringsIndex.new(io, start_offset:
      #                                             charstrings_offset)
      #
      #   # Get a specific CharString
      #   charstring = charstrings_index.charstring_at(
      #     glyph_index,
      #     private_dict,
      #     global_subrs,
      #     local_subrs
      #   )
      #
      #   # Access CharString properties
      #   puts charstring.width
      #   puts charstring.bounding_box
      #   charstring.to_commands.each { |cmd| puts cmd.inspect }
      class CharstringsIndex < Index
        # Get a CharString object at the specified glyph index
        #
        # This method retrieves the binary CharString data at the given index
        # and interprets it as a Type 2 CharString program.
        #
        # @param index [Integer] Glyph index (0-based, 0 is typically .notdef)
        # @param private_dict [PrivateDict] Private DICT for width defaults
        # @param global_subrs [Index] Global subroutines INDEX
        # @param local_subrs [Index, nil] Local subroutines INDEX (optional)
        # @return [CharString, nil] Interpreted CharString object, or nil if
        #   index is out of bounds
        #
        # @example Getting a CharString
        #   charstring = charstrings_index.charstring_at(
        #     42,
        #     private_dict,
        #     global_subrs,
        #     local_subrs
        #   )
        #   puts "Width: #{charstring.width}"
        #   puts "Bounding box: #{charstring.bounding_box.inspect}"
        def charstring_at(index, private_dict, global_subrs, local_subrs = nil)
          data = self[index]
          return nil unless data

          CharString.new(data, private_dict, global_subrs, local_subrs)
        end

        # Get all CharStrings as an array of CharString objects
        #
        # This method interprets all CharStrings in the INDEX. Use with
        # caution for fonts with many glyphs as this can be memory-intensive.
        #
        # @param private_dict [PrivateDict] Private DICT for width defaults
        # @param global_subrs [Index] Global subroutines INDEX
        # @param local_subrs [Index, nil] Local subroutines INDEX (optional)
        # @return [Array<CharString>] Array of interpreted CharString objects
        #
        # @example Getting all CharStrings
        #   charstrings = charstrings_index.all_charstrings(
        #     private_dict,
        #     global_subrs,
        #     local_subrs
        #   )
        #   charstrings.each_with_index do |cs, i|
        #     puts "Glyph #{i}: width=#{cs.width}, bbox=#{cs.bounding_box}"
        #   end
        def all_charstrings(private_dict, global_subrs, local_subrs = nil)
          Array.new(count) do |i|
            charstring_at(i, private_dict, global_subrs, local_subrs)
          end
        end

        # Iterate over each CharString in the INDEX
        #
        # This method yields each CharString as it is interpreted, which is
        # more memory-efficient than loading all at once.
        #
        # @param private_dict [PrivateDict] Private DICT for width defaults
        # @param global_subrs [Index] Global subroutines INDEX
        # @param local_subrs [Index, nil] Local subroutines INDEX (optional)
        # @yield [CharString, Integer] Interpreted CharString and its index
        # @return [Enumerator] If no block given
        #
        # @example Iterating over CharStrings
        #   charstrings_index.each_charstring(private_dict, global_subrs,
        #                                     local_subrs) do |cs, index|
        #     puts "Glyph #{index}: #{cs.bounding_box}"
        #   end
        def each_charstring(private_dict, global_subrs, local_subrs = nil)
          unless block_given?
            return enum_for(:each_charstring, private_dict, global_subrs,
                            local_subrs)
          end

          count.times do |i|
            charstring = charstring_at(i, private_dict, global_subrs,
                                       local_subrs)
            yield charstring, i if charstring
          end
        end

        # Get the number of glyphs (CharStrings) in this INDEX
        #
        # This is typically the same as the number of glyphs in the font.
        #
        # @return [Integer] Number of glyphs
        def glyph_count
          count
        end

        # Check if a glyph index is valid
        #
        # @param index [Integer] Glyph index to check
        # @return [Boolean] True if index is valid
        def valid_glyph_index?(index)
          index >= 0 && index < count
        end

        # Get the size of a CharString in bytes
        #
        # This returns the size of the binary CharString data without
        # interpreting it.
        #
        # @param index [Integer] Glyph index
        # @return [Integer, nil] Size in bytes, or nil if index is invalid
        def charstring_size(index)
          item_size(index)
        end
      end
    end
  end
end
