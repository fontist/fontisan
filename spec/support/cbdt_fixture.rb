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
    # Layouts are constructed via the BinData table models in
    # `Fontisan::Tables::*` so this fixture stays in sync with the
    # model definitions and cannot drift into invalid binary. Tables
    # without a BinData model that the loader needs to read (head, hhea,
    # OS/2, name, post) use minimal hand-rolled bytes that match the
    # OpenType spec; a self-test in
    # `spec/support/cbdt_fixture_spec.rb` round-trips the built font
    # through every model to catch any layout drift.
    module CbdtFixture
      # Image format 17: smallGlyphMetrics (5 bytes) + PNG data
      IMAGE_FORMAT_SMALL_PNG = 17
      # IndexSubTable format 1: variable-size, uint32 offset array
      INDEX_FORMAT_VAR_U32 = 1

      # Pixels-per-em for the single strike this fixture emits.
      PPEM = 16
      # Bit depth for the single strike (32-bit RGBA PNG).
      BIT_DEPTH = 32

      # @param codepoints [Array<Integer>] codepoints the fixture covers.
      #   One placeholder glyph is created per codepoint (GID 1..N).
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
          "head" => head_table,
          "hhea" => hhea_table(glyph_count),
          "maxp" => maxp_table(glyph_count),
          "OS/2" => os2_table,
          "name" => name_table,
          "post" => post_table,
          "hmtx" => hmtx_table(glyph_count),
          "cmap" => cmap_table(codepoints),
          "CBDT" => cbdt_table(codepoints),
          "CBLC" => cblc_table(codepoints),
        }
      end

      # @return [Integer] 0x00010000 (TrueType sfnt version)
      def self.sfnt_version
        0x00010000
      end

      # ---- Table builders ------------------------------------------------

      def self.head_table
        Tables::Head.new(
          version_raw: 0x00010000,
          font_revision_raw: 0x00005000,
          checksum_adjustment: 0,
          magic_number: 0x5F0F3CF5,
          flags: 0x000B,
          units_per_em: 1000,
          created_raw: 0,
          modified_raw: 0,
          x_min: 0, y_min: 0, x_max: 0, y_max: 0,
          mac_style: 0,
          lowest_rec_ppem: 8,
          font_direction_hint: 2,
          index_to_loc_format: 0,
          glyph_data_format: 0,
        ).to_binary_s
      end

      def self.hhea_table(num_glyphs)
        Tables::Hhea.new(
          version_raw: 0x00010000,
          ascent: 800,
          descent: -200,
          line_gap: 0,
          advance_width_max: 1000,
          min_left_side_bearing: 0,
          min_right_side_bearing: 0,
          x_max_extent: 1000,
          caret_slope_rise: 1,
          caret_slope_run: 0,
          caret_offset: 0,
          metric_data_format: 0,
          number_of_h_metrics: num_glyphs,
        ).to_binary_s
      end

      def self.maxp_table(num_glyphs)
        # Version 0.5 (CFF-style, 6 bytes) — sufficient for non-TT fonts.
        Tables::Maxp.new(version_raw: Tables::Maxp::VERSION_0_5,
                         num_glyphs: num_glyphs).to_binary_s
      end

      def self.os2_table
        # OS/2 v4.0. Only fields the loader actually reads are populated;
        # the rest are zeroed. Layout matches the spec byte-for-byte.
        # 13 uint16 + 10 uint8 (panose) + 4 uint32 + a4 + 8 uint16 +
        # 2 uint32 + 4 uint16.
        [
          0x0004,   # version 4
          1000,     # xAvgCharWidth
          400,      # usWeightClass (regular)
          5,        # usWidthClass (medium)
          0,        # fsType
          0, 0, 0, 0, 0, # ySubscript / ySuperscript (5 uint16)
          0, 0,     # yStrikeoutSize, yStrikeoutPosition
          0,        # sFamilyClass
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, # panose (10 bytes)
          0, 0, 0, 0, # ulUnicodeRange 1-4
          "TEST",   # achVendID
          0x0040,   # fsSelection (regular)
          0x0020,   # usFirstCharIndex
          0xFFFF,   # usLastCharIndex
          800,      # sTypoAscender
          -200,     # sTypoDescender
          0,        # sTypoLineGap
          800,      # usWinAscent
          200,      # usWinDescent
          0, 0,     # ulCodePageRange 1-2
          1000,     # sxHeight
          800,      # sCapHeight
          0,        # usDefaultChar
          0xFFFD,   # usBreakChar
          1 # usMaxContext
        ].pack("nnnnnnnnnnnnnC10NNNNa4nnnnnnnnNNnnnn")
      end

      def self.name_table
        # Two records: nameID 1 (family) and 6 (PostScript).
        records = [
          [3, 1, 0x0409, 1, "CBDT Test".encode("UTF-16BE").b],
          [3, 1, 0x0409, 6, "CBDTTest-Regular".encode("UTF-16BE").b],
        ]
        string_data = String.new(encoding: Encoding::BINARY)
        record_bytes = String.new(encoding: Encoding::BINARY)
        records.each do |pid, eid, lid, nid, encoded|
          offset = 6 + (records.size * 12) + string_data.bytesize
          record_bytes << [pid, eid, lid, nid, encoded.bytesize,
                           offset].pack("nnnnnn")
          string_data << encoded
        end
        header = [0, records.size, 6 + (records.size * 12)].pack("nnn")
        header + record_bytes + string_data
      end

      def self.post_table
        # Version 3.0 (no glyph names), zeroed metrics.
        Tables::Post.new(
          version_raw: 0x00030000,
          italic_angle_raw: 0,
          underline_position: -100,
          underline_thickness: 50,
          is_fixed_pitch: 0,
          min_mem_type42: 0,
          max_mem_type42: 0,
          min_mem_type1: 0,
          max_mem_type1: 0,
        ).to_binary_s
      end

      def self.hmtx_table(num_glyphs)
        # All glyphs: advance 1000, lsb 0.
        Array.new(num_glyphs) { [1000, 0] }.flatten.pack("n*")
      end

      def self.cmap_table(codepoints)
        # Format 4 (BMP) + Format 12 (full), platform 3 encodings 1 + 10.
        # One segment per codepoint + the mandatory 0xFFFF sentinel.
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
        # One segment per cp + the 0xFFFF sentinel. GID 0 is .notdef;
        # first codepoint gets GID 1.
        segments = cps.sort.map { |cp| cp..cp }
        segments << (0xFFFF..0xFFFF)
        seg_count = segments.size
        search_range = largest_pow2_le(seg_count) * 2
        search_range = 2 if search_range < 2
        entry_selector = Math.log2(search_range / 2).to_i
        range_shift = (seg_count * 2) - search_range

        end_codes = segments.map(&:end)
        start_codes = segments.map(&:begin)
        id_deltas = segments.each_with_index.map do |range, i|
          if range.begin == 0xFFFF
            1 # sentinel: 0xFFFF + 1 wraps to gid 0
          else
            ((i + 1) - range.begin) & 0xFFFF
          end
        end

        body = String.new(encoding: Encoding::BINARY)
        body << [seg_count * 2, search_range, entry_selector,
                 range_shift].pack("nnnn")
        body << end_codes.pack("n*")
        body << [0].pack("n") # reservedPad
        body << start_codes.pack("n*")
        body << id_deltas.pack("n*")
        body << Array.new(seg_count, 0).pack("n*") # idRangeOffset
        14 + body.bytesize # 14 = format(2)+length(2)+language(2)+header(8)... wait

        # Format 4 subtable header: format u16, length u16, language u16,
        # then segCountX2, searchRange, entrySelector, rangeShift.
        # `body` already includes those 4 seg header fields above. The 14
        # is format+length+language (6 bytes) + the 4 seg header fields
        # are in body. Let me recompute: body includes segCountX2 onward,
        # which is 8 bytes of header. Add 6 for format/length/language.
        length = 6 + body.bytesize
        [4, length, 0].pack("nnn") + body
      end

      def self.format12_subtable(cps)
        segments = cps.sort.map { |cp| cp..cp }
        body = String.new(encoding: Encoding::BINARY)
        segments.each_with_index do |range, i|
          body << [range.begin, range.end, i + 1].pack("NNN")
        end
        length = 16 + body.bytesize # 16-byte format-12 header
        [12, 0].pack("nn") + [length, 0, segments.size].pack("NNN") + body
      end

      def self.largest_pow2_le(n)
        return 0 if n <= 0

        1 << (n.bit_length - 1)
      end

      # ---- CBDT/CBLC (built via the BinData models) ---------------------

      def self.cbdt_table(codepoints)
        # CBDT v3.0: 4-byte header + one format-17 bitmap block per
        # placeholder glyph. Format 17 = smallGlyphMetrics (5 bytes) +
        # PNG data. The PNG payload is a single placeholder byte; the
        # Stitcher propagates raw bytes without decoding them.
        header = [3, 0].pack("nn") # majorVersion=3, minorVersion=0

        body = String.new(encoding: Encoding::BINARY)
        codepoints.each do |_cp|
          # smallGlyphMetrics: height u8, width u8, bearingX i8,
          # bearingY i8, advance i8 = 5 bytes total.
          body << [10, 10, 0, 0, 10].pack("CCCcc")
          body << "\xFF".b # 1 byte of placeholder "PNG" data
        end

        Tables::Cbdt.read(header + body).to_binary_s
      end

      # Per-glyph byte length of one CBDT format-17 block: 5-byte
      # smallGlyphMetrics + 1-byte placeholder PNG payload. Used to
      # build a realistic format-1 IndexSubTable offset array.
      CBDT_BLOCK_SIZE = 6

      def self.cblc_table(codepoints)
        first_gid = 1
        last_gid = codepoints.size
        glyph_count = last_gid - first_gid + 1

        # IST sits after header(8) + BitmapSize(48) + ISTA(8) = 64.
        ista_offset = 8 + 48
        ist_offset = ista_offset + 8

        # IndexSubTable format 1: 8-byte header + uint32 offsetArray[N+1].
        # Each glyph's bitmap block is CBDT_BLOCK_SIZE bytes, laid out
        # back-to-back starting at the CBDT body (offset 4 past the CBDT
        # header). offsetArray[i] = i * CBDT_BLOCK_SIZE (relative to
        # imageDataOffset); offsetArray[N+1] marks the end.
        offset_array = Array.new(glyph_count + 1) { |i| i * CBDT_BLOCK_SIZE }
        ist_bytes = [INDEX_FORMAT_VAR_U32, IMAGE_FORMAT_SMALL_PNG,
                     4].pack("nnN") + offset_array.pack("N*")

        # ISTA entry: u16 first, u16 last, u32 additionalOffset (relative
        # to ista_offset).
        ista_entry = Tables::CblcIndexSubTableArrayEntry.new(
          first_glyph_index: first_gid,
          last_glyph_index: last_gid,
          additional_offset_to_index_subtable: ist_offset - ista_offset,
        ).to_binary_s

        bitmap_size = Tables::CblcBitmapSize.new(
          index_subtable_array_offset: ista_offset,
          index_tables_size: ista_entry.bytesize + ist_bytes.bytesize,
          number_of_index_subtables: 1,
          color_ref: 0,
          hori: sbit_line_metrics,
          vert: sbit_line_metrics,
          start_glyph_index: first_gid,
          end_glyph_index: last_gid,
          ppem_x: PPEM,
          ppem_y: PPEM,
          bit_depth: BIT_DEPTH,
          flags: 2,
        )

        # CBLC header: version uint32 + numSizes uint32.
        header = [Tables::Cblc::VERSION_3_0, 1].pack("NN")
        header + bitmap_size.to_binary_s + ista_entry + ist_bytes
      end

      def self.sbit_line_metrics
        Tables::CblcSbitLineMetrics.new(
          ascender: 1,
          descender: 0,
          width_max: 1,
          caret_slope_numerator: 0,
          caret_slope_denominator: 1,
          caret_offset: 0,
          min_origin_sb: 0,
          min_advance_sb: 0,
          max_before_bl: 0,
          min_after_bl: 0,
          pad1: 0,
          pad2: 0,
        )
      end
    end
  end
end
