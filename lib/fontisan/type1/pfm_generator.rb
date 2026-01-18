# frozen_string_literal: true

require_relative "../constants"
require_relative "upm_scaler"
require_relative "afm_generator"

module Fontisan
  module Type1
    # PFM (Printer Font Metrics) file generator
    #
    # [`PFMGenerator`](lib/fontisan/type1/pfm_generator.rb) generates Printer Font Metrics
    # files from TTF/OTF fonts.
    #
    # PFM files are binary files used by Windows for printer font metrics.
    # They include:
    # - Character widths
    # - Kerning pairs
    # - Font metadata (name, version, copyright, etc.)
    # - Extended text metrics
    #
    # @example Generate PFM from TTF
    #   font = Fontisan::FontLoader.load("font.ttf")
    #   pfm_data = Fontisan::Type1::PFMGenerator.generate(font)
    #   File.binwrite("font.pfm", pfm_data)
    #
    # @example Generate PFM with 1000 UPM scaling
    #   pfm_data = Fontisan::Type1::PFMGenerator.generate(font, upm_scale: 1000)
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5005.PFM_Spec.pdf
    class PFMGenerator
      # PFM constants
      PFM_VERSION = 0x0100
      PFM_HEADER_SIZE = 256

      # Driver info structure
      DRIVER_INFO_SIZE = 118

      # Extended metrics size
      EXT_METRICS_SIZE = 48

      # Windows charset constants
      ANSI_CHARSET = 0
      DEFAULT_CHARSET = 1
      SYMBOL_CHARSET = 2

      # Font pitch and family bits
      FIXED_PITCH = 1
      VARIABLE_PITCH = 0

      # Family bits (shift left 4)
      FAMILY_DONTCARE = 0 << 4
      FAMILY_ROMAN = 1 << 4
      FAMILY_SWISS = 2 << 4
      FAMILY_MODERN = 3 << 4
      FAMILY_SCRIPT = 4 << 4
      FAMILY_DECORATIVE = 5 << 4
      FAMILY_MODERN_LOWERCASE = 6 << 4

      class << self
        # Generate PFM binary data from a font
        #
        # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] The font to generate PFM from
        # @param options [Hash] Generation options
        # @option options [Integer, :native] :upm_scale Target UPM (1000 for Type 1, :native for no scaling)
        # @return [String] PFM file binary data
        def generate(font, options = {})
          new(font, options).generate_pfm
        end

        # Generate PFM file from a font and write to file
        #
        # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] The font to generate PFM from
        # @param path [String] Path to write PFM file
        # @param options [Hash] Generation options
        # @return [void]
        def generate_to_file(font, path, options = {})
          pfm_data = generate(font, options)
          File.binwrite(path, pfm_data)
        end
      end

      # Initialize a new PFMGenerator
      #
      # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] The font to generate PFM from
      # @param options [Hash] Generation options
      def initialize(font, options = {})
        @font = font
        @metrics = MetricsCalculator.new(font)

        # Set up scaler
        upm_scale = options[:upm_scale] || 1000
        @scaler = if upm_scale == :native
                    UPMScaler.native(font)
                  else
                    UPMScaler.new(font, target_upm: upm_scale)
                  end
      end

      # Generate PFM binary data
      #
      # @return [String] PFM file binary data
      def generate_pfm
        # Collect font data
        char_widths = collect_character_widths
        return "" if char_widths.empty?

        # Build sections
        header_data = build_header(char_widths)
        face_name_data = build_face_name
        driver_info_data = build_driver_info
        ext_metrics_data = build_extended_metrics
        width_table_data = build_width_table(char_widths)
        kerning_data = build_kerning_table

        # Calculate offsets
        dfFace_offset = PFM_HEADER_SIZE
        dfExtMetrics_offset = dfFace_offset + face_name_data.length + driver_info_data.length
        dfExtentTable_offset = dfExtMetrics_offset + ext_metrics_data.length
        dfPairKernTable_offset = if kerning_data.empty?
                                   0
                                 else
                                   dfExtentTable_offset + width_table_data.length
                                 end
        dfDriverInfo_offset = if dfPairKernTable_offset.positive?
                                dfPairKernTable_offset + kerning_data.length
                              else
                                dfExtentTable_offset + width_table_data.length
                              end

        # Update offsets in header
        update_header_offsets(header_data, dfFace_offset, dfExtMetrics_offset,
                              dfExtentTable_offset, dfPairKernTable_offset,
                              dfDriverInfo_offset)

        # Combine all sections: Header + Face Name + Driver Info + Ext Metrics + Width Table + Kerning
        header_data + face_name_data + driver_info_data + ext_metrics_data +
          width_table_data + kerning_data
      end

      private

      # Collect character widths from TTF
      #
      # @return [Hash] Character index to width mapping
      def collect_character_widths
        widths = {}

        cmap = @font.table(Constants::CMAP_TAG)
        return widths unless cmap

        # Get Unicode mappings
        mappings = if cmap.respond_to?(:unicode_mappings)
                     cmap.unicode_mappings || {}
                   else
                     {}
                   end

        # Get widths for characters 0-255
        mappings.each do |codepoint, glyph_id|
          next unless codepoint >= 0 && codepoint <= 255

          width = @metrics.glyph_width(glyph_id)
          next unless width

          # Scale width
          scaled_width = @scaler.scale_width(width)
          widths[codepoint] = scaled_width
        end

        widths
      end

      # Build face name as Pascal string
      #
      # @return [String] Face name as Pascal string (length byte + string data)
      def build_face_name
        face_name = extract_face_name[0, 255] # Limit to 255 chars
        [face_name.length].pack("C") + face_name
      end

      # Build PFM header
      #
      # @param char_widths [Hash] Character widths
      # @return [String] Header binary data (256 bytes)
      def build_header(char_widths)
        header = String.new(encoding: "ASCII-8BIT")

        # Get font metrics
        hhea = @font.table(Constants::HHEA_TAG)
        head = @font.table(Constants::HEAD_TAG)
        post = @font.table(Constants::POST_TAG)
        @font.table(Constants::OS2_TAG)

        # Version (2 bytes at offset 0)
        header << [PFM_VERSION].pack("v")

        # dfSize (4 bytes at offset 2) - placeholder, will update
        header << [0].pack("V")

        # Copyright (60 bytes at offset 6)
        copyright = extract_copyright[0, 59]
        header << [copyright.length].pack("C")
        header << copyright.ljust(59, "\0")

        # dfType (2 bytes at offset 66) - 0 for Type 1
        header << [0].pack("v")

        # dfPoints (2 bytes at offset 68) - Use units_per_em / 2 as approximation
        points = head&.units_per_em ? head.units_per_em / 2 : 500
        header << [points].pack("v")

        # dfVertRes (2 bytes at offset 70)
        header << [300].pack("v")

        # dfHorizRes (2 bytes at offset 72)
        header << [300].pack("v")

        # dfAscent (2 bytes at offset 74)
        ascent = hhea&.ascent || @metrics.ascent || 1000
        header << [clamp_to_u16(ascent)].pack("v")

        # dfInternalLeading (2 bytes at offset 76)
        internal_leading = hhea&.line_gap || 0
        header << [clamp_to_u16(internal_leading)].pack("v")

        # dfExternalLeading (2 bytes at offset 78)
        header << [0].pack("v")

        # dfItalic (1 byte at offset 80)
        italic = (post&.italic_angle || 0).zero? ? 0 : 1
        header << [italic].pack("C")

        # dfUnderline (1 byte at offset 81)
        header << [1].pack("C")

        # dfStrikeOut (1 byte at offset 82)
        header << [0].pack("C")

        # dfWeight (2 bytes at offset 83)
        weight = extract_weight_value
        header << [weight].pack("v")

        # dfCharSet (1 byte at offset 85)
        header << [DEFAULT_CHARSET].pack("C")

        # dfPixWidth (2 bytes at offset 86)
        header << [0].pack("v")

        # dfPixHeight (2 bytes at offset 88)
        header << [0].pack("v")

        # dfPitchAndFamily (1 byte at offset 90)
        pitch_and_family = pitch_and_family_value
        header << [pitch_and_family].pack("C")

        # dfAverageWidth (2 bytes at offset 91)
        avg_width = calculate_average_width(char_widths)
        header << [clamp_to_u16(avg_width)].pack("v")

        # dfMaxWidth (2 bytes at offset 93)
        max_width = char_widths.values.max || 1000
        header << [clamp_to_u16(max_width)].pack("v")

        # dfFirstChar (1 byte at offset 95)
        first_char = char_widths.keys.min || 0
        header << [clamp_to_u8(first_char)].pack("C")

        # dfLastChar (1 byte at offset 96)
        last_char = char_widths.keys.max || 255
        header << [clamp_to_u8(last_char)].pack("C")

        # dfDefaultChar (1 byte at offset 97)
        header << [32].pack("C") # Space

        # dfBreakChar (1 byte at offset 98)
        header << [32].pack("C") # Space

        # dfWidthBytes (2 bytes at offset 99)
        width_bytes = ((char_widths.keys.max || 255) + 1) * 2
        header << [width_bytes].pack("v")

        # dfDevice (4 bytes at offset 101)
        header << [0].pack("V")

        # dfFace (4 bytes at offset 105) - placeholder
        header << [0].pack("V")

        # BitsPointer (4 bytes at offset 109)
        header << [0].pack("V")

        # BitsOffset (4 bytes at offset 113)
        header << [0].pack("V")

        # dfExtMetricsOffset (4 bytes at offset 117) - placeholder
        header << [0].pack("V")

        # dfExtentTable (4 bytes at offset 121) - placeholder
        header << [0].pack("V")

        # dfOriginTable (4 bytes at offset 125)
        header << [0].pack("V")

        # dfPairKernTable (4 bytes at offset 129) - placeholder
        header << [0].pack("V")

        # dfTrackKernTable (4 bytes at offset 133)
        header << [0].pack("V")

        # dfDriverInfo (4 bytes at offset 137) - placeholder
        header << [0].pack("V")

        # dfReserved (4 bytes at offset 141)
        header << [0].pack("V")

        # dfSignature (4 bytes at offset 145)
        header << [0x50414D4B].pack("V") # 'PAMK'

        # Pad to 256 bytes
        header << "\0" * (PFM_HEADER_SIZE - header.length)
      end

      # Build driver info section
      #
      # @return [String] Driver info binary data
      def build_driver_info
        info = String.new(encoding: "ASCII-8BIT")

        # Driver info structure (118 bytes)
        # Most fields are reserved/unused

        # Windows reserved
        info << [0].pack("V") * 22

        # Offset to Windows reserved fields (not used)
        info << [0].pack("V")

        # Offset to driver name (not used)
        info << [0].pack("V")

        # Fill to 118 bytes
        info << "\0" * (DRIVER_INFO_SIZE - info.length)

        info
      end

      # Build extended text metrics
      #
      # @return [String] Extended metrics binary data (48 bytes)
      def build_extended_metrics
        metrics = String.new(encoding: "ASCII-8BIT")

        os2 = @font.table(Constants::OS2_TAG)

        # etmSize (4 bytes)
        metrics << [0].pack("V")

        # etmPointSize (4 bytes)
        metrics << [0].pack("V")

        # etmOrientation (4 bytes)
        metrics << [0].pack("V")

        # etmMasterHeight (4 bytes)
        metrics << [0].pack("V")

        # etmMinScale (4 bytes)
        metrics << [0].pack("V")

        # etmMaxScale (4 bytes)
        metrics << [0].pack("V")

        # etmMasterUnits (4 bytes)
        metrics << [0].pack("V")

        # etmCapHeight (4 bytes)
        cap_height = if os2.respond_to?(:cap_height) && os2.cap_height
                       os2.cap_height
                     elsif os2.respond_to?(:s_typo_ascender) && os2.s_typo_ascender
                       os2.s_typo_ascender
                     else
                       @metrics.ascent || 1000
                     end
        metrics << [@scaler.scale(cap_height)].pack("V")

        # etmXHeight (4 bytes)
        x_height = if os2.respond_to?(:x_height) && os2.x_height&.positive?
                     os2.x_height
                   else
                     # Fallback: use roughly half the ascent for x-height
                     (@metrics.ascent / 2) || 500
                   end
        metrics << [@scaler.scale(x_height)].pack("V")

        # etmLowerCaseAscent (4 bytes)
        metrics << [0].pack("V")

        # etmLowerCaseDescent (4 bytes)
        metrics << [0].pack("V")

        # etmSlant (4 bytes)
        metrics << [0].pack("V")

        # etmSuperScript (4 bytes)
        metrics << [0].pack("V")

        # etmSubScript (4 bytes)
        metrics << [0].pack("V")

        # etmSuperScriptSize (4 bytes)
        metrics << [0].pack("V")

        # etmSubScriptSize (4 bytes)
        metrics << [0].pack("V")

        # etmUnderlineOffset (4 bytes)
        metrics << [0].pack("V")

        # etmUnderlineWidth (4 bytes)
        metrics << [0].pack("V")

        # etmDoubleUpperUnderlineOffset (4 bytes)
        metrics << [0].pack("V")

        # etmDoubleLowerUnderlineOffset (4 bytes)
        metrics << [0].pack("V")

        # etmDoubleUpperUnderlineWidth (4 bytes)
        metrics << [0].pack("V")

        # etmDoubleLowerUnderlineWidth (4 bytes)
        metrics << [0].pack("V")

        # etmStrikeOutOffset (4 bytes)
        metrics << [0].pack("V")

        # etmStrikeOutWidth (4 bytes)
        metrics << [0].pack("V")

        # etmKernPairs (4 bytes)
        metrics << [0].pack("V")

        # etmKernTracks (4 bytes)
        metrics << [0].pack("V")

        metrics
      end

      # Build width table
      #
      # @param char_widths [Hash] Character widths
      # @return [String] Width table binary data
      def build_width_table(char_widths)
        table = String.new(encoding: "ASCII-8BIT")

        # Number of extents (2 bytes)
        num_extents = (char_widths.keys.max || 255) + 1
        table << [num_extents].pack("v")

        # Character widths (2 bytes each)
        (0...num_extents).each do |i|
          width = char_widths[i] || 0
          table << [clamp_to_u16(width)].pack("v")
        end

        table
      end

      # Build kerning table
      #
      # @return [String] Kerning table binary data
      def build_kerning_table
        # For now, return empty kerning data
        # Full implementation would parse GPOS table
        String.new(encoding: "ASCII-8BIT")
      end

      # Update offsets in header data
      #
      # @param header [String] Header data (mutable via byteslice)
      def update_header_offsets(header, face_offset, ext_metrics_offset,
                                extent_table_offset, kern_table_offset,
                                driver_info_offset)
        # dfFace (4 bytes at offset 105)
        header[105, 4] = [face_offset].pack("V")

        # dfExtMetricsOffset (4 bytes at offset 117)
        header[117, 4] = [ext_metrics_offset].pack("V")

        # dfExtentTable (4 bytes at offset 121)
        header[121, 4] = [extent_table_offset].pack("V")

        # dfPairKernTable (4 bytes at offset 129)
        header[129, 4] = [kern_table_offset].pack("V")

        # dfDriverInfo (4 bytes at offset 137)
        header[137, 4] = [driver_info_offset].pack("V")

        # Update dfSize (4 bytes at offset 2)
        total_size = face_offset + driver_info_offset + DRIVER_INFO_SIZE
        header[2, 4] = [total_size].pack("V")
      end

      # Extract copyright notice
      #
      # @return [String] Copyright notice
      def extract_copyright
        name_table = @font.table(Constants::NAME_TAG)
        return "" unless name_table

        if name_table.respond_to?(:copyright)
          name_table.copyright(1) || name_table.copyright(3) || ""
        else
          ""
        end
      end

      # Extract face name from font
      #
      # @return [String] Face name
      def extract_face_name
        name_table = @font.table(Constants::NAME_TAG)
        return "" unless name_table

        # Try full font name first, then font family, then postscript name
        face_name = if name_table.respond_to?(:full_font_name)
                      name_table.full_font_name(1) || name_table.full_font_name(3) || ""
                    elsif name_table.respond_to?(:font_family)
                      name_table.font_family(1) || name_table.font_family(3) || ""
                    elsif name_table.respond_to?(:postscript_name)
                      name_table.postscript_name(1) || name_table.postscript_name(3) || ""
                    else
                      @font.post_script_name || ""
                    end

        face_name.to_s
      end

      # Extract weight value (100-900)
      #
      # @return [Integer] Weight value
      def extract_weight_value
        os2 = @font.table(Constants::OS2_TAG)
        return 400 unless os2

        weight_class = if os2.respond_to?(:us_weight_class)
                         os2.us_weight_class
                       elsif os2.respond_to?(:weight_class)
                         os2.weight_class
                       end
        return 400 unless weight_class

        # Map OS/2 weight class to PFM weight
        case weight_class
        when 100..200 then 100
        when 300 then 300
        when 400 then 400
        when 500 then 500
        when 600 then 600
        when 700 then 700
        when 800 then 800
        when 900 then 900
        else 400
        end
      end

      # Calculate pitch and family byte value
      #
      # @return [Integer] Pitch and family byte
      def pitch_and_family_value
        post = @font.table(Constants::POST_TAG)
        is_fixed = post.respond_to?(:is_fixed_pitch) ? post.is_fixed_pitch : false

        pitch = is_fixed ? FIXED_PITCH : VARIABLE_PITCH

        # Use Modern as default family
        family = FAMILY_MODERN

        pitch | family
      end

      # Calculate average character width
      #
      # @param char_widths [Hash] Character widths
      # @return [Integer] Average width
      def calculate_average_width(char_widths)
        return 0 if char_widths.empty?

        widths = char_widths.values
        sum = widths.sum
        sum / widths.length
      end

      # Clamp value to 8-bit unsigned range
      #
      # @param value [Integer] Value to clamp
      # @return [Integer] Clamped value
      def clamp_to_u8(value)
        [[0, value].max, 255].min
      end

      # Clamp value to 16-bit unsigned range
      #
      # @param value [Integer] Value to clamp
      # @return [Integer] Clamped value
      def clamp_to_u16(value)
        [[0, value].max, 65535].min
      end
    end
  end
end
