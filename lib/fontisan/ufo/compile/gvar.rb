# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `gvar` (Glyph Variation Data) table from
      # per-glyph deltas computed between a default master and one or
      # more extreme masters.
      #
      # This is the hardest table in the variable-font specification.
      # It stores, for every glyph, how each outline point moves
      # between the default master and each extreme master.
      #
      # This builder produces a minimal-but-valid gvar:
      #   - One tuple per master (no shared tuples)
      #   - Explicit per-point deltas (no IUP compression)
      #   - Delta values encoded as int8 when possible, int16 otherwise
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/gvar
      module Gvar
        VERSION_MAJOR = 1
        VERSION_MINOR = 0

        # TupleIndex flags
        TUPLE_SHARED          = 0x8000
        TUPLE_PRIVATE         = 0x4000
        TUPLE_AXIS_COUNT_MASK = 0x0FFF

        # Delta encoding flags (in the delta data header)
        DELTAS_ARE_ZERO    = 0x80
        DELTAS_ARE_INT8    = 0x40
        POINT_COUNT_MASK   = 0x3FFF

        # @param default_glyphs [Array<Fontisan::Ufo::Glyph>] default master
        # @param masters [Array<Hash>] extreme masters
        #   Each hash: { axes: { tag: peak_value }, glyphs: [Glyph, ...] }
        # @param axis_count [Integer] number of axes
        # @return [String] gvar table bytes
        def self.build(default_glyphs:, masters:, axis_count:)
          glyph_count = default_glyphs.size
          return build_empty(glyph_count) if masters.empty? || glyph_count.zero?

          # Compute per-glyph variation data
          glyph_data = Array.new(glyph_count) do |gid|
            build_glyph_variation(default_glyphs[gid], masters, gid, axis_count)
          end

          assemble(glyph_count, axis_count, glyph_data)
        end

        # ---------- per-glyph variation ----------

        # Build the tuple variation data for a single glyph.
        # Returns the serialized bytes (tuple headers + delta data).
        # Returns empty string if the glyph has no variation.
        def self.build_glyph_variation(default_glyph, masters, gid, axis_count)
          return +"" unless default_glyph

          tuples = []
          masters.each do |master|
            master_glyph = master[:glyphs]&.dig(gid)
            next unless master_glyph

            deltas = compute_deltas(default_glyph, master_glyph)
            next if deltas.all? { |d| d[0].zero? && d[1].zero? }

            tuples << {
              peak: master[:axes] || {},
              deltas: deltas,
            }
          end

          return +"" if tuples.empty?

          serialize_tuples(tuples, axis_count)
        end

        # Compute per-point deltas (dx, dy) between default and master.
        # @return [Array<[Integer, Integer]>] deltas for each point
        def self.compute_deltas(default_glyph, master_glyph)
          default_points = default_glyph.contours.flat_map(&:points)
          master_points = master_glyph.contours.flat_map(&:points)

          count = [default_points.size, master_points.size].min
          Array.new(count) do |i|
            dx = master_points[i].x.to_i - default_points[i].x.to_i
            dy = master_points[i].y.to_i - default_points[i].y.to_i
            [dx, dy]
          end
        end

        # ---------- tuple serialization ----------

        def self.serialize_tuples(tuples, axis_count)
          tuple_entries = tuples.map { |t| serialize_tuple(t, axis_count) }
          tuple_count = tuple_entries.size

          io = +""
          io << [tuple_count].pack("n") # tupleVariationCount
          io << [4 + tuple_count * 4].pack("n") # dataOffset (after header + tuple headers)
          # Wait — dataOffset is from start of per-glyph data to the delta data area.
          # The tuple headers come first, then the delta data.
          # Let me recalculate:
          tuple_headers_size = tuple_entries.sum { |e| e[:header].bytesize }
          data_offset = 4 + tuple_headers_size

          io = +""
          io << [tuple_count].pack("n")
          io << [data_offset].pack("n")

          tuple_entries.each do |e|
            io << e[:header]
            io << e[:data]
          end

          io
        end

        def self.serialize_tuple(tuple, axis_count)
          peak = tuple[:peak]
          deltas = tuple[:deltas]

          # Encode delta data
          all_fit_int8 = deltas.all? { |dx, dy| dx.between?(-127, 127) && dy.between?(-127, 127) }

          point_count = deltas.size
          flags = point_count & POINT_COUNT_MASK
          flags |= DELTAS_ARE_INT8 if all_fit_int8

          data = +""
          data << [flags].pack("n")

          if all_fit_int8
            deltas.each do |dx, dy|
              data << [dx & 0xFF, dy & 0xFF].pack("CC")
            end
          else
            deltas.each do |dx, dy|
              data << [dx & 0xFFFF, dy & 0xFFFF].pack("nn")
            end
          end

          # Encode tuple header
          tuple_index = TUPLE_PRIVATE | (axis_count & TUPLE_AXIS_COUNT_MASK)

          header = +""
          header << [data.bytesize].pack("n") # variationDataSize
          header << [tuple_index].pack("n") # tupleIndex

          # Peak axis coordinates (F2DOT14 per axis)
          axis_tags = peak.keys.sort
          axis_tags.first(axis_count).each do |tag|
            header << [f2dot14(peak[tag] || 0)].pack("n")
          end

          { header: header, data: data }
        end

        # ---------- gvar table assembly ----------

        def self.assemble(glyph_count, axis_count, glyph_data)
          # Build the glyph variation data offset array
          offsets = [0]
          current = 0
          glyph_data.each do |data|
            current += data.bytesize
            offsets << current
          end

          # Offset size: uint16 (flags bit 0 = 0) or uint32 (bit 0 = 1)
          use_long = offsets.last > 0xFFFF
          flags = use_long ? 1 : 0

          # Build header (20 bytes for v1)
          header = +""
          header << [VERSION_MAJOR, VERSION_MINOR].pack("nn") # version
          header << [axis_count].pack("n") # axisCount
          header << [0].pack("n") # sharedTupleCount
          header << [0].pack("N") # offsetToSharedTuples
          header << [glyph_count].pack("n") # glyphCount
          header << [flags].pack("n") # flags (bit 0 = offset size)

          header_size = header.bytesize
          offset_entry_size = use_long ? 4 : 2
          offset_array_size = (glyph_count + 1) * offset_entry_size
          header_size + offset_array_size

          # Offset array (relative to data_start)
          if use_long
            header + offsets.pack("N*") + glyph_data.join
          else
            header + offsets.pack("n*") + glyph_data.join
          end
        end

        def self.build_empty(glyph_count)
          # Minimal gvar with no variation data
          header = [VERSION_MAJOR, VERSION_MINOR, 0, 0, 0, glyph_count, 1, glyph_count * 1 + 16].pack("nnnnnnNN")
          offsets = Array.new(glyph_count + 1, 0).pack("C*")
          header + offsets
        end

        # ---------- helpers ----------

        def self.f2dot14(value)
          (value.to_f * 16384).to_i
        end

        def self.byte_size_for(max_value)
          return 1 if max_value <= 0xFF
          return 2 if max_value <= 0xFFFF
          return 3 if max_value <= 0xFFFFFF

          4
        end
        private_class_method :build_glyph_variation, :compute_deltas,
                             :serialize_tuples, :serialize_tuple,
                             :assemble, :build_empty, :f2dot14, :byte_size_for
      end
    end
  end
end
