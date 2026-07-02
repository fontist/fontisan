# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `sbix` (Apple Bitmap) table.
      #
      # sbix stores bitmap strikes (PNG/JPEG) at multiple sizes. Each
      # strike is a set of glyph-to-bitmap mappings at a specific ppem
      # and resolution.
      #
      # Layout:
      #   Header (8 bytes):
      #     uint16 version (= 1)
      #     uint16 flags
      #     uint32 numStrikes
      #     Offset32 strikeOffsets[numStrikes]
      #
      #   Strike (per ppem):
      #     uint16 ppem
      #     uint16 resolution (ppi)
      #     Offset32 glyphDataOffsets[numGlyphs + 1]
      #
      #   Glyph Data (per glyph):
      #     int16 originOffsetX
      #     int16 originOffsetY
      #     uint16 graphicType ("png " or "jpeg")
      #     uint8 bitmapData[]
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/sbix
      module Sbix
        VERSION = 1
        PNG_TYPE = "png "
        JPEG_TYPE = "jpeg"

        # @param strikes [Array<Hash>] each with :ppem, :resolution,
        #   and :glyphs (Array<Hash> with :origin_x, :origin_y,
        #   :graphic_type, :data per glyph)
        # @param num_glyphs [Integer] total glyph count
        # @return [String, nil] sbix bytes, or nil if no strikes
        def self.build(strikes:, num_glyphs:)
          return nil if strikes.nil? || strikes.empty?

          num_strikes = strikes.size
          header_size = 4 + 4 + (num_strikes * 4) # version + flags + offsets

          strike_bytes = strikes.map { |s| build_strike(s, num_glyphs) }

          io = +""
          io << [VERSION, 0, num_strikes].pack("nnN")

          offset = header_size
          strike_bytes.each do |s|
            io << [offset].pack("N")
            offset += s.bytesize
            io << s
          end
          io
        end

        def self.build_strike(strike, num_glyphs)
          glyphs = strike[:glyphs] || []
          ppem = strike[:ppem] || 0
          resolution = strike[:resolution] || 72

          # Offset table: ppem(2) + resolution(2) + (numGlyphs+1) × offset(4)
          offset_table_size = 4 + ((num_glyphs + 1) * 4)

          offsets = []
          glyph_data = +""
          current_offset = offset_table_size

          num_glyphs.times do |gid|
            glyph = glyphs[gid]
            if glyph && glyph[:data]
              offsets << current_offset
              data = glyph[:data].b
              glyph_data << [glyph[:origin_x] || 0, glyph[:origin_y] || 0].pack("nn")
              glyph_data << (glyph[:graphic_type] || PNG_TYPE).ljust(4)[0, 4]
              glyph_data << data
              current_offset += 8 + data.bytesize
            else
              offsets << current_offset
            end
          end
          offsets << current_offset # sentinel

          io = +""
          io << [ppem, resolution].pack("nn")
          offsets.each { |o| io << [o].pack("N") }
          io << glyph_data
          io
        end

        private_class_method :build_strike
      end
    end
  end
end
