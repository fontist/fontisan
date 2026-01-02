# frozen_string_literal: true

module Fontisan
  module Tables
    # Parser for the 'post' (PostScript) table
    #
    # The post table contains PostScript information, primarily glyph names.
    # Different versions exist (1.0, 2.0, 2.5, 3.0, 4.0) with varying
    # glyph name storage strategies.
    #
    # Reference: OpenType specification, post table
    class Post < Binary::BaseRecord
      # Standard Mac glyph names for version 1.0 (258 glyphs)
      # rubocop:disable Metrics/CollectionLiteralLength
      STANDARD_NAMES = %w[
        .notdef .null nonmarkingreturn space exclam quotedbl numbersign
        dollar percent ampersand quotesingle parenleft parenright asterisk
        plus comma hyphen period slash zero one two three four five six
        seven eight nine colon semicolon less equal greater question at
        A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
        bracketleft backslash bracketright asciicircum underscore grave
        a b c d e f g h i j k l m n o p q r s t u v w x y z
        braceleft bar braceright asciitilde Adieresis Aring Ccedilla
        Eacute Ntilde Odieresis Udieresis aacute agrave acircumflex
        adieresis atilde aring ccedilla eacute egrave ecircumflex
        edieresis iacute igrave icircumflex idieresis ntilde oacute
        ograve ocircumflex odieresis otilde uacute ugrave ucircumflex
        udieresis dagger degree cent sterling section bullet paragraph
        germandbls registered copyright trademark acute dieresis notequal
        AE Oslash infinity plusminus lessequal greaterequal yen mu
        partialdiff summation product pi integral ordfeminine ordmasculine
        Omega ae oslash questiondown exclamdown logicalnot radical florin
        approxequal Delta guillemotleft guillemotright ellipsis
        nonbreakingspace Agrave Atilde Otilde OE oe endash emdash
        quotedblleft quotedblright quoteleft quoteright divide lozenge
        ydieresis Ydieresis fraction currency guilsinglleft guilsinglright
        fi fl daggerdbl periodcentered quotesinglbase quotedblbase
        perthousand Acircumflex Ecircumflex Aacute Edieresis Egrave
        Iacute Icircumflex Idieresis Igrave Oacute Ocircumflex apple
        Ograve Uacute Ucircumflex Ugrave dotlessi circumflex tilde
        macron breve dotaccent ring cedilla hungarumlaut ogonek caron
        Lslash lslash Scaron scaron Zcaron zcaron brokenbar Eth
        eth Yacute yacute Thorn thorn minus multiply onesuperior
        twosuperior threesuperior onehalf onequarter threequarters franc
        Gbreve gbreve Idotaccent Scedilla scedilla Cacute cacute Ccaron
        ccaron dcroat
      ].freeze
      # rubocop:enable Metrics/CollectionLiteralLength

      # Version 2.0 as Fixed 16.16 constant
      VERSION_2_0_RAW = 131_072 # 2.0 * 65536

      endian :big

      int32 :version_raw
      int32 :italic_angle_raw
      int16 :underline_position
      int16 :underline_thickness
      uint32 :is_fixed_pitch
      uint32 :min_mem_type42
      uint32 :max_mem_type42
      uint32 :min_mem_type1
      uint32 :max_mem_type1

      # Version 2.0 specific fields
      uint16 :num_glyphs_v2, onlyif: -> { version_raw == VERSION_2_0_RAW }
      rest :remaining_data

      # Get version as float (Fixed 16.16 format)
      def version
        fixed_to_float(version_raw)
      end

      # Get italic angle as float (Fixed 16.16 format)
      def italic_angle
        fixed_to_float(italic_angle_raw)
      end

      # Get glyph names based on version
      #
      # @return [Array<String>] array of glyph names
      def glyph_names
        @glyph_names ||= case version
                         when 1.0
                           STANDARD_NAMES.dup
                         when 2.0
                           parse_version_2_names
                         else
                           []
                         end
      end

      private

      # Parse version 2.0 glyph names
      #
      # Version 2.0 uses a combination of standard Mac names (indices 0-257)
      # and custom names (indices >= 258) stored as Pascal strings.
      # rubocop:disable Metrics/PerceivedComplexity
      def parse_version_2_names
        return [] unless version_raw == VERSION_2_0_RAW
        return [] if remaining_data.empty?

        data = remaining_data
        offset = 0

        # Read glyph name indices (uint16 array)
        indices = []
        num_glyphs_v2.times do
          break if offset + 2 > data.length

          index = data[offset, 2].unpack1("n")
          indices << index
          offset += 2
        end

        # Read Pascal strings for custom names (index >= 258)
        custom_names = []
        while offset < data.length
          length = data[offset].ord
          offset += 1
          break if length.zero? || offset + length > data.length

          name = data[offset, length]
          offset += length
          custom_names << name
        end

        # Map indices to names
        indices.map do |index|
          if index < 258
            # Standard Mac name
            STANDARD_NAMES[index]
          else
            # Custom name
            custom_index = index - 258
            if custom_index < custom_names.length
              custom_names[custom_index]
            else
              ".notdef"
            end
          end
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      public

      # Validation helper: Check if version is valid
      #
      # Common versions: 1.0, 2.0, 2.5, 3.0, 4.0
      #
      # @return [Boolean] True if version is recognized
      def valid_version?
        [1.0, 2.0, 2.5, 3.0, 4.0].include?(version)
      end

      # Validation helper: Check if italic angle is reasonable
      #
      # Italic angle should be between -60 and 60 degrees
      #
      # @return [Boolean] True if italic angle is within reasonable bounds
      def valid_italic_angle?
        italic_angle.abs <= 60.0
      end

      # Validation helper: Check if underline values are present
      #
      # Both position and thickness should be non-zero for valid underline
      #
      # @return [Boolean] True if underline metrics exist
      def has_underline_metrics?
        underline_position != 0 && underline_thickness != 0
      end

      # Validation helper: Check if fixed pitch flag is consistent
      #
      # @return [Boolean] True if is_fixed_pitch is 0 or 1
      def valid_fixed_pitch_flag?
        is_fixed_pitch == 0 || is_fixed_pitch == 1
      end

      # Validation helper: Check if glyph names are available
      #
      # For versions 1.0 and 2.0, glyph names should be accessible
      #
      # @return [Boolean] True if glyph names can be retrieved
      def has_glyph_names?
        names = glyph_names
        !names.nil? && !names.empty?
      end

      # Validation helper: Check if version 2.0 data is complete
      #
      # For version 2.0, we should have glyph count and name data
      #
      # @return [Boolean] True if version 2.0 data is present and complete
      def complete_version_2_data?
        return true unless version == 2.0

        !num_glyphs_v2.nil? && num_glyphs_v2 > 0 && !remaining_data.empty?
      end
    end
  end
end
