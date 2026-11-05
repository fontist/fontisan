# frozen_string_literal: true

require "digest"

module Fontisan
  module Reference
    # Canonical digests of parsed table content, computed from the raw table
    # bytes with the OpenType layouts written out here (not through the
    # table classes), so another implementation can reproduce them from the
    # same bytes. Every function returns JSON-ready data with String keys;
    # Fixed 16.16 values are raw integers. A structure that runs past the
    # end of its table raises {Truncated}.
    #
    # See docs/reference-facade.md ("Parsed table digests").
    module TableDigests
      class Truncated < StandardError; end

      module_function

      # SHA-256 over the concatenation of the 32-byte digests of each part.
      def digest_of_parts(parts)
        Digest::SHA256.hexdigest(parts.map { |p| Digest::SHA256.digest(p) }.join)
      end

      def sha(bytes)
        Digest::SHA256.hexdigest(bytes)
      end

      def slice(data, offset, length)
        raise Truncated, "#{length} bytes at #{offset} past #{data.bytesize}" if
          offset.negative? || length.negative? || offset + length > data.bytesize

        data.byteslice(offset, length)
      end

      def u8(data, off) = slice(data, off, 1).unpack1("C")
      def u16(data, off) = slice(data, off, 2).unpack1("n")
      def u32(data, off) = slice(data, off, 4).unpack1("N")
      def i32(data, off) = slice(data, off, 4).unpack1("l>")

      # gvar: header fields, the shared tuples, and one digest over every
      # glyph's GlyphVariationData byte range (located by the offset array).
      def gvar(data)
        axis_count = u16(data, 4)
        shared_count = u16(data, 6)
        shared_offset = u32(data, 8)
        glyph_count = u16(data, 12)
        flags = u16(data, 14)
        array_offset = u32(data, 16)
        long = flags.anybits?(1)
        step = long ? 4 : 2
        offsets = Array.new(glyph_count + 1) do |i|
          value = long ? u32(data, 20 + (i * step)) : u16(data, 20 + (i * step)) * 2
          array_offset + value
        end
        parts = offsets.each_cons(2).map { |a, b| slice(data, a, b - a) }
        {
          "axis_count" => axis_count,
          "flags" => flags,
          "glyph_count" => glyph_count,
          "glyphs_with_data" => parts.count { |p| !p.empty? },
          "glyphs_digest" => digest_of_parts(parts),
          "shared_tuple_count" => shared_count,
          "shared_tuples_sha256" => sha(slice(data, shared_offset, shared_count * axis_count * 2)),
          "version" => [u16(data, 0), u16(data, 2)],
        }
      end

      # HVAR / VVAR share a layout: header, ItemVariationStore, and up to
      # three DeltaSetIndexMaps.
      def hvar(data)
        maps = { "advance_mapping" => 8, "lsb_mapping" => 12, "rsb_mapping" => 16 }
        result = { "version" => [u16(data, 0), u16(data, 2)] }
        result["item_variation_store"] = item_variation_store(data, u32(data, 4))
        maps.each do |name, at|
          offset = u32(data, at)
          result[name] = offset.zero? ? nil : delta_set_index_map(data, offset)
        end
        result
      end

      # MVAR: value records (tag, outer, inner) and the ItemVariationStore
      # (Offset16 from the table start).
      def mvar(data)
        record_size = u16(data, 6)
        count = u16(data, 8)
        store_offset = u16(data, 10)
        {
          "version" => [u16(data, 0), u16(data, 2)],
          "value_records" => Array.new(count) do |i|
            at = 12 + (i * record_size)
            { "tag" => slice(data, at, 4), "outer" => u16(data, at + 4), "inner" => u16(data, at + 6) }
          end,
          "item_variation_store" => store_offset.zero? ? nil : item_variation_store(data, store_offset),
        }
      end

      # Exact byte ranges: header+offsets, region list, each
      # ItemVariationData. Digests are per range, then one over all.
      def item_variation_store(data, base)
        region_offset = u32(data, base + 2)
        data_count = u16(data, base + 6)
        region_axes = u16(data, base + region_offset)
        region_count = u16(data, base + region_offset + 2)
        region_len = 4 + (region_count * region_axes * 6)
        subtables = Array.new(data_count) do |i|
          start = base + u32(data, base + 8 + (i * 4))
          items = u16(data, start)
          words = u16(data, start + 2)
          indexes = u16(data, start + 4)
          long = words.anybits?(0x8000)
          word_count = words & 0x7FFF
          row = long ? (word_count * 4) + ((indexes - word_count) * 2) : word_count + indexes
          slice(data, start, 6 + (indexes * 2) + (items * row))
        end
        {
          "region_count" => region_count,
          "item_data_count" => data_count,
          "regions_sha256" => sha(slice(data, base + region_offset, region_len)),
          "data_digest" => digest_of_parts(subtables),
          "data_sha256" => subtables.map { |s| sha(s) },
        }
      end

      # DeltaSetIndexMap: format 0 (u16 count) or 1 (u32 count).
      def delta_set_index_map(data, offset)
        format = u8(data, offset)
        entry_format = u8(data, offset + 1)
        count = format.zero? ? u16(data, offset + 2) : u32(data, offset + 2)
        header = format.zero? ? 4 : 6
        size = ((entry_format >> 4) & 3) + 1
        {
          "format" => format,
          "entry_format" => entry_format,
          "map_count" => count,
          "sha256" => sha(slice(data, offset, header + (count * size))),
        }
      end

      # STAT: design axes and every axis value record, Fixed as raw ints.
      def stat(data)
        axis_size = u16(data, 4)
        axis_count = u16(data, 6)
        axes_offset = u32(data, 8)
        value_count = u16(data, 12)
        values_offset = u32(data, 14)
        minor = u16(data, 2)
        {
          "version" => [u16(data, 0), minor],
          "elided_fallback_name_id" => minor >= 1 ? u16(data, 18) : nil,
          "axes" => Array.new(axis_count) do |i|
            at = axes_offset + (i * axis_size)
            { "tag" => slice(data, at, 4), "name_id" => u16(data, at + 4), "ordering" => u16(data, at + 6) }
          end,
          "axis_values" => Array.new(value_count) do |i|
            axis_value(data, values_offset + u16(data, values_offset + (i * 2)))
          end,
        }
      end

      def axis_value(data, pos)
        format = u16(data, pos)
        case format
        when 1
          fixed_value(data, pos, format, 8, %w[value])
        when 2
          fixed_value(data, pos, format, 8, %w[nominal range_min range_max])
        when 3
          fixed_value(data, pos, format, 8, %w[value linked_value])
        when 4
          n = u16(data, pos + 2)
          { "format" => 4, "flags" => u16(data, pos + 4), "value_name_id" => u16(data, pos + 6),
            "axis_values" => Array.new(n) do |j|
              { "axis_index" => u16(data, pos + 8 + (j * 6)), "value" => i32(data, pos + 10 + (j * 6)) }
            end }
        else
          { "format" => format, "unsupported" => true }
        end
      end

      def fixed_value(data, pos, format, first, names)
        out = { "format" => format, "axis_index" => u16(data, pos + 2), "flags" => u16(data, pos + 4),
                "value_name_id" => u16(data, pos + 6) }
        names.each_with_index { |n, i| out["#{n}_raw"] = i32(data, pos + first + (i * 4)) }
        out
      end

      # CFF2: CharStrings INDEX located through Top DICT operator 17.
      # Returns the per-glyph charstring byte slices.
      def cff2_charstrings(data)
        header_size = u8(data, 2)
        top_length = u16(data, 3)
        offset = dict_operand(slice(data, header_size, top_length), 17)
        return [] unless offset

        count = u32(data, offset)
        return [] if count.zero?

        off_size = u8(data, offset + 4)
        read = ->(i) { slice(data, offset + 5 + (i * off_size), off_size).bytes.inject(0) { |a, b| (a << 8) | b } }
        base = offset + 5 + ((count + 1) * off_size) - 1
        Array.new(count) { |i| slice(data, base + read.call(i), read.call(i + 1) - read.call(i)) }
      end

      # The last operand before `operator` in a DICT, or nil. Only the
      # operand encodings a CharStrings offset can use are decoded; real
      # numbers are skipped (pushed as 0).
      def dict_operand(dict, operator)
        stack = []
        i = 0
        while i < dict.bytesize
          lead = dict.getbyte(i)
          if lead <= 21
            op = lead == 12 ? (i += 1) && (1200 + dict.getbyte(i)) : lead
            return stack.last if op == operator

            stack.clear
          else
            value, i = dict_number(dict, i, lead)
            stack << value
          end
          i += 1
        end
        nil
      end

      # Decode the operand starting at `i`; returns [value, index of its
      # last byte].
      def dict_number(dict, idx, lead)
        case lead
        when 28 then [dict.byteslice(idx + 1, 2).unpack1("s>"), idx + 2]
        when 29 then [dict.byteslice(idx + 1, 4).unpack1("l>"), idx + 4]
        when 30
          idx += 1
          idx += 1 until idx >= dict.bytesize || dict.getbyte(idx) >> 4 == 0xF || dict.getbyte(idx) & 0xF == 0xF
          [0, idx]
        when 32..246 then [lead - 139, idx]
        when 247..250 then [((lead - 247) * 256) + dict.getbyte(idx + 1) + 108, idx + 1]
        when 251..254 then [-((lead - 251) * 256) - dict.getbyte(idx + 1) - 108, idx + 1]
        else [0, idx]
        end
      end
    end
  end
end
