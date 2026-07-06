# frozen_string_literal: true

require "stringio"

module Fontisan
  module Woff2
    # Encodes glyf + loca into the WOFF2 transformed glyf table format per
    # WOFF2 spec section 5.1.
    #
    # The loca table is reconstructed by the decoder (its data is omitted
    # from the brotli-compressed stream). Its directory entry keeps
    # origLength and sets transformLength = 0 per spec section 5.3.
    #
    # Output layout (spec section 5.1):
    #   uint16 version              # always 0
    #   uint16 optionFlags          # bit 0 = overlapSimpleBitmap present
    #   uint16 numGlyphs
    #   uint16 indexFormat          # loca format (0=short, 1=long)
    #   uint32 × 7 stream sizes
    #   nContourStream:   int16[numGlyphs]
    #   nPointsStream:    255UInt16 per contour (point count, not endpoint)
    #   flagStream:       uint8[numPoints] (triplet flags)
    #   glyphStream:      triplet payloads + 255UInt16 instructionLength per glyph
    #   compositeStream:  raw component bytes per composite glyph
    #   bboxStream:       bboxBitmap + explicit bbox int16[4] entries
    #   instructionStream: raw instruction bytes
    #   overlapSimpleBitmap (optional)
    class GlyfLocaTransform
      # TrueType simple-glyph flag bits per OpenType spec.
      FLAG_ON_CURVE = 0x01
      FLAG_OVERLAP_SIMPLE = 0x40

      # TrueType composite-glyph flag bits.
      ARG_1_AND_2_ARE_WORDS = 0x0001
      WE_HAVE_A_SCALE = 0x0008
      MORE_COMPONENTS = 0x0020
      WE_HAVE_AN_X_AND_Y_SCALE = 0x0040
      WE_HAVE_A_TWO_BY_TWO = 0x0080
      WE_HAVE_INSTRUCTIONS = 0x0100

      # Simple glyph records start with int16 numberOfContours + 4 int16 bbox.
      SIMPLE_HEADER_SIZE = 10

      attr_reader :num_glyphs, :source_index_format, :target_format

      # @param glyf_data [String] raw glyf table bytes
      # @param loca_data [String] raw loca table bytes
      # @param num_glyphs [Integer] from maxp
      # @param source_index_format [Integer] 0 (short) or 1 (long), from
      #   head.indexToLocFormat of the source font. Used only to parse the
      #   source loca offsets.
      # @param target_format [LocaFormat] the loca format to encode in the
      #   transformed glyf header. Defaults to {LocaFormat::SHORT} per
      #   Chrome's preference; the encoder re-picks based on glyf size.
      def initialize(glyf_data:, loca_data:, num_glyphs:, source_index_format:,
                     target_format: LocaFormat::SHORT)
        @glyf_data = glyf_data
        @loca_data = loca_data
        @num_glyphs = num_glyphs
        @source_index_format = source_index_format
        @target_format = target_format
      end

      # Encode the glyf/loca transform, returning the transformed glyf bytes.
      #
      # @return [String] transformed glyf bytes per spec section 5.1
      def transform
        s = Streams.new(@num_glyphs)
        offsets = parse_loca_offsets

        num_glyphs.times do |glyph_id|
          start_off = offsets[glyph_id]
          end_off = offsets[glyph_id + 1]
          glyph_bytes = @glyf_data[start_off...end_off]

          if glyph_bytes.nil? || glyph_bytes.empty? || glyph_bytes.bytesize.zero?
            s.n_contour << [0].pack("s>")
            next
          end

          num_contours = read_int16(glyph_bytes, 0)
          bbox = read_bbox(glyph_bytes, 2)

          case num_contours
          when 0
            s.n_contour << [0].pack("s>")
          when -1
            encode_composite(s:, glyph_bytes:, bbox:, glyph_id:)
          else
            encode_simple(s:, glyph_bytes:, num_contours:, bbox:, glyph_id:)
          end
        end

        assemble(s)
      end

      # Mutable container for the 7 streams + 2 bitmaps. Avoids passing 9
      # parameters through every helper. Defined at top-level so the Struct
      # class isn't hidden behind `private` (Ruby treats constants as public
      # regardless, but RuboCop flags the modifier as useless).
      Streams = Struct.new(:n_contour, :n_points, :flags, :glyph, :composite,
                           :bbox_data, :instructions, :bbox_bitmap,
                           :overlap_bitmap) do
        def initialize(num_glyphs)
          super(*Array.new(7) { String.new(encoding: Encoding::BINARY) },
                Array.new(((num_glyphs + 31) >> 5) << 2, 0),
                Array.new((num_glyphs + 7) >> 3, 0))
        end

        def has_overlap?
          overlap_bitmap.any?(&:nonzero?)
        end

        # bboxStream on the wire = bboxBitmap || bboxStream (spec section 5.1).
        def bbox_wire
          bbox_bitmap.pack("C*") + bbox_data
        end
      end

      private

      def encode_simple(s:, glyph_bytes:, num_contours:, bbox:, glyph_id:)
        s.n_contour << [num_contours].pack("s>")

        io = StringIO.new(glyph_bytes)
        io.pos = SIMPLE_HEADER_SIZE
        end_pts = Array.new(num_contours) { io.read(2).unpack1("n") }
        total_points = end_pts.last + 1

        # nPoints stream: per-contour point counts (NOT endPtsOfContours).
        prev_end = -1
        end_pts.each do |ep|
          s.n_points << UInt255.encode(ep - prev_end)
          prev_end = ep
        end

        inst_len = io.read(2).unpack1("n")
        instructions = io.read(inst_len)

        tt_flags = decode_truetype_flags(io, total_points)
        xs = decode_coordinates(io, tt_flags, x_axis: true)
        ys = decode_coordinates(io, tt_flags, x_axis: false)

        # Re-encode each point as a WOFF2 triplet
        prev_x = prev_y = 0
        total_points.times do |i|
          dx = xs[i] - prev_x
          dy = ys[i] - prev_y
          prev_x = xs[i]
          prev_y = ys[i]
          on_curve = (tt_flags[i] & FLAG_ON_CURVE).nonzero?
          flag, payload = TripletCodec.encode(dx, dy, on_curve:)
          s.flags << [flag].pack("C")
          s.glyph << payload.pack("C*")
        end

        # Overlap bit lives on the first flag of each simple glyph
        if (tt_flags.first & FLAG_OVERLAP_SIMPLE).nonzero?
          s.overlap_bitmap[glyph_id >> 3] |= (0x80 >> (glyph_id & 7))
        end

        # glyphStream carries per-glyph instructionLength; bytes go to instructionStream
        s.glyph << UInt255.encode(instructions.bytesize)
        s.instructions << instructions

        # Spec: simple glyphs omit bbox when it matches calculated bounds.
        calculated = calc_bounds(xs, ys)
        return if calculated == bbox

        set_bbox_bit(s, glyph_id)
        s.bbox_data << bbox.pack("s>*")
      end

      def encode_composite(s:, glyph_bytes:, bbox:, glyph_id:)
        s.n_contour << [-1].pack("s>")

        io = StringIO.new(glyph_bytes)
        io.pos = SIMPLE_HEADER_SIZE

        components_end = nil
        have_instructions = false
        loop do
          flags = io.read(2).unpack1("n")
          io.read(2) # glyphIndex
          io.read((flags & ARG_1_AND_2_ARE_WORDS).nonzero? ? 4 : 2)
          io.read(component_transform_size(flags))
          components_end = io.pos
          have_instructions = (flags & WE_HAVE_INSTRUCTIONS).nonzero?
          break if (flags & MORE_COMPONENTS).zero?
        end

        s.composite << glyph_bytes[SIMPLE_HEADER_SIZE...components_end]

        if have_instructions
          inst_len = io.read(2).unpack1("n")
          instructions = io.read(inst_len)
          s.glyph << UInt255.encode(instructions.bytesize)
          s.instructions << instructions
        end

        # Composite glyphs MUST have explicit bbox per spec section 5.1
        set_bbox_bit(s, glyph_id)
        s.bbox_data << bbox.pack("s>*")
      end

      def component_transform_size(flags)
        if (flags & WE_HAVE_A_SCALE).nonzero? then 2
        elsif (flags & WE_HAVE_AN_X_AND_Y_SCALE).nonzero? then 4
        elsif (flags & WE_HAVE_A_TWO_BY_TWO).nonzero? then 8
        else
          0
        end
      end

      def decode_truetype_flags(io, total_points)
        flags = []
        while flags.size < total_points
          flag = io.read(1).unpack1("C")
          flags << flag
          if (flag & 0x08).nonzero? # REPEAT_FLAG
            repeat = io.read(1).unpack1("C")
            repeat.times { flags << flag }
          end
        end
        flags
      end

      def decode_coordinates(io, flags, x_axis:)
        short_flag = x_axis ? 0x02 : 0x04
        same_flag = x_axis ? 0x10 : 0x20

        coord = 0
        coords = []
        flags.each do |flag|
          if (flag & short_flag).nonzero?
            delta = io.read(1).unpack1("C")
            delta = -delta if (flag & same_flag).zero?
          elsif (flag & same_flag).nonzero?
            delta = 0
          else
            delta = read_int16_io(io)
          end
          coord += delta
          coords << coord
        end
        coords
      end

      def assemble(s)
        bbox_bitmap_bytes = ((@num_glyphs + 31) >> 5) << 2
        # Pad bbox_bitmap to required size (struct may have fewer bytes allocated)
        bb = s.bbox_bitmap
        if bb.size < bbox_bitmap_bytes
          bb.concat(Array.new(bbox_bitmap_bytes - bb.size, 0))
        end

        out = String.new(encoding: Encoding::BINARY)
        out << [0].pack("S>")                                  # version
        out << [(s.has_overlap? ? 1 : 0)].pack("S>")           # optionFlags
        out << [@num_glyphs].pack("S>")
        out << [target_format.code].pack("S>")
        out << [s.n_contour.bytesize].pack("L>")
        out << [s.n_points.bytesize].pack("L>")
        out << [s.flags.bytesize].pack("L>")
        out << [s.glyph.bytesize].pack("L>")
        out << [s.composite.bytesize].pack("L>")
        out << [s.bbox_wire.bytesize].pack("L>")
        out << [s.instructions.bytesize].pack("L>")
        out << s.n_contour
        out << s.n_points
        out << s.flags
        out << s.glyph
        out << s.composite
        out << s.bbox_wire
        out << s.instructions
        out << s.overlap_bitmap.pack("C*") if s.has_overlap?
        out
      end

      def parse_loca_offsets
        if @source_index_format.zero?
          @loca_data.unpack("n*").map { |v| v * 2 }
        else
          @loca_data.unpack("N*")
        end
      end

      def set_bbox_bit(s, glyph_id)
        s.bbox_bitmap[glyph_id >> 3] |= (0x80 >> (glyph_id & 7))
      end

      def read_int16(bytes, offset)
        v = (bytes.getbyte(offset) << 8) | bytes.getbyte(offset + 1)
        v > 0x7FFF ? v - 0x10000 : v
      end

      def read_int16_io(io)
        v = io.read(2).unpack1("n")
        v > 0x7FFF ? v - 0x10000 : v
      end

      def read_bbox(bytes, offset)
        [
          read_int16(bytes, offset),
          read_int16(bytes, offset + 2),
          read_int16(bytes, offset + 4),
          read_int16(bytes, offset + 6),
        ]
      end

      def calc_bounds(xs, ys)
        return nil if xs.empty?

        [xs.min, ys.min, xs.max, ys.max]
      end
    end
  end
end
