# frozen_string_literal: true

require "fontisan"

module Fontisan
  module SpecHelpers
    # Minimal CBDT color-bitmap font builder for regression specs.
    #
    # Real CBDT fonts (NotoColorEmoji, TwemojiMozilla) are too large to
    # bundle just for one spec. This builder constructs a valid SFNT
    # with the table set Source#bitmap_mode recognises as :cbdt
    # (CBDT + CBLC, no glyf/CFF). The bitmap payload is intentionally
    # trivial — the Stitcher only propagates the raw table bytes, it
    # never decodes bitmap blocks during stitch.
    #
    # Output: a TTF file that +FontLoader.load+ can read, with:
    #   - .notdef + N placeholder glyphs (one per codepoint)
    #   - cmap mapping each codepoint to its placeholder GID
    #   - CBDT/CBLC tables (minimal valid headers + one tiny bitmap)
    module CbdtFixture
      HEAD_TAG = "head"
      CMAP_TAG = "cmap"
      CBDT_TAG = "CBDT"
      CBLC_TAG = "CBLC"
      MAXP_TAG = "maxp"

      # @param codepoints [Array<Integer>] codepoints the fixture covers.
      #   One placeholder glyph is created per codepoint.
      # @param path [String] where to write the TTF.
      # @return [void]
      def self.write_font(codepoints:, path:)
        tables = build_tables(codepoints)
        FontWriter.write_to_file(tables, path, sfnt_version: sfnt_version)
      end

      # Build the minimal table set. Exposed so specs can inspect the
      # individual tables without re-reading the file.
      # @param codepoints [Array<Integer>]
      # @return [Hash<String, String>]
      def self.build_tables(codepoints)
        glyph_count = codepoints.size + 1 # +1 for .notdef

        {
          HEAD_TAG => head_table,
          "hhea" => hhea_table(glyph_count),
          MAXP_TAG => maxp_table(glyph_count),
          "OS/2" => os2_table,
          "name" => name_table,
          "post" => post_table,
          "hmtx" => hmtx_table(glyph_count),
          CMAP_TAG => cmap_table(codepoints),
          CBDT_TAG => cbdt_table(codepoints),
          CBLC_TAG => cblc_table(codepoints),
        }
      end

      # @return [Integer] 0x00010000 (TrueType sfnt version)
      def self.sfnt_version
        0x00010000
      end

      # ---- Table builders ----

      def self.head_table
        [
          0x00010000,  # version 1.0
          0x00005000,  # fontRevision 0.5
          0x00000000,  # checksumAdjustment (filled by FontWriter)
          0x5F0F3CF5,  # magicNumber
          0x000B,      # flags (baseline at 0, left sidebearing at 0, etc.)
          1000,        # unitsPerEm
          0, 0,        # created, modified (LONGDATETIME, zeros ok for test)
          0, 0, 0, 0, 0, 0, 0, 0,  # xMin, yMin, xMax, yMax (all 0)
          0x0000,      # macStyle
          8,           # lowestRecPPEM
          2,           # fontDirectionHint
          0,           # indexToLocFormat (unused since no glyf/loca)
          0,           # glyphDataFormat
        ].pack("N N N N n n N N n n n n n n n n")
      end

      def self.hhea_table(num_glyphs)
        [
          0x00010000,  # version 1.0
          800,         # ascent
          -200,        # descent
          0,           # lineGap
          1000,        # advanceWidthMax
          0,           # minLeftSideBearing
          0,           # minRightSideBearing
          1000,        # xMaxExtent
          1, 0,        # caretSlopeRise, caretSlopeRun
          0,           # caretOffset
          0, 0, 0, 0,  # reserved * 4
          0,           # metricDataFormat
          num_glyphs,  # numberOfHMetrics
        ].pack("N n n n n n n n n n n n n n n n")
      end

      def self.maxp_table(num_glyphs)
        # Version 0.5 (minimal, sufficient for non-TT fonts)
        [0x00005000, num_glyphs].pack("N n")
      end

      def self.os2_table
        # Minimal OS/2 v4.0. Fields the loader actually reads (weight,
        # fsSelection, usWinAscent/Descent) are populated; the rest are
        # zeroed. Layout matches the OpenType spec byte-for-byte so
        # BinData parses it without raising.
        [
          0x0004,      # version 4
          1000,        # xAvgCharWidth
          400,         # usWeightClass (regular)
          5,           # usWidthClass (medium)
          0,           # fsType
          0, 0, 0, 0, 0, # ySubscript / ySuperscript (5 uint16 fields)
          0, 0,        # yStrikeoutSize, yStrikeoutPosition
          0,           # sFamilyClass
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, # panose (10 bytes)
          0, 0, 0, 0,  # ulUnicodeRange 1-4
          "TEST",      # achVendID
          0x0040,      # fsSelection (regular)
          0x0020,      # usFirstCharIndex
          0xFFFF,      # usLastCharIndex
          800,         # sTypoAscender
          -200,        # sTypoDescender
          0,           # sTypoLineGap
          800,         # usWinAscent
          200,         # usWinDescent
          0, 0,        # ulCodePageRange 1-2
          1000,        # sxHeight
          800,         # sCapHeight
          0,           # usDefaultChar
          0xFFFD,      # usBreakChar
          1,           # usMaxContext
        ].pack("n n n n n n n n n n n n n C10 N N N N a4 n n n n n n n n N N n n n n")
      end

      def self.name_table
        # Minimal name table with nameID 1 (family) and 6 (PostScript)
        records = [
          [3, 1, 0x0409, 1, "CBDT Test".encode("UTF-16BE").b],
          [3, 1, 0x0409, 6, "CBDTTest-Regular".encode("UTF-16BE").b],
        ]
        string_data = String.new(encoding: Encoding::BINARY)
        record_bytes = String.new(encoding: Encoding::BINARY)
        records.each do |pid, eid, lid, nid, encoded|
          offset = 6 + records.size * 12 + string_data.bytesize
          record_bytes << [pid, eid, lid, nid, encoded.bytesize, offset].pack("n n n n n n")
          string_data << encoded
        end
        header = [0, records.size, 6 + records.size * 12].pack("n n n")
        header + record_bytes + string_data
      end

      def self.post_table
        # Version 3.0 (no glyph names), all metrics zero
        [0x00030000, 0, -100, 50, 0, 0, 0, 0, 0].pack("N N n n N N N N N")
      end

      def self.hmtx_table(num_glyphs)
        # All glyphs: advance 1000, lsb 0
        Array.new(num_glyphs) { [1000, 0] }.flatten.pack("n" * (num_glyphs * 2))
      end

      def self.cmap_table(codepoints)
        # Format 4 (BMP) + Format 12 (full), platform 3 encodings 1 + 10.
        # One segment per codepoint (no contiguous runs needed for the test).
        bmp = codepoints.select { |cp| cp <= 0xFFFF }
        full = codepoints

        subtable_bmp = format4_subtable(bmp)
        subtable_full = format12_subtable(full)

        header_size = 4 + (2 * 8)
        offset_bmp = header_size
        offset_full = header_size + subtable_bmp.bytesize

        header = [0, 2].pack("nn")
        header << [3, 1, offset_bmp].pack("nnN")
        header << [3, 10, offset_full].pack("nnN")
        header + subtable_bmp + subtable_full
      end

      def self.format4_subtable(cps)
        # One segment per cp + sentinel. Minimal but valid.
        # GID 0 is .notdef; first codepoint gets GID 1.
        segments = cps.sort.map { |cp| cp..cp }
        segments << (0xFFFF..0xFFFF) # sentinel
        seg_count = segments.size
        search_range = largest_pow2_le(seg_count) * 2
        entry_selector = (Math.log([1, search_range / 2].max) / Math.log(2)).to_i
        range_shift = seg_count * 2 - search_range

        end_codes = segments.map(&:end)
        start_codes = segments.map(&:begin)
        id_deltas = segments.each_with_index.map do |range, i|
          start_cp = range.begin
          gid = i + 1 # .notdef is gid 0; first codepoint is gid 1
          if start_cp == 0xFFFF
            1
          else
            (gid - start_cp) & 0xFFFF
          end
        end

        body = String.new(encoding: Encoding::BINARY)
        body << [seg_count * 2, search_range, entry_selector, range_shift].pack("nnnn")
        body << end_codes.pack("n*")
        body << [0].pack("n")
        body << start_codes.pack("n*")
        body << id_deltas.pack("n*")
        body << Array.new(seg_count, 0).pack("n*")
        length = 14 + body.bytesize
        [4, length, 0].pack("nnn") + body
      end

      def self.format12_subtable(cps)
        segments = cps.sort.map { |cp| cp..cp }
        body = String.new(encoding: Encoding::BINARY)
        segments.each_with_index do |range, i|
          gid = i + 1 # .notdef is gid 0
          body << [range.begin, range.end, gid].pack("NNN")
        end
        length = 16 + body.bytesize
        [12, 0].pack("nn") + [length, 0, segments.size].pack("NNN") + body
      end

      def self.largest_pow2_le(n)
        return 0 if n <= 0

        1 << (n.bit_length - 1)
      end

      def self.cbdt_table(codepoints)
        # CBDT v2.0 header (4 bytes) + one bitmap block per glyph. The
        # bitmap payload is a placeholder byte; the Stitcher propagates
        # raw bytes without decoding them, so validity of the bitmap
        # data itself is irrelevant for the regression we exercise.
        header = [0x0002, 0x0000].pack("nn")

        body = String.new(encoding: Encoding::BINARY)
        codepoints.each_with_index do |_cp, _gid|
          body << [2].pack("C") # format = 2 (BigGlyphMetrics + byte data)
          body << [1, 1, 0, 0, 1000, 0, 0, 1000].pack("n n n n n n n n")
          body << [1].pack("N")
          body << "\xFF".b # 1 byte of bitmap data
        end

        header + body
      end

      def self.cblc_table(codepoints)
        # CBLC v2.0 header (4 bytes) + one bitmap size table per strike.
        # Minimal: one strike, format 1 index subtable, gid 0..N.
        header = [0x0002, 0x0000].pack("nn") # v2.0
        num_sizes = 1
        header << [num_sizes].pack("N")

        # bitmapSizeTable: 48 bytes
        # indexSubTableArray: one entry (firstgid, lastgid, indexSubTableOffset, indexSubTableSize)
        first_gid = 1
        last_gid = codepoints.size
        index_subtable_offset = 8 + (num_sizes * 48) + 8 # after header + size table + indexSubTableArray entry
        index_format = 1
        image_format = 2
        image_data_offset = 4 # offset into CBDT (after CBDT's 4-byte header)

        # indexSubTableArray entry: 12 bytes (startGlyphIndex, endGlyphIndex, indexSubTableOffset, indexSubTableSize)
        index_array = [first_gid, last_gid, index_subtable_offset, 16].pack("N N N N")

        # indexSubTableHeader (format 1): indexFormat(2) + imageFormat(2) + imageDataOffset(4) + sbitOffsets[]
        index_subtable = [index_format, image_format, image_data_offset].pack("nnN")
        # sbitOffsets: one per glyph + 1 sentinel. Each is uint32 offset into CBDT.
        # Point each glyph to offset 4 (start of bitmap data in CBDT).
        (last_gid - first_gid + 2).times do
          index_subtable << [4].pack("N")
        end

        # bitmapSizeTable (48 bytes)
        size_table = [
          1, 1,                  # hori: ascender, descender (sbitLineMetrics)
          1, 1000, 0, 0,         # hori: widthMax, caretSlopeRise, caretSlopeRun
          1, 0, 0, 0,            # hori: caretOffset, minOriginSB, minAdvanceSB, maxBeforeBL
          0,                     # hori: minAfterBL
          1, 1,                  # vert: ascender, descender
          1, 1000, 0, 0,
          1, 0, 0, 0,
          0,                     # vert: minAfterBL
          0x0002,                # startGlyphIndex (placeholder, overwritten below)
          last_gid,              # endGlyphIndex
          1,                     # ppemX
          1,                     # ppemY
          0,                     # bitDepth
          2,                     # flags
        ].pack("n n n n n n n n n n n n n n n n n n n n n n n n n")

        header + size_table + index_array + index_subtable
      end
    end
  end
end
