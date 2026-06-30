# frozen_string_literal: true

require "stringio"

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `CFF ` table from UFO glyphs.
      #
      # Pipeline:
      #   1. Convert each UFO glyph's contours to a Models::Outline
      #      (cubic Bezier commands).
      #   2. Encode each outline as a Type 2 charstring via the
      #      existing `Tables::Cff::CharStringBuilder`.
      #   3. Build the CFF structural INDEXes (Name, Top DICT, String,
      #      Global Subr, CharStrings) with correct offsets.
      #
      # The Top DICT references absolute offsets to the charset,
      # charstrings, and private dict. Those offsets depend on the
      # size of everything that comes before them — including the Top
      # DICT itself. We resolve the circular dependency with a
      # fixed-point iteration: build the Top DICT, compute offsets,
      # rebuild the Top DICT with the new offsets, repeat until it
      # converges (typically 2 iterations).
      module Cff
        # @param font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] in gid order
        # @return [String] CFF table bytes
        def self.build(font, glyphs:)
          name = font.info.postscript_font_name || font.info.family_name || "Untitled"
          charstrings = glyphs.map { |g| charstring_for(g) }
          private_dict = +""

          layout = compute_layout(name: name, glyphs: glyphs,
                                  charstrings: charstrings,
                                  private_dict: private_dict)

          assemble(layout: layout)
        end

        # ---------- charstring per-glyph ----------

        def self.charstring_for(glyph)
          return empty_charstring(glyph.width.to_i) if glyph.contours.empty?

          builder = Fontisan::Tables::Cff::CharStringBuilder.new
          builder.build(glyph.to_outline, width: glyph.width.to_i)
        rescue StandardError
          # Any failure (e.g., too-short contours, unsupported curve
          # combination): fall back to an empty charstring so the
          # INDEX stays valid.
          empty_charstring(glyph.width.to_i)
        end

        def self.empty_charstring(width)
          builder = Fontisan::Tables::Cff::CharStringBuilder.new
          builder.build_empty(width: width.zero? ? nil : width)
        end

        # ---------- layout ----------

        # Compute the byte offsets of every CFF structural section.
        # Iterates until the Top DICT's encoded size stabilizes.
        def self.compute_layout(name:, glyphs:, charstrings:, private_dict:)
          name_index = index_bytes([name.b])
          string_index = index_bytes([])
          global_subr_index = index_bytes([])
          charset = charset_bytes(glyphs)
          charstrings_index = index_bytes(charstrings)

          # First guess: Top DICT encoded with all-zero offsets.
          top_dict = top_dict_bytes(0, 0, 0, 0)
          top_dict_index = index_bytes([top_dict])

          charset_offset = 0
          charstrings_offset = 0
          private_offset = 0

          10.times do
            header_size = 4
            post_top_dict = header_size + name_index.bytesize +
              top_dict_index.bytesize + string_index.bytesize +
              global_subr_index.bytesize

            charset_offset = post_top_dict
            charstrings_offset = charset_offset + charset.bytesize
            private_offset = charstrings_offset + charstrings_index.bytesize

            new_top_dict = top_dict_bytes(
              charset_offset,
              charstrings_offset,
              private_dict.bytesize,
              private_offset,
            )
            new_top_dict_index = index_bytes([new_top_dict])

            if new_top_dict_index.bytesize == top_dict_index.bytesize
              # Converged. Use the freshly-encoded Top DICT so the
              # layout hash is self-consistent with the offsets.
              top_dict_index = new_top_dict_index
              break
            end

            top_dict_index = new_top_dict_index
          end

          {
            name_index: name_index,
            top_dict_index: top_dict_index,
            string_index: string_index,
            global_subr_index: global_subr_index,
            charset_offset: charset_offset,
            charstrings_offset: charstrings_offset,
            private_offset: private_offset,
            charset: charset,
            charstrings_index: charstrings_index,
            private_dict: private_dict,
          }
        end

        # ---------- byte emission ----------

        def self.assemble(layout:)
          io = StringIO.new("".b)

          io.write([1, 0, 4, 1].pack("CCCC")) # CFF header (v1.0, hdrSize=4, offSize=1)

          io.write(layout[:name_index])
          io.write(layout[:top_dict_index])
          io.write(layout[:string_index])
          io.write(layout[:global_subr_index])

          io.write(layout[:charset])
          io.write(layout[:charstrings_index])
          io.write(layout[:private_dict])

          io.string
        end

        # Top DICT bytes with the three standard offset operators.
        # Operators: charset(15), CharStrings(17), Private(18).
        # Encoding (operator 16) is implicit for OpenType fonts.
        def self.top_dict_bytes(charset_offset, charstrings_offset,
                                private_size, private_offset)
          bytes = +""
          bytes << encode_int(charset_offset) << "\x0f"     # charset
          bytes << encode_int(charstrings_offset) << "\x11" # CharStrings
          bytes << encode_int(private_size) << encode_int(private_offset) << "\x12" # Private
          bytes
        end

        # Format 0 charset: 1 format byte + (n-1) SIDs.
        # Gid 0 is implicit .notdef.
        def self.charset_bytes(glyphs)
          return +"" if glyphs.size <= 1

          bytes = +"\x00"
          (1...glyphs.size).each { |_| bytes << [0].pack("n") } # SID 0 placeholder
          bytes
        end

        # ---------- INDEX helpers ----------

        def self.index_bytes(items)
          io = StringIO.new("".b)
          if items.empty?
            io.write([0].pack("n"))
            return io.string
          end

          count = items.size
          offsets = [1]
          items.each { |item| offsets << offsets.last + item.bytesize }
          max_offset = offsets.last
          off_size = byte_size_for(max_offset)

          io.write([count, off_size].pack("nC"))
          offsets.each { |o| io.write(pack_offset(o, off_size)) }
          items.each { |item| io.write(item) }
          io.string
        end

        def self.byte_size_for(max_value)
          return 1 if max_value <= 0xFF
          return 2 if max_value <= 0xFFFF
          return 3 if max_value <= 0xFFFFFF

          4
        end

        def self.pack_offset(value, size)
          case size
          when 1 then [value].pack("C")
          when 2 then [value].pack("n")
          when 3
            [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].pack("CCC")
          when 4 then [value].pack("N")
          end
        end

        # CFF DICT integer encoding (CFF spec section 3.1).
        def self.encode_int(value)
          if value.between?(-107, 107)
            [value + 139].pack("C")
          elsif value.between?(108, 1131)
            v = value - 108
            [(v / 256) + 247, v % 256].pack("CC")
          elsif value.between?(-1131, -108)
            v = -value - 108
            [-(v / 256) - 247, v % 256].pack("CC")
          elsif value.between?(-32_768, 32_767)
            [28, value].pack("Cn")
          else
            [29, value].pack("CN")
          end
        end

        private_class_method :charstring_for, :empty_charstring,
                             :compute_layout, :assemble, :top_dict_bytes,
                             :charset_bytes, :index_bytes, :byte_size_for,
                             :pack_offset, :encode_int
      end
    end
  end
end
