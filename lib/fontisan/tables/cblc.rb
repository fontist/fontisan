# frozen_string_literal: true

module Fontisan
  module Tables
    # CBLC (Color Bitmap Location) table.
    #
    # CBLC indexes glyph IDs into CBDT byte offsets across one or more
    # bitmap strikes (each strike = a ppem + bit depth combination). For
    # each strike, a list of IndexSubTable records describes how to locate
    # the bitmap of each glyph in a contiguous glyph range.
    #
    # Layout:
    #   uint32 version                (0x00020000 or 0x00030000)
    #   uint32 num_sizes              (number of BitmapSize records)
    #   CblcBitmapSize[num_sizes]     (48 bytes each)
    #   IndexSubTableArray entries    (8 bytes each, per BitmapSize)
    #   IndexSubTable records         (variable, format-specific)
    #
    # This model parses the header + BitmapSize records via BinData, then
    # lazily walks the IndexSubTableArray / IndexSubTable structures on
    # demand so callers can iterate [(gid, strike) → CBDT location] pairs.
    #
    # Reference: OpenType CBLC specification.
    # https://learn.microsoft.com/en-us/typography/opentype/spec/cblc
    #
    # @example Enumerate every glyph's CBDT bitmap location
    #   cblc = Fontisan::Tables::Cblc.read(font.table_data["CBLC"])
    #   cblc.each_glyph_location do |loc|
    #     puts "gid=#{loc.glyph_id} cbdt_offset=#{loc.cbdt_offset}"
    #   end
    class Cblc < Binary::BaseRecord
      TAG = "CBLC"

      # CBLC v2.0 — original release
      VERSION_2_0 = 0x00020000
      # CBLC v3.0 — adds PNG image format support
      VERSION_3_0 = 0x00030000

      uint32 :version
      uint32 :num_sizes
      array :bitmap_sizes,
            type: Fontisan::Tables::CblcBitmapSize,
            initial_length: :num_sizes

      # Iterate every (glyph_id, strike) → CblcGlyphBitmapLocation pair
      # across all strikes. Each strike's IndexSubTables are walked in
      # turn so the caller sees every glyph's CBDT location exactly once
      # per strike.
      #
      # @yield [CblcGlyphBitmapLocation]
      # @return [Enumerator] if no block given
      def each_glyph_location(&block)
        return enum_for(:each_glyph_location) unless block

        index_sub_tables.each do |sub|
          sub.locations.each(&block)
        end
      end

      # All IndexSubTable records across every strike.
      #
      # @return [Array<CblcIndexSubTable>]
      def index_sub_tables
        @index_sub_tables ||= bitmap_sizes.flat_map { |s| sub_tables_for(s) }
      end

      # Locate a glyph's CBDT bitmap at a specific ppem.
      #
      # @param glyph_id [Integer] source glyph ID
      # @param ppem [Integer] strike ppem
      # @return [CblcGlyphBitmapLocation, nil]
      def bitmap_offset_for_gid(glyph_id, ppem)
        strike = bitmap_sizes.find do |s|
          s.ppem == ppem && s.includes_glyph?(glyph_id)
        end
        return nil unless strike

        sub_tables_for(strike).each do |sub|
          loc = sub.locations.find { |l| l.glyph_id == glyph_id }
          return loc if loc
        end
        nil
      end

      # Iterate every IndexSubTable in a single strike.
      #
      # @param strike [CblcBitmapSize]
      # @return [Array<CblcIndexSubTable>]
      def sub_tables_for(strike)
        return [] if strike.number_of_index_subtables.zero?

        array_offset = strike.index_subtable_array_offset
        entries = read_index_subtable_array(strike, array_offset)

        entries.map do |entry|
          absolute = array_offset + entry.additional_offset_to_index_subtable
          CblcIndexSubTable.parse(
            raw_data,
            index_subtable_offset: absolute,
            first_glyph_index: entry.first_glyph_index,
            last_glyph_index: entry.last_glyph_index,
          )
        end
      end

      # All available ppem sizes across every strike.
      #
      # @return [Array<Integer>]
      def ppem_sizes
        bitmap_sizes.map(&:ppem).uniq.sort
      end

      # Number of bitmap strikes.
      #
      # @return [Integer]
      def num_strikes
        num_sizes
      end

      # Strikes that cover a given glyph ID.
      #
      # @param glyph_id [Integer]
      # @return [Array<CblcBitmapSize>]
      def strikes_for_glyph(glyph_id)
        bitmap_sizes.select { |s| s.includes_glyph?(glyph_id) }
      end

      # Strikes that match a specific ppem.
      #
      # @param ppem [Integer]
      # @return [Array<CblcBitmapSize>]
      def strikes_for_ppem(ppem)
        bitmap_sizes.select { |s| s.ppem == ppem }
      end

      # All glyph IDs that have any bitmap across every strike.
      #
      # @return [Array<Integer>]
      def glyph_ids_with_bitmaps
        bitmap_sizes.flat_map { |s| s.glyph_range.to_a }.uniq.sort
      end

      # Whether the CBLC header is one fontisan understands and at least
      # the header fields parsed successfully.
      #
      # @return [Boolean]
      def valid?
        return false if version.nil?
        return false unless [VERSION_2_0, VERSION_3_0].include?(version)

        true
      end

      private

      # Read the IndexSubTableArray entries for one strike.
      #
      # @param strike [CblcBitmapSize]
      # @param array_offset [Integer] absolute offset within CBLC bytes
      # @return [Array<CblcIndexSubTableArrayEntry>]
      def read_index_subtable_array(strike, array_offset)
        count = strike.number_of_index_subtables
        bytes = raw_data[array_offset, count * 8]
        return [] unless bytes

        Array.new(count) do |i|
          CblcIndexSubTableArrayEntry.read(bytes[i * 8, 8])
        end
      end
    end
  end
end
