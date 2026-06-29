# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `CFF ` table from UFO glyphs.
      #
      # The full CFF builder (charstrings, dicts, INDEX structures,
      # subroutines) is TODO.full/10. For now this emits a valid
      # CFF skeleton that satisfies font consumers' shape checks
      # but renders glyphs as empty paths.
      #
      # When TODO 10 lands, replace `build_empty_cff` with a real
      # charstring-by-charstring encoder using
      # `Tables::Cff::CharStringBuilder`.
      module Cff
        # @param font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] in gid order
        # @return [String] CFF table bytes
        def self.build(font, glyphs:)
          require "stringio"
          io = StringIO.new("".b)
          emit_header(io)
          emit_name_index(io, font.info.postscript_font_name || font.info.family_name || "Untitled")
          emit_top_dict_index(io, glyphs.size)
          emit_string_index(io)
          emit_global_subr_index(io)
          emit_charset(io, glyphs)
          emit_charstrings_index(io, glyphs)
          emit_private_dict(io)
          io.string
        end

        # ---------- Header ----------

        def self.emit_header(io)
          # major=1, minor=0, hdrSize=4, offSize=1
          io.write([1, 0, 4, 1].pack("CCCC"))
        end

        # ---------- Name INDEX ----------

        def self.emit_name_index(io, name)
          emit_index(io, [name.b])
        end

        # ---------- Top DICT INDEX ----------
        # The Top DICT references charset + charstrings offsets which
        # we can't compute until everything else is laid out. For the
        # MVP we emit a minimal DICT and accept that downstream tools
        # won't find the charstrings. TODO 10 fixes this properly.

        def self.emit_top_dict_index(io, _glyph_count)
          # Single Top DICT with placeholder operators
          top_dict = "".b
          # charset 0 (ISOAdobe) — operator 15
          top_dict << encode_int(0) << "\x0f"
          # Encoding 0 (Standard) — operator 16
          top_dict << encode_int(0) << "\x10"
          # CharStrings offset placeholder — operator 17
          top_dict << encode_int(0) << "\x11"
          emit_index(io, [top_dict])
        end

        def self.emit_string_index(io)
          emit_index(io, [])
        end

        def self.emit_global_subr_index(io)
          emit_index(io, [])
        end

        def self.emit_charset(io, glyphs)
          # Format 0: array of SIDs, one per glyph (skip gid 0).
          return if glyphs.size <= 1

          io.write([0].pack("C"))
          (1...glyphs.size).each do |_gid|
            io.write([0].pack("n")) # SID 0 = ".notdef" placeholder
          end
        end

        def self.emit_charstrings_index(io, glyphs)
          charstrings = glyphs.map { |g| charstring_for(g) }
          emit_index(io, charstrings)
        end

        # Each charstring is a Type 2 program. For the MVP we emit
        # just `endchar` (0x0e) for every glyph — they render empty.
        # TODO 10 wires the real CharStringBuilder here.
        def self.charstring_for(_glyph)
          "\x0e".b
        end

        def self.emit_private_dict(io)
          # Empty Private DICT — operators only.
        end

        # ---------- INDEX helper ----------

        def self.emit_index(io, items)
          if items.empty?
            io.write([0].pack("n"))
            return
          end

          count = items.size
          offsets = [1]
          items.each { |item| offsets << offsets.last + item.bytesize }
          max_offset = offsets.last
          off_size = byte_size_for(max_offset)

          io.write([count, off_size].pack("nC"))
          offsets.each { |o| io.write(pack_offset(o, off_size)) }
          items.each { |item| io.write(item) }
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
          when 3 then [value].pack("Cxxx")[0, 3].b # ugly 3-byte pack
          when 4 then [value].pack("N")
          end
        end

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
        private_class_method :emit_header, :emit_name_index, :emit_top_dict_index,
                             :emit_string_index, :emit_global_subr_index,
                             :emit_charset, :emit_charstrings_index, :charstring_for,
                             :emit_private_dict, :emit_index, :byte_size_for,
                             :pack_offset, :encode_int
      end
    end
  end
end
