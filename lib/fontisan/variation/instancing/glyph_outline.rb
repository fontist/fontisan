# frozen_string_literal: true

module Fontisan
  module Variation
    module Instancing
      # A parsed glyf entry that can be moved by deltas and re-serialized.
      # Points are the simple-glyph points, or for composites one point per
      # component (its x/y offset), matching gvar's point numbering.
      class GlyphOutline
        ON_CURVE = 0x01
        X_SHORT = 0x02
        Y_SHORT = 0x04
        REPEAT = 0x08
        X_SAME = 0x10
        Y_SAME = 0x20

        ARGS_ARE_WORDS = 0x0001
        ARGS_ARE_XY = 0x0002
        HAVE_SCALE = 0x0008
        MORE_COMPONENTS = 0x0020
        HAVE_XY_SCALE = 0x0040
        HAVE_TWO_BY_TWO = 0x0080

        Component = Struct.new(:flags, :gid, :arg1, :arg2, :transform)

        attr_reader :end_pts, :on_curve, :overlap, :instructions, :components,
                    :trailer, :header_contours

        def self.parse(bytes)
          new(bytes)
        end

        def initialize(bytes)
          @header_contours = 0
          @end_pts = []
          @on_curve = []
          @components = []
          @points = []
          return if bytes.nil? || bytes.empty?

          @header_contours = bytes[0, 2].unpack1("s>")
          if @header_contours >= 0
            parse_simple(bytes)
          else
            parse_composite(bytes)
          end
        end

        def empty?
          @header_contours.zero? && @points.empty?
        end

        def composite?
          @header_contours.negative?
        end

        # @return [Array<Array<Float>>] [[x, y], ...]
        def points
          @points.map(&:dup)
        end

        def point_count
          @points.size
        end

        def bounds_of(points)
          return nil if points.empty?

          xs = points.map(&:first)
          ys = points.map(&:last)
          [xs.min, ys.min, xs.max, ys.max]
        end

        # Serialize with the given (already rounded) points. +bbox+ is the
        # [xMin, yMin, xMax, yMax] to record in the header.
        def serialize(new_points, bbox)
          return "".b if empty?

          composite? ? serialize_composite(new_points, bbox) : serialize_simple(new_points, bbox)
        end

        private

        def parse_simple(bytes)
          n = @header_contours
          @end_pts = bytes[10, n * 2].unpack("n*")
          pos = 10 + (n * 2)
          ilen = bytes[pos, 2].unpack1("n")
          @instructions = bytes[pos + 2, ilen]
          pos += 2 + ilen
          count = n.zero? ? 0 : @end_pts.last + 1
          flags = []
          while flags.size < count
            f = bytes.getbyte(pos)
            pos += 1
            flags << f
            if f.anybits?(REPEAT)
              bytes.getbyte(pos).times { flags << f }
              pos += 1
            end
          end
          xs = read_coords(bytes, pos, flags, X_SHORT, X_SAME)
          pos = xs.pop
          ys = read_coords(bytes, pos, flags, Y_SHORT, Y_SAME)
          ys.pop
          @on_curve = flags.map { |f| f.anybits?(ON_CURVE) }
          @overlap = flags.first&.anybits?(0x40) || false
          @points = xs.zip(ys)
        end

        def read_coords(bytes, pos, flags, short, same)
          val = 0
          out = flags.map do |f|
            if f.anybits?(short)
              d = bytes.getbyte(pos)
              pos += 1
              val += f.anybits?(same) ? d : -d
            elsif !f.anybits?(same)
              val += bytes[pos, 2].unpack1("s>")
              pos += 2
            end
            val
          end
          out << pos
        end

        def parse_composite(bytes)
          pos = 10
          loop do
            flags, gid = bytes[pos, 4].unpack("nn")
            pos += 4
            if flags.anybits?(ARGS_ARE_WORDS)
              fmt = flags.anybits?(ARGS_ARE_XY) ? "s>s>" : "nn"
              a1, a2 = bytes[pos, 4].unpack(fmt)
              pos += 4
            else
              fmt = flags.anybits?(ARGS_ARE_XY) ? "cc" : "CC"
              a1, a2 = bytes[pos, 2].unpack(fmt)
              pos += 2
            end
            tlen = if flags.anybits?(HAVE_SCALE) then 2
                   elsif flags.anybits?(HAVE_XY_SCALE) then 4
                   elsif flags.anybits?(HAVE_TWO_BY_TWO) then 8
                   else 0
                   end
            @components << Component.new(flags, gid, a1, a2, bytes[pos, tlen])
            pos += tlen
            break unless flags.anybits?(MORE_COMPONENTS)
          end
          @trailer = bytes[pos..] || "".b
          @points = @components.map do |c|
            c.flags.anybits?(ARGS_ARE_XY) ? [c.arg1.to_f, c.arg2.to_f] : [0.0, 0.0]
          end
        end

        def serialize_simple(pts, bbox)
          out = [@header_contours, *bbox].pack("s>5")
          out << @end_pts.pack("n*")
          out << [@instructions.bytesize].pack("n") << @instructions
          flags = +"".b
          xs = +"".b
          ys = +"".b
          px = py = 0
          pts.each_with_index do |(x, y), i|
            f = @on_curve[i] ? ON_CURVE : 0
            f |= 0x40 if i.zero? && @overlap
            dx = x - px
            dy = y - py
            if dx.zero? then f |= X_SAME
            else xs << [dx].pack("s>")
            end
            if dy.zero? then f |= Y_SAME
            else ys << [dy].pack("s>")
            end
            flags << f.chr
            px = x
            py = y
          end
          out << flags << xs << ys
        end

        def serialize_composite(pts, bbox)
          out = [@header_contours, *bbox].pack("s>5")
          @components.each_with_index do |c, i|
            flags = c.flags
            a1 = c.arg1
            a2 = c.arg2
            if flags.anybits?(ARGS_ARE_XY)
              a1, a2 = pts[i]
              flags |= ARGS_ARE_WORDS
              out << [flags, c.gid, a1, a2].pack("nns>s>")
            elsif flags.anybits?(ARGS_ARE_WORDS)
              out << [flags, c.gid, a1, a2].pack("nnnn")
            else
              out << [flags, c.gid, a1, a2].pack("nnCC")
            end
            out << c.transform
          end
          out << @trailer
        end
      end
    end
  end
end
