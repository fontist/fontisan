# frozen_string_literal: true

require_relative "dict"

module Fontisan
  module Tables
    class Cff
      # CFF Top DICT structure
      #
      # The Top DICT contains font-level metadata and pointers to other CFF
      # structures like CharStrings, Charset, Encoding, and Private DICT.
      #
      # Top DICT Operators (in addition to common DICT operators):
      # - charset: Offset to Charset data
      # - encoding: Offset to Encoding data
      # - charstrings: Offset to CharStrings INDEX
      # - private: Size and offset to Private DICT
      # - font_bbox: Font bounding box [xMin, yMin, xMax, yMax]
      # - unique_id: Unique ID for this font
      # - xuid: Extended unique ID array
      # - ros: CIDFont registry, ordering, supplement
      # - cidcount: Number of CIDs in CIDFont
      # - fdarray: Offset to Font DICT INDEX (CIDFont)
      # - fdselect: Offset to FDSelect data (CIDFont)
      #
      # Reference: CFF specification section 9 "Top DICT"
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
      #
      # @example Parsing a Top DICT
      #   top_dict_data = cff.top_dict_index[0]
      #   top_dict = Fontisan::Tables::Cff::TopDict.new(top_dict_data)
      #   puts top_dict[:charstrings]  # => offset to CharStrings
      #   puts top_dict[:charset]      # => offset to Charset
      class TopDict < Dict
        # Top DICT specific operators
        #
        # These extend the common operators defined in the base Dict class
        TOP_DICT_OPERATORS = {
          5 => :font_bbox,
          13 => :unique_id,
          14 => :xuid,
          15 => :charset,
          16 => :encoding,
          17 => :charstrings,
          18 => :private,
          [12, 30] => :ros,
          [12, 31] => :cid_font_version,
          [12, 32] => :cid_font_revision,
          [12, 33] => :cid_font_type,
          [12, 34] => :cid_count,
          [12, 35] => :uid_base,
          [12, 36] => :fd_array,
          [12, 37] => :fd_select,
          [12, 38] => :font_name,
        }.freeze

        # Default values for Top DICT operators
        #
        # These are used when an operator is not present in the DICT
        DEFAULTS = {
          is_fixed_pitch: false,
          italic_angle: 0,
          underline_position: -100,
          underline_thickness: 50,
          paint_type: 0,
          charstring_type: 2,
          font_matrix: [0.001, 0, 0, 0.001, 0, 0],
          unique_id: nil,
          font_bbox: [0, 0, 0, 0],
          stroke_width: 0,
          charset: 0,       # Offset 0 = ISOAdobe charset
          encoding: 0,      # Offset 0 = Standard encoding
          cid_count: 8720,
        }.freeze

        # Get a value with default fallback
        #
        # @param key [Symbol] Operator name
        # @return [Object] Value or default value
        def fetch(key, default = nil)
          @dict.fetch(key, DEFAULTS.fetch(key, default))
        end

        # Get the charset offset
        #
        # Charset determines which glyphs are present and their SIDs
        #
        # Special values:
        # - 0: ISOAdobe charset
        # - 1: Expert charset
        # - 2: Expert Subset charset
        # - Otherwise: Offset to custom charset
        #
        # @return [Integer] Charset offset or predefined charset ID
        def charset
          fetch(:charset)
        end

        # Get the encoding offset
        #
        # Encoding maps character codes to glyph indices
        #
        # Special values:
        # - 0: Standard encoding
        # - 1: Expert encoding
        # - Otherwise: Offset to custom encoding
        #
        # @return [Integer] Encoding offset or predefined encoding ID
        def encoding
          fetch(:encoding)
        end

        # Get the CharStrings offset
        #
        # CharStrings INDEX contains the glyph programs (outline data)
        #
        # @return [Integer, nil] Offset to CharStrings INDEX
        def charstrings
          @dict[:charstrings]
        end

        # Get the Private DICT size and offset
        #
        # The private operator stores [size, offset] as a two-element array
        #
        # @return [Array<Integer>, nil] [size, offset] or nil if not present
        def private
          @dict[:private]
        end

        # Get the Private DICT size
        #
        # @return [Integer, nil] Size in bytes, or nil if no Private DICT
        def private_size
          private&.first
        end

        # Get the Private DICT offset
        #
        # @return [Integer, nil] Offset in bytes, or nil if no Private DICT
        def private_offset
          private&.last
        end

        # Get the font bounding box
        #
        # @return [Array<Integer>] [xMin, yMin, xMax, yMax]
        def font_bbox
          fetch(:font_bbox)
        end

        # Get the font matrix
        #
        # Transform from glyph space to user space
        #
        # @return [Array<Float>] 6-element affine transformation matrix
        def font_matrix
          fetch(:font_matrix)
        end

        # Check if this is a CIDFont
        #
        # CIDFonts have the ROS (Registry-Ordering-Supplement) operator
        #
        # @return [Boolean] True if CIDFont
        def cid_font?
          has_key?(:ros)
        end

        # Get the ROS (Registry, Ordering, Supplement) for CIDFonts
        #
        # @return [Array<Integer>, nil] [registry_sid, ordering_sid, supplement]
        def ros
          @dict[:ros]
        end

        # Get the CID count for CIDFonts
        #
        # @return [Integer] Number of CIDs
        def cid_count
          fetch(:cid_count)
        end

        # Get the FDArray offset for CIDFonts
        #
        # FDArray is a Font DICT INDEX for CIDFonts
        #
        # @return [Integer, nil] Offset to FDArray
        def fd_array
          @dict[:fd_array]
        end

        # Get the FDSelect offset for CIDFonts
        #
        # FDSelect maps CIDs to Font DICTs in FDArray
        #
        # @return [Integer, nil] Offset to FDSelect
        def fd_select
          @dict[:fd_select]
        end

        # Get the CharString type
        #
        # @return [Integer] CharString type (typically 2 for Type 2 CharStrings)
        def charstring_type
          fetch(:charstring_type)
        end

        # Check if the font has a custom charset
        #
        # @return [Boolean] True if charset is custom (not 0, 1, or 2)
        def custom_charset?
          charset_val = charset
          charset_val && charset_val > 2
        end

        # Check if the font has a custom encoding
        #
        # @return [Boolean] True if encoding is custom (not 0 or 1)
        def custom_encoding?
          encoding_val = encoding
          encoding_val && encoding_val > 1
        end

        private

        # Get Top DICT specific operators
        #
        # @return [Hash] Top DICT operators merged with base operators
        def derived_operators
          TOP_DICT_OPERATORS
        end
      end
    end
  end
end
