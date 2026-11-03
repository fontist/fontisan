# frozen_string_literal: true

module Fontisan
  module Variation
    module Instancing
      # Reads per-glyph tuple variations from a gvar table.
      class GvarReader
        SHARED_POINTS = 0x8000
        EMBEDDED_PEAK = 0x8000
        INTERMEDIATE = 0x4000
        PRIVATE_POINTS = 0x2000
        INDEX_MASK = 0x0FFF

        # points == nil means "every point of the glyph, phantoms included"
        Tuple = Struct.new(:peak, :start, :end, :points, :dx, :dy) do
          def intermediate?
            !start.nil?
          end
        end

        def initialize(data)
          @data = data
          _major, _minor, @axis_count, shared_count, shared_offset,
            @glyph_count, flags, @array_offset = data[0, 20].unpack("nnnnNnnN")
          @long_offsets = flags.anybits?(1)
          @shared = Array.new(shared_count) do |i|
            read_tuple(shared_offset + (i * @axis_count * 2))
          end
        end

        # @param gid [Integer]
        # @param point_count [Integer] glyph points including 4 phantoms
        # @return [Array<Tuple>]
        def tuples_for(gid, point_count)
          return [] if gid >= @glyph_count

          first, last = glyph_range(gid)
          return [] if last <= first

          parse_glyph(@data[@array_offset + first, last - first], point_count)
        end

        private

        def read_tuple(pos)
          @data[pos, @axis_count * 2].unpack("s>*").map { |v| v / 16384.0 }
        end

        def glyph_range(gid)
          if @long_offsets
            @data[20 + (gid * 4), 8].unpack("NN")
          else
            @data[20 + (gid * 2), 4].unpack("nn").map { |v| v * 2 }
          end
        end

        def parse_glyph(glyph_data, point_count)
          count_field, data_offset = glyph_data[0, 4].unpack("nn")
          count = count_field & INDEX_MASK
          headers = []
          pos = 4
          count.times do
            size, index = glyph_data[pos, 4].unpack("nn")
            pos += 4
            peak = start = finish = nil
            if index.anybits?(EMBEDDED_PEAK)
              peak = glyph_data[pos, @axis_count * 2].unpack("s>*").map { |v| v / 16384.0 }
              pos += @axis_count * 2
            else
              peak = @shared.fetch(index & INDEX_MASK)
            end
            if index.anybits?(INTERMEDIATE)
              start = glyph_data[pos, @axis_count * 2].unpack("s>*").map { |v| v / 16384.0 }
              finish = glyph_data[pos + (@axis_count * 2), @axis_count * 2]
                .unpack("s>*").map { |v| v / 16384.0 }
              pos += @axis_count * 4
            end
            headers << [size, index, peak, start, finish]
          end

          dpos = data_offset
          shared_points = nil
          if count_field.anybits?(SHARED_POINTS)
            shared_points, dpos = read_points(glyph_data, dpos)
          end
          headers.map do |size, index, peak, start, finish|
            tuple_end = dpos + size
            points = shared_points
            points, dpos = read_points(glyph_data, dpos) if index.anybits?(PRIVATE_POINTS)
            n = points ? points.size : point_count
            dx, dpos = read_deltas(glyph_data, dpos, n)
            dy, = read_deltas(glyph_data, dpos, n)
            dpos = tuple_end
            Tuple.new(peak, start, finish, points, dx, dy)
          end
        end

        def read_points(data, pos)
          count = data.getbyte(pos)
          pos += 1
          if count.anybits?(0x80)
            count = ((count & 0x7F) << 8) | data.getbyte(pos)
            pos += 1
          end
          return [nil, pos] if count.zero?

          points = []
          last = 0
          while points.size < count
            ctl = data.getbyte(pos)
            pos += 1
            run = (ctl & 0x7F) + 1
            if ctl.anybits?(0x80)
              vals = data[pos, run * 2].unpack("n*")
              pos += run * 2
            else
              vals = data[pos, run].unpack("C*")
              pos += run
            end
            vals.each { |v| points << (last += v) }
          end
          [points, pos]
        end

        def read_deltas(data, pos, count)
          out = []
          while out.size < count
            ctl = data.getbyte(pos)
            pos += 1
            run = (ctl & 0x3F) + 1
            if ctl.anybits?(0x80)
              out.concat(Array.new(run, 0))
            elsif ctl.anybits?(0x40)
              out.concat(data[pos, run * 2].unpack("s>*"))
              pos += run * 2
            else
              out.concat(data[pos, run].unpack("c*"))
              pos += run
            end
          end
          [out.first(count), pos]
        end
      end
    end
  end
end
