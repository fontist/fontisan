# frozen_string_literal: true

require_relative "../tables/cff/index_builder"
require_relative "../tables/cff/dict_builder"

module Fontisan
  module Converters
    # Builds CFF table data from glyph outlines
    #
    # This module handles the construction of complete CFF tables including
    # all INDEX structures (name, Top DICT, String, GlobalSubr, CharStrings, LocalSubr)
    # and the Private DICT.
    #
    # The CFF table structure is:
    # - Header (4 bytes)
    # - Name INDEX
    # - Top DICT INDEX
    # - String INDEX
    # - Global Subr INDEX
    # - CharStrings INDEX
    # - Private DICT (with offset in Top DICT)
    # - Local Subr INDEX (with offset in Private DICT)
    module CffTableBuilder
      # Build complete CFF table from pre-built charstrings
      #
      # @param charstrings [Array<String>] Pre-built CharString data (already optimized if needed)
      # @param local_subrs [Array<String>] Local subroutines from optimization
      # @param font [TrueTypeFont] Source font (for metadata)
      # @return [String] Complete CFF table binary data
      def build_cff_table(charstrings, local_subrs, font)
        # If we have local subrs from optimization, use them
        local_subrs = [] unless local_subrs.is_a?(Array)

        # Build font metadata
        font_name = extract_font_name(font)

        # Build all INDEXes
        header_size = 4
        name_index_data = Tables::Cff::IndexBuilder.build([font_name])
        string_index_data = Tables::Cff::IndexBuilder.build([]) # Empty strings
        global_subr_index_data = Tables::Cff::IndexBuilder.build([]) # Empty global subrs
        charstrings_index_data = Tables::Cff::IndexBuilder.build(charstrings)
        local_subrs_index_data = Tables::Cff::IndexBuilder.build(local_subrs)

        # Build Private DICT with Subrs offset if we have local subroutines
        private_dict_data, private_dict_size = build_private_dict(local_subrs)

        # Calculate offsets with iterative refinement
        top_dict_index_data, =
          calculate_cff_offsets(
            header_size,
            name_index_data,
            string_index_data,
            global_subr_index_data,
            charstrings_index_data,
            private_dict_size,
          )

        # Build CFF Header
        header = build_cff_header

        # Assemble complete CFF table
        header +
          name_index_data +
          top_dict_index_data +
          string_index_data +
          global_subr_index_data +
          charstrings_index_data +
          private_dict_data +
          local_subrs_index_data
      end

      private

      # Build Private DICT with optional Subrs offset
      #
      # @param local_subrs [Array<String>] Local subroutines
      # @return [Array<String, Integer>] [Private DICT data, size]
      def build_private_dict(local_subrs)
        private_dict_hash = {
          default_width_x: 1000,
          nominal_width_x: 0,
        }

        # If we have local subroutines, add Subrs offset
        # Subrs offset is relative to Private DICT start
        if local_subrs.any?
          # Add a placeholder Subrs offset first to get accurate size
          private_dict_hash[:subrs] = 0

          # Calculate size of Private DICT with Subrs entry
          temp_private_dict_data = Tables::Cff::DictBuilder.build(private_dict_hash)
          subrs_offset = temp_private_dict_data.bytesize

          # Update with actual Subrs offset
          private_dict_hash[:subrs] = subrs_offset
        end

        # Build final Private DICT
        private_dict_data = Tables::Cff::DictBuilder.build(private_dict_hash)
        [private_dict_data, private_dict_data.bytesize]
      end

      # Calculate CFF table offsets with iterative refinement
      #
      # @param header_size [Integer] CFF header size
      # @param name_index_data [String] Name INDEX data
      # @param string_index_data [String] String INDEX data
      # @param global_subr_index_data [String] Global Subr INDEX data
      # @param charstrings_index_data [String] CharStrings INDEX data
      # @param private_dict_size [Integer] Private DICT size
      # @return [Array<String, Integer, Integer>] [Top DICT INDEX, CharStrings offset, Private DICT offset]
      def calculate_cff_offsets(
        header_size,
        name_index_data,
        string_index_data,
        global_subr_index_data,
        charstrings_index_data,
        private_dict_size
      )
        # Initial pass
        top_dict_index_start = header_size + name_index_data.bytesize
        string_index_start = top_dict_index_start + 100 # Approximate
        global_subr_index_start = string_index_start + string_index_data.bytesize
        charstrings_offset = global_subr_index_start + global_subr_index_data.bytesize

        # Build Top DICT
        top_dict_hash = {
          charset: 0,
          encoding: 0,
          charstrings: charstrings_offset,
        }
        top_dict_data = Tables::Cff::DictBuilder.build(top_dict_hash)
        top_dict_index_data = Tables::Cff::IndexBuilder.build([top_dict_data])

        # Recalculate with actual Top DICT size
        string_index_start = top_dict_index_start + top_dict_index_data.bytesize
        global_subr_index_start = string_index_start + string_index_data.bytesize
        charstrings_offset = global_subr_index_start + global_subr_index_data.bytesize
        private_dict_offset = charstrings_offset + charstrings_index_data.bytesize

        # Update Top DICT with Private DICT info
        top_dict_hash = {
          charset: 0,
          encoding: 0,
          charstrings: charstrings_offset,
          private: [private_dict_size, private_dict_offset],
        }
        top_dict_data = Tables::Cff::DictBuilder.build(top_dict_hash)
        top_dict_index_data = Tables::Cff::IndexBuilder.build([top_dict_data])

        # Final recalculation
        string_index_start = top_dict_index_start + top_dict_index_data.bytesize
        global_subr_index_start = string_index_start + string_index_data.bytesize
        charstrings_offset = global_subr_index_start + global_subr_index_data.bytesize
        private_dict_offset = charstrings_offset + charstrings_index_data.bytesize

        # Final Top DICT
        top_dict_hash = {
          charset: 0,
          encoding: 0,
          charstrings: charstrings_offset,
          private: [private_dict_size, private_dict_offset],
        }
        top_dict_data = Tables::Cff::DictBuilder.build(top_dict_hash)
        top_dict_index_data = Tables::Cff::IndexBuilder.build([top_dict_data])

        [top_dict_index_data, charstrings_offset, private_dict_offset]
      end

      # Build CFF Header
      #
      # @return [String] 4-byte CFF header
      def build_cff_header
        [
          1,    # major version
          0,    # minor version
          4,    # header size
          4,    # offSize (will be in INDEX)
        ].pack("C4")
      end

      # Extract font name from name table
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font
      # @return [String] Font name
      def extract_font_name(font)
        name_table = font.table("name")
        if name_table
          font_name = name_table.english_name(Tables::Name::FAMILY)
          return font_name.dup.force_encoding("ASCII-8BIT") if font_name
        end

        "UnnamedFont"
      end
    end
  end
end
