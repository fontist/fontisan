# frozen_string_literal: true

require_relative "upm_scaler"
require_relative "ttf_to_type1_converter"
require_relative "../tables/name"

module Fontisan
  module Type1
    # PFB (Printer Font Binary) Generator
    #
    # [`PFBGenerator`](lib/fontisan/type1/pfb_generator.rb) generates Type 1 PFB files
    # from TrueType fonts.
    #
    # PFB files are segmented binary files used by Windows for Type 1 fonts.
    # They contain:
    # - ASCII segment: Font dictionary
    # - Binary segment: CharString data
    # - ASCII segment: Trailer
    #
    # @example Generate PFB from TTF
    #   font = Fontisan::FontLoader.load("font.ttf")
    #   pfb_data = Fontisan::Type1::PFBGenerator.generate(font)
    #   File.binwrite("font.pfb", pfb_data)
    #
    # @example Generate PFB with custom options
    #   options = { upm_scale: 1000, format: :pfb }
    #   pfb_data = Fontisan::Type1::PFBGenerator.generate(font, options)
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5178.Type1.pdf
    class PFBGenerator
      # PFB segment markers
      ASCII_SEGMENT = 0x01
      BINARY_SEGMENT = 0x02
      END_SEGMENT = 0x03

      # Header format string
      PFB_HEADER = "%%!PS-AdobeFont-1.0: %s 1.0\n"

      # Generate PFB from TTF font
      #
      # @param font [Fontisan::Font] Source TTF font
      # @param options [Hash] Generation options
      # @option options [Integer, :native] :upm_scale Target UPM (default: 1000)
      # @option options [Class] :encoding Encoding class (default: Encodings::AdobeStandard)
      # @option options [Boolean] :convert_curves Convert quadratic to cubic (default: true)
      # @return [String] PFB file content (binary)
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

      # Generate PFB file content
      #
      # @return [String] PFB binary content
      def generate
        # Build PFB segments
        ascii_segment1 = build_ascii_segment_1
        binary_segment = build_binary_segment
        ascii_segment2 = build_ascii_segment_2

        # Combine with segment headers
        [
          segment_header(ASCII_SEGMENT, ascii_segment1.bytesize),
          ascii_segment1,
          segment_header(BINARY_SEGMENT, binary_segment.bytesize),
          binary_segment,
          segment_header(ASCII_SEGMENT, ascii_segment2.bytesize),
          ascii_segment2,
          [END_SEGMENT, 0, 0, 0, 0, 0].pack("CV"),
        ].join
      end

      private

      # Build first ASCII segment (font dictionary)
      #
      # @return [String] ASCII font dictionary
      def build_ascii_segment_1
        lines = []
        lines << format(PFB_HEADER, @font.post_script_name)
        lines << build_font_dict
        lines << build_private_dict
        lines << build_charstrings_dict
        lines.join("\n")
      end

      # Build font dictionary
      #
      # @return [String] Font dictionary in PostScript
      def build_font_dict
        dict = []
        dict << "10 dict begin"
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

        dict << "currentdict end"
        dict << "dup /FontName get exch definefont pop"

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
        dict << "/BlueValues [-20 0 500 510] def"
        dict << "/BlueScale 0.039625 def"
        dict << "/BlueShift 7 def"
        dict << "/BlueFuzz 1 def"

        # Stem snap hints
        os2 = @font.table(Constants::OS2_TAG)
        if os2.respond_to?(:weight_class)
          stem_width = @scaler.scale([100, 80,
                                      90][os2.weight_class / 100] || 80)
          dict << "/StemSnapH [#{stem_width}] def"
          dict << "/StemSnapV [#{stem_width}] def"
        end

        # Force bold flag
        dict << if os2.respond_to?(:weight_class) && os2.weight_class && os2.weight_class >= 700
                  "/ForceBold true def"
                else
                  "/ForceBold false def"
                end

        # Language group
        dict << "/LanguageGroup 0 def"

        # Unique ID (random)
        dict << "/UniqueID #{rand(1000000..9999999)} def"

        dict << "currentdict end"
        dict << "dup /Private get"

        dict.join("\n")
      end

      # Build CharStrings dictionary
      #
      # @return [String] CharStrings dictionary reference
      def build_charstrings_dict
        # This is a placeholder - actual CharStrings are in the binary segment
        "/CharStrings #{@charstrings&.size || 0} dict dup begin\nend"
      end

      # Build binary segment (CharStrings)
      #
      # @return [String] Binary CharString data
      def build_binary_segment
        # Convert glyphs to Type 1 CharStrings
        charstrings = if @convert_curves
                        TTFToType1Converter.convert(@font, @scaler, @encoding)
                      else
                        # For simple curve conversion skip, generate minimal charstrings
                        generate_simple_charstrings
                      end

        # Encode charstrings to eexec format (encrypted)
        # For now, we'll use plain format (not encrypted)
        # TODO: Implement eexec encryption

        charstrings.values.join
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

        # For simple glyphs without curve conversion, generate line-based charstring
        # This is a simplified implementation
        lsb = @scaler.scale(glyph.left_side_bearing || 0)
        width = @scaler.scale(glyph.advance_width || 500)
        bytes = [0, lsb, width] # hsbw

        # Add lines between points (simplified)
        if glyph.respond_to?(:points) && glyph.points && !glyph.points.empty?
          glyph.points.each do |point|
            next unless point.on_curve?

            # This is very simplified - proper implementation would handle curves
          end
        end

        bytes << 14 # endchar
        bytes.pack("C*")
      end

      # Build second ASCII segment (trailer)
      #
      # @return [String] ASCII trailer
      def build_ascii_segment_2
        lines = []
        lines << "put" # Put the Private dictionary
        lines << "dup /FontName get exch definefont pop"
        lines << "% cleartomark"
        lines.join("\n")
      end

      # Create PFB segment header
      #
      # @param marker [Integer] Segment type marker
      # @param size [Integer] Segment data size
      # @return [String] 6-byte segment header
      def segment_header(marker, size)
        [marker, size].pack("CV")
      end
    end
  end
end
