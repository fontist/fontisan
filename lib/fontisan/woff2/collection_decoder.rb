# frozen_string_literal: true

require "stringio"

module Fontisan
  module Woff2
    # Decodes a WOFF2 font collection per spec section 4.2. This is the
    # decoder counterpart of {Woff2::CollectionEncoder}.
    #
    # Layout parsed:
    #   [WOFF2Header (48 bytes, flavor = 'ttcf')]
    #   [TableDirectory]              # one entry per unique table
    #   [CollectionDirectory]         # CollectionHeader + N CollectionFontEntry
    #   [CompressedFontData]          # single brotli stream of all tables
    #
    # Each CollectionFontEntry references tables in the TableDirectory via
    # indices. The decoder yields one reconstructed font per entry, with
    # glyf/loca reconstruction per spec section 5.1/5.3 applied.
    #
    # Reference: W3C WOFF2 spec, section 4.2.
    class CollectionDecoder
      TTC_FLAVOR = 0x74746366 # 'ttcf'

      # Parsed table directory entry: tag + raw bytes + transform state.
      TableEntry = Struct.new(:tag, :raw_bytes, :orig_length, :transform_length,
                              keyword_init: true)

      # Parsed CollectionFontEntry: per-font table indices + flavor.
      FontEntry = Struct.new(:flavor, :table_indices, keyword_init: true)

      # @param data [String] WOFF2 collection binary
      def initialize(data)
        @data = data.dup.force_encoding(Encoding::BINARY)
      end

      # Decode the WOFF2 collection, returning one Hash per font containing
      # the reconstructed table data ready to assemble into an SFNT.
      #
      # @return [Array<Hash{Symbol => Object}>] per-font:
      #   {flavor:, tables: {tag ⇒ bytes}}
      def decode
        validate_signature!
        validate_collection_flavor!

        table_entries, post_dir_pos = read_table_directory
        font_entries, post_coll_pos = read_collection_directory(post_dir_pos)
        decompressed = decompress_table_data(post_coll_pos)

        # Replace each table entry's raw_bytes by slicing from the
        # decompressed stream at its cumulative offset.
        cursor = 0
        table_entries.each do |e|
          len = e.transform_length || e.orig_length
          e.raw_bytes = decompressed[cursor, len]
          cursor += len
        end

        # For each font, gather its tables and reconstruct glyf/loca when
        # the glyf was transformed.
        font_entries.map do |fe|
          font_tables = {}
          fe.table_indices.each do |idx|
            entry = table_entries.fetch(idx)
            font_tables[entry.tag] = entry.raw_bytes
          end
          reconstruct_glyf_loca!(font_tables) if font_tables.key?("glyf")
          { flavor: fe.flavor, tables: font_tables }
        end
      end

      private

      def validate_signature!
        sig = @data[0, 4].unpack1("N")
        return if sig == Woff2Header::SIGNATURE

        raise InvalidFontError,
              "Invalid WOFF2 signature: 0x#{sig.to_s(16)}"
      end

      def validate_collection_flavor!
        flavor = @data[4, 4].unpack1("N")
        return if flavor == TTC_FLAVOR

        raise InvalidFontError,
              "WOFF2 file is not a collection (flavor 0x#{flavor.to_s(16)}; " \
              "expected 0x#{TTC_FLAVOR.to_s(16)} 'ttcf')"
      end

      def num_tables = @data[12, 2].unpack1("n")

      def total_compressed_size = @data[20, 4].unpack1("N")

      # Walk num_tables entries, returning the array of TableEntry and the
      # byte position immediately after the table directory.
      def read_table_directory
        entries = []
        pos = 48
        num_tables.times do
          entry, pos = read_one_directory_entry(pos)
          entries << entry
        end
        [entries, pos]
      end

      def read_one_directory_entry(pos)
        flags = @data.getbyte(pos)
        pos += 1
        tag_index = flags & 0x3F
        transform_version = (flags >> 6) & 0x03
        tag = if tag_index == 0x3F
                t = @data[pos, 4]
                pos += 4
                t
              else
                Directory::KNOWN_TAGS.fetch(tag_index)
              end
        orig_length, pos = read_uint_base128(pos)
        transform_length = nil
        is_glyf_loca = ["glyf", "loca"].include?(tag)
        is_transformed_hmtx = tag == "hmtx" && transform_version == 1
        if (is_glyf_loca && transform_version.zero?) || is_transformed_hmtx
          transform_length, pos = read_uint_base128(pos)
        end
        entry = TableEntry.new(tag:, raw_bytes: nil, orig_length:,
                               transform_length:)
        [entry, pos]
      end

      # Read CollectionHeader + N CollectionFontEntry records.
      def read_collection_directory(pos)
        version = @data[pos, 4].unpack1("N")
        pos += 4
        raise InvalidFontError, "Unsupported CollectionHeader version 0x#{version.to_s(16)}" unless version == 0x00010000

        num_fonts, pos = UInt255.decode_at(@data, pos)
        font_entries = Array.new(num_fonts) do
          num_tables_f, pos2 = UInt255.decode_at(@data, pos)
          pos = pos2
          flavor = @data[pos, 4].unpack1("N")
          pos += 4
          indices = Array.new(num_tables_f) do
            idx, pos2 = UInt255.decode_at(@data, pos)
            pos = pos2
            idx
          end
          FontEntry.new(flavor:, table_indices: indices)
        end
        [font_entries, pos]
      end

      def decompress_table_data(start_pos)
        compressed = @data[start_pos, total_compressed_size]
        Utilities::BrotliWrapper.decompress(compressed)
      end

      # Reconstruct glyf + loca per spec section 5.1/5.3 when glyf is in
      # transformed format. Replaces font_tables["glyf"] with reconstructed
      # bytes and adds font_tables["loca"].
      def reconstruct_glyf_loca!(font_tables)
        glyf_bytes = font_tables["glyf"]
        return unless glyf_bytes && glyf_bytes.bytesize >= 36

        num_glyphs = parse_num_glyphs(font_tables)
        index_format = parse_index_format(font_tables)
        return unless num_glyphs && index_format

        loca_format = index_format.zero? ? LocaFormat::SHORT : LocaFormat::LONG
        result = GlyfLocaReconstruct.new(
          transformed_glyf: glyf_bytes,
          num_glyphs:,
          loca_format:,
        ).reconstruct
        font_tables["glyf"] = result[:glyf]
        font_tables["loca"] = result[:loca]
      end

      def parse_num_glyphs(font_tables)
        maxp = font_tables["maxp"]
        return nil unless maxp && maxp.bytesize >= 6

        maxp[4, 2].unpack1("n")
      end

      def parse_index_format(font_tables)
        head = font_tables["head"]
        return nil unless head && head.bytesize >= 52

        head[50, 2].unpack1("n")
      end

      def read_uint_base128(pos)
        value = 0
        5.times do
          byte = @data.getbyte(pos)
          pos += 1
          if (byte & 0x80).zero?
            value = (value << 7) | byte
            return [value, pos]
          end
          value = (value << 7) | (byte & 0x7F)
        end
        raise InvalidFontError, "UIntBase128 sequence exceeds 5 bytes"
      end
    end
  end
end
