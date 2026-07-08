# frozen_string_literal: true

module Fontisan
  module Tables
    # Per-format CBLC IndexSubTable parser. Extracted as a sibling class so
    # that CblcIndexSubTable remains a pure data model.
    #
    # The five OpenType formats differ in how the offset array encodes
    # glyph lengths and CBDT offsets. This class hides that arithmetic
    # behind a uniform [.locations] entry point that returns a flat list
    # of CblcGlyphBitmapLocation objects (one per glyph in the range).
    #
    # Reference: OpenType CBLC spec, IndexSubTable formats 1–5.
    class CblcIndexSubTableFormatParser
      # Format 4 (bit-packed offsets) is rare and not currently parsed.
      class UnsupportedFormat < Fontisan::Error; end

      class << self
        # Returns an Array of CblcGlyphBitmapLocation, one per glyph in
        # the IndexSubTable's glyph range.
        #
        # @param header [CblcIndexSubTableHeader] the 8-byte IndexSubTable header
        # @param bytes [String] the full CBLC table bytes
        # @param base [Integer] absolute offset of this IndexSubTable within CBLC
        # @param first [Integer] first glyph ID covered
        # @param last [Integer] last glyph ID covered
        # @return [Array<CblcGlyphBitmapLocation>]
        def locations(header:, bytes:, base:, first:, last:)
          case header.index_format
          when 1 then format_1(header, bytes, base, first, last)
          when 2 then format_2(header, bytes, base, first, last)
          when 3 then format_3(header, bytes, base, first, last)
          when 5 then format_5(header, bytes, base, first, last)
          when 4
            raise UnsupportedFormat,
                  "CBLC IndexSubTable format 4 (bit-packed) is unsupported"
          else
            raise UnsupportedFormat,
                  "Unknown CBLC IndexSubTable format: #{header.index_format}"
          end
        end

        # Returns the raw bytes the IndexSubTable occupies in CBLC.
        #
        # @return [String]
        def raw_bytes(header:, bytes:, base:, first:, last:)
          count = last - first + 1
          length = byte_length(header.index_format, count, bytes, base)
          bytes[base, length]
        end

        private

        # Format 1: variable metrics + variable size, uint32 offsetArray.
        # offsets[0] is the first glyph's bitmap start (relative to
        # imageDataOffset); offsets[i+1] - offsets[i] = glyph i's length.
        def format_1(header, bytes, base, first, last)
          count = last - first + 1
          offsets = uint32_array(bytes, base + 8, count + 1)
          build(first, count, offsets, header.image_format,
                header.image_data_offset)
        end

        # Format 2: constant metrics + constant size. One imageSize field
        # applies to every glyph; the i-th glyph's bitmap is at
        # imageDataOffset + i * imageSize.
        def format_2(header, bytes, base, first, last)
          count = last - first + 1
          image_size = bytes[base + 8, 4].unpack1("N")
          Array.new(count) do |i|
            CblcGlyphBitmapLocation.new(
              glyph_id: first + i,
              image_format: header.image_format,
              cbdt_offset: header.image_data_offset + (i * image_size),
              byte_length: image_size,
            )
          end
        end

        # Format 3: like format 1 but offsets are uint16 and stored as
        # multiples of 4 (CBDT bitmap data is 4-byte aligned).
        def format_3(header, bytes, base, first, last)
          count = last - first + 1
          raw = uint16_array(bytes, base + 8, count + 1)
          offsets = raw.map { |v| v * 4 }
          build(first, count, offsets, header.image_format,
                header.image_data_offset)
        end

        # Format 5: constant metrics + constant size with an explicit
        # uint32 offsetArray (count + 1 entries). Length per glyph is
        # the constant imageSize; offset comes from the array.
        def format_5(header, bytes, base, first, last)
          count = last - first + 1
          image_size = bytes[base + 8, 4].unpack1("N")
          offset_array_start = base + 12 + 8 + 4
          offsets = uint32_array(bytes, offset_array_start, count + 1)
          Array.new(count) do |i|
            start_off = offsets[i] || 0
            CblcGlyphBitmapLocation.new(
              glyph_id: first + i,
              image_format: header.image_format,
              cbdt_offset: header.image_data_offset + start_off,
              byte_length: image_size,
            )
          end
        end

        def build(first, count, offsets, image_format, image_data_offset)
          Array.new(count) do |i|
            start_off = offsets[i] || 0
            end_off = offsets[i + 1] || start_off
            CblcGlyphBitmapLocation.new(
              glyph_id: first + i,
              image_format: image_format,
              cbdt_offset: image_data_offset + start_off,
              byte_length: end_off - start_off,
            )
          end
        end

        def byte_length(index_format, count, bytes, base)
          case index_format
          when 1, 3
            entry_size = index_format == 1 ? 4 : 2
            8 + (count + 1) * entry_size
          when 2
            8 + 4 + 8 # header + imageSize + bigGlyphMetrics
          when 5
            8 + 4 + 8 + 4 + (count + 1) * 4
          else
            bytes.bytesize - base
          end
        end

        def uint32_array(bytes, offset, count)
          return [] if count.zero?

          bytes[offset, count * 4].unpack("N*")
        end

        def uint16_array(bytes, offset, count)
          return [] if count.zero?

          bytes[offset, count * 2].unpack("n*")
        end
      end
    end
  end
end
