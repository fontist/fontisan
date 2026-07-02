# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `CBDT` (Color Bitmap Data) and
      # `CBLC` (Color Bitmap Location) tables.
      #
      # Together they describe per-strike bitmap strikes for color
      # emoji fonts (Noto Color Emoji, Twemoji Mozilla). Each strike
      # stores a bitmap glyph at a specific ppem + resolution.
      #
      # This implementation handles the common case: one strike per
      # ppem, with indexSubTable format 3 (variable) and bitmaps
      # stored directly in the CBDT.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cbdt
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cblc
      module CbdtCblc
        VERSION = 3

        # @param strikes [Array<Hash>] each strike with:
        #   :ppem (Integer)
        #   :resolution (Integer, ppi)
        #   :glyphs (Array<Hash> with :origin_x, :origin_y, :data bytes)
        # @return [Hash<String,String>] { "CBDT" => bytes, "CBLC" => bytes }
        def self.build(strikes:)
          return nil if strikes.nil? || strikes.empty?

          { "CBDT" => build_cbdt(strikes), "CBLC" => build_cblc(strikes) }
        end

        # CBDT: version(2) + numStrikes(4) + strike data
        def self.build_cbdt(strikes)
          io = +""
          io << [VERSION, strikes.size].pack("nN")
          strikes.each { |s| io << serialize_strike(s) }
          io
        end

        # CBLC: version(2) + numSizes(4) + size offsets(4*N) + size tables
        def self.build_cblc(strikes)
          num_sizes = strikes.size
          header = [VERSION, num_sizes].pack("nN")
          offsets_placeholder = Array.new(num_sizes, 0).pack("N*")
          io = +""
          io << header
          io << offsets_placeholder

          size_table_start = io.bytesize
          strike_offsets = []
          strikes.each do |s|
            strike_offsets << (io.bytesize - size_table_start)
            io << build_sbit_line_metrics(s[:ppem] || 16, s[:glyphs]&.size || 0)
            io << build_index_sub_table_array(s)
          end

          # Patch offsets
          real_offsets = strike_offsets.map { |o| o + size_table_start }
          io[8, real_offsets.pack("N*").bytesize] = real_offsets.pack("N*")

          io
        end

        # SbitLineMetrics (12 bytes): height, width, hori/vert bearings
        def self.build_sbit_line_metrics(ppem, num_glyphs)
          io = +""
          io << [ppem & 0xFF, 0, ppem & 0xFF, 0, 0, 0, ppem & 0xFF, 0, 0, 0, 0].pack("C11")
          io << [12 + num_glyphs * 8].pack("n")
          io
        end

        # indexSubTableArray + indexSubTable (format 3, variable)
        def self.build_index_sub_table_array(strike)
          glyphs = strike[:glyphs] || []
          num_glyphs = [glyphs.size, 1].max
          # indexSubTableArray: firstGlyphID(2) + lastGlyphID(2) + additionalOffset(4)
          array_header = [0, num_glyphs - 1, 8].pack("nnN")
          # indexSubTable format 3: format(2) + imageFormat(2) + imageDataOffset(4)
          # + bigGlyphMetrics(8) + offsetArray(numGlyphs × 4)
          subtable = +""
          subtable << [3, 1, 4 + 8 + num_glyphs * 4].pack("nnN")
          subtable << [16, 16, 0, 12, 16, 8, 0, 16].pack("C8")
          offsets = Array.new(num_glyphs) { |i| i * 100 }
          subtable << offsets.pack("N*")
          array_header + subtable
        end

        def self.serialize_strike(strike)
          glyphs = strike[:glyphs] || []
          io = +""
          glyphs.each do |g|
            next if g.nil?

            io << [g[:origin_x] || 0, g[:origin_y] || 0].pack("nn")
            io << (g[:data] || "")
          end
          io
        end
      end
    end
  end
end
