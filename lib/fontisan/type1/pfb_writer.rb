# frozen_string_literal: true

module Fontisan
  module Type1
    # Assembles the canonical Adobe Type 1 PFB from its parts: the clear-text
    # header, the eexec-encrypted private dictionary and CharStrings, and the
    # clear-text trailer. The layout mirrors what fontTools and t1utils emit
    # (the vocabulary our own {PFBParser} and {CharStrings} read), and every
    # encryption step is deterministic, so conversions are reproducible
    # byte for byte.
    #
    # @example Assemble a PFB
    #   pfb = Type1::PFBWriter.new(
    #     psname: "TestT1-Regular",
    #     bbox: [50, 0, 668, 750],
    #     fontinfo: { version: "1.0", FullName: "Test T1" },
    #     private_entries: { "BlueValues" => [0, 0], "password" => 5839 },
    #     charstrings: { ".notdef" => plain_bytes },
    #   ).write
    class PFBWriter
      # PFB chunk markers (Constants carries the reader's names).
      ASCII_SEGMENT = 0x01
      BINARY_SEGMENT = 0x02
      END_SEGMENT = 0x03
      PFB_MARKER = 0x80

      # The number of zero bytes that follow the eexec data.
      TRAILER_ZEROS = 512

      # @param psname [String] PostScript name
      # @param version [String] Font version string
      # @param fontinfo [Hash<Symbol, Object>] FontInfo entries
      #   (:version, :Notice, :Copyright, :FullName, :FamilyName, :Weight,
      #   :ItalicAngle, :isFixedPitch)
      # @param bbox [Array<Numeric>] FontBBox (4 numbers)
      # @param charstrings [Hash<String, String>] glyph name => PLAIN
      #   (unencrypted) Type 1 CharString bytes
      # @param private_entries [Hash<String, Object>] Private dictionary
      #   entries written in order ("/BlueValues" => [...], ...)
      def initialize(psname:, charstrings:, version: "1.0", fontinfo: {},
                     bbox: [0, 0, 0, 0], private_entries: {})
        @psname = psname
        @version = version
        @fontinfo = fontinfo
        @bbox = bbox
        @charstrings = charstrings
        @private_entries = private_entries
      end

      # @return [String] the PFB bytes
      def write
        [
          segment(ASCII_SEGMENT, clear_text),
          segment(BINARY_SEGMENT, Decryptor.eexec_encrypt(encrypted_payload)),
          segment(ASCII_SEGMENT, trailer),
          segment(END_SEGMENT, ""),
        ].join
      end

      private

      def segment(marker, data)
        [PFB_MARKER, marker, data.bytesize].pack("CCV") + data.b
      end

      # The clear-text header, ending at the eexec handoff.
      def clear_text
        <<~CLEAR
          %!PS-AdobeFont-1.0: #{@psname} #{@version}
          %%BeginResource: font #{@psname}
          12 dict dup begin
          /FontType 1 def
          /FontName /#{@psname} def
          /FontInfo #{fontinfo_count} dict dup begin
          #{fontinfo_text}end def
          /PaintType 0 def
          /FontMatrix [0.001 0 0 0.001 0 0] def
          /Encoding 256 array
          0 1 255 {1 index exch /.notdef put} for
          def
          /FontBBox {#{@bbox.join(' ')}} def
          end
          currentfile eexec
        CLEAR
      end

      def fontinfo_count
        keys = %i[version Notice Copyright FullName FamilyName Weight
                  ItalicAngle isFixedPitch UnderlinePosition UnderlineThickness
                  FSType]
        keys.count { |k| @fontinfo.key?(k) }
      end

      def fontinfo_text
        @fontinfo.filter_map do |key, value|
          next unless key

          case key
          when :ItalicAngle, :UnderlinePosition, :UnderlineThickness
            "/#{key} #{format('%<v>.6f', v: value)} def\n"
          when :isFixedPitch, :FSType
            "/#{key} #{value} def\n"
          else
            "/#{key} (#{value}) def\n"
          end
        end.join
      end

      # The eexec-encrypted body: private dictionary, then CharStrings.
      def encrypted_payload
        <<~BODY
          dup /Private
          8 dict dup begin
          /-| {string currentfile exch readstring pop} def
          /|- {def} def
          /| {put} def
          #{private_text}end
          /CharStrings
          #{@charstrings.size} dict dup begin
          #{charstrings_text}end put
          end
          dup /FontName get exch definefont pop
          mark
          currentfile closefile
        BODY
      end

      def private_text
        @private_entries.filter_map do |key, value|
          case value
          when Array then "/#{key} [#{value.join(' ')}] def\n"
          when true, false then "/#{key} #{value} def\n"
          else "/#{key} #{value} def\n"
          end
        end.join
      end

      def charstrings_text
        @charstrings.filter_map do |name, plain|
          encrypted = Decryptor.charstring_encrypt(plain)
          next if encrypted.empty?

          "/#{name} #{encrypted.bytesize} -| #{encrypted} |-\n"
        end.join
      end

      def trailer
        zeros = ("0" * 64) << "\n"
        "#{zeros * (TRAILER_ZEROS / 64)}cleartomark\n%%EndResource\n%%EOF\n"
      end
    end
  end
end
