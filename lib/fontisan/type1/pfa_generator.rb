# frozen_string_literal: true

require_relative "pfb_generator"

module Fontisan
  module Type1
    # PFA (Printer Font ASCII) Generator
    #
    # [`PFAGenerator`](lib/fontisan/type1/pfa_generator.rb) generates Type 1 PFA files
    # from TrueType fonts.
    #
    # PFA files are ASCII-encoded Type 1 fonts used by Unix systems.
    # They are the same as PFB files but with binary data hex-encoded.
    #
    # @example Generate PFA from TTF
    #   font = Fontisan::FontLoader.load("font.ttf")
    #   pfa_data = Fontisan::Type1::PFAGenerator.generate(font)
    #   File.write("font.pfa", pfa_data)
    #
    # @example Generate PFA with custom options
    #   options = { upm_scale: 1000, format: :pfa }
    #   pfa_data = Fontisan::Type1::PFAGenerator.generate(font, options)
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5178.Type1.pdf
    class PFAGenerator
      # Hex line length for ASCII encoding
      HEX_LINE_LENGTH = 64

      # Generate PFA from TTF font
      #
      # @param font [Fontisan::Font] Source TTF font
      # @param options [Hash] Generation options
      # @option options [Integer, :native] :upm_scale Target UPM (default: 1000)
      # @option options [Class] :encoding Encoding class (default: Encodings::AdobeStandard)
      # @option options [Boolean] :convert_curves Convert quadratic to cubic (default: true)
      # @return [String] PFA file content (ASCII text)
      def self.generate(font, options = {})
        new(font, options).generate
      end

      def initialize(font, options = {})
        @font = font
        @options = options
        @metrics = MetricsCalculator.new(font)

        # Set up scaler
        upm_scale = options[:upm_scale] || 1000
        @scaler = if upm_scale == :native
                    UPMScaler.native(font)
                  else
                    UPMScaler.new(font, target_upm: upm_scale)
                  end

        # Set up encoding
        @encoding = options[:encoding] || Encodings::AdobeStandard

        # Set up converter options
        @convert_curves = options.fetch(:convert_curves, true)
      end

      # Generate PFA file content
      #
      # @return [String] PFA ASCII content
      def generate
        lines = []

        # Header (ASCII section 1)
        lines << build_pfa_header
        lines << build_font_dict
        lines << build_private_dict
        lines << ""
        lines << "currentdict end"
        lines << "dup /FontName get exch definefont pop"
        lines << ""

        # Binary section (hex-encoded)
        lines << "%--Data to be hex-encoded:"
        hex_data = build_hex_encoded_charstrings
        lines.concat(hex_data)
        lines << ""

        # Trailer
        lines << build_pfa_trailer

        lines.join("\n")
      end

      private

      # Build PFA header
      #
      # @return [String] PFA header comment
      def build_pfa_header
        format("%%!PS-AdobeFont-1.0: %s 1.0\n", @font.post_script_name)
      end

      # Build font dictionary
      #
      # @return [String] Font dictionary in PostScript
      def build_font_dict
        dict = []
        dict << "25 dict begin"

        # Font type
        dict << "/FontType 1 def"
        dict << "/FontMatrix [0.001 0 0 0.001 0 0] def"

        # Font info
        name_table = @font.table(Constants::NAME_TAG)
        if name_table
          font_name = name_table.english_name(Tables::Name::POSTSCRIPT_NAME) || @font.post_script_name
          dict << "/FontName /#{font_name} def"
        end

        # Bounding box
        head = @font.table(Constants::HEAD_TAG)
        if head
          bbox = [
            @scaler.scale(head.x_min || 0),
            @scaler.scale(head.y_min || 0),
            @scaler.scale(head.x_max || 1000),
            @scaler.scale(head.y_max || 1000),
          ]
          dict << "/FontBBox {#{bbox.join(' ')}} def"
        end

        # Paint type
        dict << "/PaintType 0 def"

        # Encoding
        if @encoding == Encodings::AdobeStandard
          dict << "/Encoding StandardEncoding def"
        elsif @encoding == Encodings::ISOLatin1
          dict << "/Encoding ISOLatin1Encoding def"
        end

        # Font info
        if name_table
          if name_table.respond_to?(:version_string)
            version = name_table.version_string(1) || name_table.version_string(3)
            dict << "/Version (#{version}) def" if version
          end

          if name_table.respond_to?(:copyright)
            copyright = name_table.copyright(1) || name_table.copyright(3)
            dict << "/Notice (#{copyright}) def" if copyright
          end
        end

        dict << "currentdict end"
        dict << "begin"

        dict.join("\n")
      end

      # Build Private dictionary
      #
      # @return [String] Private dictionary in PostScript
      def build_private_dict
        dict = []
        dict << "/Private 15 dict begin"

        # Blue values (for hinting)
        # These are typically derived from the font's alignment zones
        os2 = @font.table(Constants::OS2_TAG)
        if os2.respond_to?(:typo_ascender) && os2.typo_ascender
          blue_values = [
            @scaler.scale(os2.typo_descender || -200),
            @scaler.scale(os2.typo_descender || -200) + 20,
            @scaler.scale(os2.typo_ascender),
            @scaler.scale(os2.typo_ascender) + 10,
          ]
          dict << "/BlueValues {#{blue_values.join(' ')}} def"
        else
          dict << "/BlueValues [-20 0 500 510] def"
        end

        dict << "/BlueScale 0.039625 def"
        dict << "/BlueShift 7 def"
        dict << "/BlueFuzz 1 def"

        # Stem snap hints
        if os2.respond_to?(:weight_class) && os2.weight_class
          stem_width = @scaler.scale([100, 80,
                                      90][os2.weight_class / 100] || 80)
          dict << "/StemSnapH [#{stem_width}] def"
          dict << "/StemSnapV [#{stem_width}] def"
        end

        # Force bold flag
        if os2.respond_to?(:weight_class) && os2.weight_class && os2.weight_class >= 700
          dict << "/ForceBold true def"
        else
          dict << "/ForceBold false def"
        end

        # Language group
        dict << "/LanguageGroup 0 def"

        # Unique ID (random)
        dict << "/UniqueID #{rand(1000000..9999999)} def"

        # Subrs (empty for now)
        dict << "/Subrs 0 array def"

        dict << "private dict begin"
        dict << "end"

        dict.join("\n")
      end

      # Build hex-encoded CharStrings section
      #
      # @return [Array<String>] Array of hex-encoded lines
      def build_hex_encoded_charstrings
        # Generate CharStrings
        charstrings = if @convert_curves
                        TTFToType1Converter.convert(@font, @scaler, @encoding)
                      else
                        generate_simple_charstrings
                      end

        # Combine all charstrings
        binary_data = charstrings.values.join

        # Convert to hex representation
        hex_lines = []

        # Start hex section marker
        hex_lines << "00" # Start binary data marker

        # Encode binary data as hex with line breaks
        hex_string = binary_data.bytes.map { |b| format("%02x", b) }.join

        # Split into lines of HEX_LINE_LENGTH characters
        hex_string.scan(/.{#{HEX_LINE_LENGTH}}/o) do |line|
          hex_lines << line
        end

        # End hex section marker
        hex_lines << "00" # End binary data marker

        hex_lines
      end

      # Generate simple CharStrings (without curve conversion)
      #
      # @return [Hash<Integer, String>] Glyph ID to CharString mapping
      def generate_simple_charstrings
        glyf_table = @font.table(Constants::GLYF_TAG)
        return {} unless glyf_table

        maxp = @font.table(Constants::MAXP_TAG)
        num_glyphs = maxp&.num_glyphs || 0

        charstrings = {}
        num_glyphs.times do |gid|
          charstrings[gid] = simple_charstring(glyf_table, gid)
        end

        charstrings
      end

      # Generate a simple CharString for a glyph
      #
      # @param glyf_table [Object] TTF glyf table
      # @param gid [Integer] Glyph ID
      # @return [String] Type 1 CharString data
      def simple_charstring(glyf_table, gid)
        glyph = glyf_table.glyph(gid)

        # Empty or compound glyph
        if glyph.nil? || glyph.contour_count.zero? || glyph.compound?
          # Return empty charstring (hsbw + endchar)
          return [0, 500, 14].pack("C*")
        end

        # For simple glyphs without curve conversion, generate minimal charstring
        lsb = @scaler.scale(glyph.left_side_bearing || 0)
        width = @scaler.scale(glyph.advance_width || 500)
        bytes = [13, lsb, width] # hsbw command (13)

        # Add simple line commands (very basic)
        if glyph.respond_to?(:points) && glyph.points && !glyph.points.empty?
          # Just draw lines between consecutive on-curve points
          prev_point = nil
          glyph.points.each do |point|
            next unless point.on_curve?

            if prev_point
              dx = @scaler.scale(point.x) - @scaler.scale(prev_point.x)
              dy = @scaler.scale(point.y) - @scaler.scale(prev_point.y)
              bytes << 5 # rlineto
              bytes.concat(encode_number(dx))
              bytes.concat(encode_number(dy))
            end
            prev_point = point
          end
        end

        bytes << 14 # endchar
        bytes.pack("C*")
      end

      # Encode a number for Type 1 CharString
      #
      # @param value [Integer] Number to encode
      # @return [Array<Integer>] Array of bytes
      def encode_number(value)
        if value >= -107 && value <= 107
          [value + 139]
        elsif value >= 108 && value <= 1131
          byte1 = ((value - 108) >> 8) + 247
          byte2 = (value - 108) & 0xFF
          [byte1, byte2]
        elsif value >= -1131 && value <= -108
          byte1 = ((-value - 108) >> 8) + 251
          byte2 = (-value - 108) & 0xFF
          [byte1, byte2]
        elsif value >= -32768 && value <= 32767
          [255, value & 0xFF, (value >> 8) & 0xFF]
        else
          bytes = []
          4.times do |i|
            bytes << ((value >> (8 * i)) & 0xFF)
          end
          [255] + bytes
        end
      end

      # Build PFA trailer
      #
      # @return [String] PFA trailer
      def build_pfa_trailer
        lines = []
        lines << "currentdict end"
        lines << "dup /FontName get exch definefont pop"
        lines << "% cleartomark"
        lines.join("\n")
      end
    end
  end
end
