# frozen_string_literal: true

require "stringio"

module Fontisan
  module Woff2
    # Reconstructs glyf and loca tables from the WOFF2 transformed glyf
    # stream per spec section 5.1. This is the decoder counterpart of
    # {Woff2::GlyfLocaTransform}.
    #
    # The transformed glyf table is split into 7 streams preceded by a
    # 36-byte header (uint16 version + uint16 optionFlags + uint16 numGlyphs
    # + uint16 indexFormat + 7 × uint32 stream sizes). An optional
    # overlapSimpleBitmap follows when optionFlags bit 0 is set.
    #
    # Reference: W3C WOFF2 spec, section 5.1.
    class GlyfLocaReconstruct
      # TrueType simple-glyph flag bits per OpenType spec.
      FLAG_ON_CURVE = 0x01
      FLAG_X_SHORT = 0x02
      FLAG_Y_SHORT = 0x04
      FLAG_REPEAT = 0x08
      FLAG_X_SAME_OR_POS = 0x10
      FLAG_Y_SAME_OR_POS = 0x20
      FLAG_OVERLAP_SIMPLE = 0x40

      # TrueType composite-glyph flag bits.
      ARG_1_AND_2_ARE_WORDS = 0x0001
      WE_HAVE_A_SCALE = 0x0008
      MORE_COMPONENTS = 0x0020
      WE_HAVE_AN_X_AND_Y_SCALE = 0x0040
      WE_HAVE_A_TWO_BY_TWO = 0x0080
      WE_HAVE_INSTRUCTIONS = 0x0100

      # 8-byte header + 7 × 4-byte stream sizes.
      HEADER_SIZE = 36

      attr_reader :num_glyphs, :index_format

      # @param transformed_glyf [String] bytes of the transformed glyf table
      # @param num_glyphs [Integer] from maxp
      # @param index_format [Integer] 0 (short) or 1 (long), from head
      def initialize(transformed_glyf:, num_glyphs:, index_format:)
        @data = transformed_glyf
        @num_glyphs = num_glyphs
        @index_format = index_format
      end

      # Reconstruct glyf and loca tables.
      #
      # Per OpenType glyf table spec, loca offsets must be even (short
      # format) or multiples of 4 (long format). Each reconstructed glyph
      # is padded to the loca-format alignment boundary so the next
      # glyph starts at a valid offset. Without this padding, Chrome's
      # OTS rejects the font with "Failed to convert WOFF 2.0 font to
      # SFNT" because glyf.origLength understates the padded size every
      # conformant decoder produces.
      #
      # @return [Hash{Symbol => String}] `{ glyf:, loca: }`
      def reconstruct
        header = parse_header
        streams = read_streams(header)

        glyf = String.new(encoding: Encoding::BINARY)
        offsets = [0]
        # Short loca (indexFormat=0) stores offset/2 as uint16, so glyph
        # offsets must be even — pad to 2-byte boundary. Long loca
        # (indexFormat=1) has no alignment requirement (fontTools does
        # not pad). Matching fontTools exactly is required: Chrome OTS
        # rejects when glyf.origLength doesn't equal the decoder's output.
        align = @index_format.zero? ? 2 : 1

        num_glyphs.times do |glyph_id|
          glyph = decode_glyph(glyph_id, streams)
          glyf << glyph
          if align > 1
            remainder = glyf.bytesize % align
            glyf << ("\x00" * (align - remainder)) if remainder.positive?
          end
          offsets << glyf.bytesize
        end

        { glyf:, loca: build_loca(offsets) }
      end

      private

      # Parsed header. Holds the 4 uint16 fields plus the 7 uint32 stream
      # sizes. Stored as a Hash so the keys document themselves.
      def parse_header
        version, option_flags, ng, idx_fmt = @data[0, 8].unpack("S>S>S>S>")
        sizes = @data[8, 28].unpack("L>7")

        if ng != @num_glyphs
          raise InvalidFontError,
                "WOFF2 glyf numGlyphs mismatch: header says #{ng}, expected #{@num_glyphs}"
        end
        if idx_fmt != @index_format
          raise InvalidFontError,
                "WOFF2 glyf indexFormat mismatch: header says #{idx_fmt}, expected #{@index_format}"
        end

        {
          version:,
          option_flags:,
          has_overlap_bitmap: (option_flags & 0x01).nonzero?,
          stream_sizes: sizes,
        }
      end

      # Slice the 7 streams out of the data block and set up per-stream
      # StringIO cursors. The bboxStream is split into bboxBitmap (fixed
      # size per numGlyphs) and bboxStream (variable, conditionally read
      # per glyph). The optional overlapSimpleBitmap is read at the end.
      def read_streams(header)
        pos = HEADER_SIZE
        bitmap_size = ((@num_glyphs + 31) >> 5) << 2
        overlap_size = header[:has_overlap_bitmap] ? ((@num_glyphs + 7) >> 3) : 0

        names = %i[n_contour n_points flags glyph composite bbox instructions]
        streams = {}
        names.each_with_index do |name, i|
          size = header[:stream_sizes][i]
          streams[name] = StringIO.new(@data[pos, size])
          pos += size
        end

        # bboxStream begins with bboxBitmap (4 × floor((numGlyphs+31)/32)).
        bbox_blob = streams[:bbox].string
        streams[:bbox_bitmap] = bbox_blob[0, bitmap_size] || ""
        streams[:bbox_entries] = StringIO.new(bbox_blob[bitmap_size..] || "")

        # overlapSimpleBitmap follows all streams when optionFlags bit 0 set.
        streams[:overlap_bitmap] =
          header[:has_overlap_bitmap] ? @data[pos, overlap_size] : ""

        # nContour is read positionally (int16 per glyph).
        nc_data = streams[:n_contour].string
        streams[:n_contour_values] = nc_data.unpack("s>*")

        streams
      end

      def decode_glyph(glyph_id, streams)
        num_contours = streams[:n_contour_values][glyph_id]

        case num_contours
        when 0
          # Empty glyph: just an entry in loca (loca[n] == loca[n-1]).
          ""
        when -1
          decode_composite(glyph_id, streams)
        else
          decode_simple(glyph_id, num_contours, streams)
        end
      end

      # Decode a simple glyph per spec section 5.1 "Decoding of Simple Glyphs".
      def decode_simple(glyph_id, num_contours, streams)
        # Step 1: read num_contours 255UInt16 values from nPointsStream to
        # build endPtsOfContours[].
        end_pts = []
        cumulative = -1
        num_contours.times do
          pts_of_contour = UInt255.decode(streams[:n_points])
          cumulative += pts_of_contour
          end_pts << cumulative
        end
        total_points = end_pts.last + 1

        # Step 2: read total_points flag bytes from flagStream (triplet flags).
        triplet_flags = streams[:flags].read(total_points).bytes

        # Step 3: read coordinate triplets from glyphStream (1-4 bytes per
        # point depending on flag). Decode to (dx, dy) deltas.
        xs = []
        ys = []
        on_curve_flags = []
        x = 0
        y = 0
        triplet_flags.each do |flag|
          dx, dy, oc = TripletCodec.decode(flag,
                                           read_triplet_payload(flag,
                                                                streams[:glyph]))
          x += dx
          y += dy
          xs << x
          ys << y
          on_curve_flags << (oc ? FLAG_ON_CURVE : 0)
        end

        # Step 4-5: read instructionLength from glyphStream, bytes from instructionStream.
        inst_len = UInt255.decode(streams[:glyph])
        instructions = streams[:instructions].read(inst_len)

        # Bbox: emit explicit bbox if bboxBitmap bit is set for this glyph,
        # otherwise recalculate from coordinates.
        bbox = if bbox_bit_set?(streams[:bbox_bitmap], glyph_id)
                 read_bbox(streams[:bbox_entries])
               else
                 calc_bounds(xs, ys) || [0, 0, 0, 0]
               end

        # Re-encode in standard TrueType format.
        build_simple_glyph_bytes(num_contours:, bbox:, end_pts:,
                                 on_curve_flags:, xs:, ys:, instructions:,
                                 overlap: overlap_bit_set?(streams[:overlap_bitmap], glyph_id))
      end

      def decode_composite(_glyph_id, streams)
        # Composite components are stored verbatim in compositeStream. Walk
        # the component records to find their total byte length, then copy.
        # Per spec section 5.1 "Decoding of Composite Glyphs": each component
        # has a uint16 flags word, then 4-14 argument bytes.
        composite_io = streams[:composite]
        component_start = composite_io.pos
        have_instructions = false
        loop do
          break if composite_io.eof?

          flags = read_uint16_io(composite_io)
          composite_io.read(2) # glyphIndex
          composite_io.read((flags & ARG_1_AND_2_ARE_WORDS).nonzero? ? 4 : 2)
          composite_io.read(composite_transform_size(flags))
          have_instructions = (flags & WE_HAVE_INSTRUCTIONS).nonzero?
          break if (flags & MORE_COMPONENTS).zero?
        end
        component_end = composite_io.pos
        component_bytes = composite_io.string[component_start...component_end]

        instructions = String.new(encoding: Encoding::BINARY)
        if have_instructions
          inst_len = UInt255.decode(streams[:glyph])
          instructions = streams[:instructions].read(inst_len)
        end

        # Composite glyphs always have explicit bbox in bboxStream.
        bbox = read_bbox(streams[:bbox_entries])

        # num_contours = -1 (int16), bbox 4 × int16, components, optional instructions
        out = String.new(encoding: Encoding::BINARY)
        out << [-1].pack("s>")
        out << bbox.pack("s>*")
        out << component_bytes
        # If the last component had WE_HAVE_INSTRUCTIONS, the standard
        # TrueType composite format expects a uint16 instructionLength
        # followed by the instruction bytes.
        if have_instructions
          out << [instructions.bytesize].pack("n")
          out << instructions
        end
        out
      end

      def composite_transform_size(flags)
        if (flags & WE_HAVE_A_SCALE).nonzero? then 2
        elsif (flags & WE_HAVE_AN_X_AND_Y_SCALE).nonzero? then 4
        elsif (flags & WE_HAVE_A_TWO_BY_TWO).nonzero? then 8
        else
          0
        end
      end

      # Read 1-4 payload bytes for a triplet based on the flag's index bits.
      def read_triplet_payload(flag, io)
        idx = flag & 0x7F
        n_bytes = if idx < 84 then 1
                  elsif idx < 120 then 2
                  elsif idx < 124 then 3
                  else 4
                  end
        bytes = io.read(n_bytes)
        bytes ? bytes.bytes : Array.new(n_bytes, 0)
      end

      def read_uint16_io(io)
        io.read(2)&.unpack1("n") || 0
      end

      def bbox_bit_set?(bbox_bitmap, glyph_id)
        return false if bbox_bitmap.nil? || bbox_bitmap.empty?

        byte_idx = glyph_id >> 3
        bit_idx = glyph_id & 7
        (bbox_bitmap.getbyte(byte_idx) & (0x80 >> bit_idx)).nonzero?
      end

      def overlap_bit_set?(overlap_bitmap, glyph_id)
        return false unless overlap_bitmap && !overlap_bitmap.empty?

        byte_idx = glyph_id >> 3
        bit_idx = glyph_id & 7
        (overlap_bitmap.getbyte(byte_idx) & (0x80 >> bit_idx)).nonzero?
      end

      def read_bbox(io)
        bytes = io.read(8)
        return [0, 0, 0, 0] unless bytes&.bytesize == 8

        bytes.unpack("s>*")
      end

      def calc_bounds(xs, ys)
        return nil if xs.empty?

        [xs.min, ys.min, xs.max, ys.max]
      end

      # Build a standard TrueType simple-glyph record from per-point arrays.
      # Re-encodes coordinates using the standard TrueType flag scheme based
      # on per-point delta magnitudes (per OFF section 5.3.3 spec rules).
      def build_simple_glyph_bytes(num_contours:, bbox:, end_pts:, on_curve_flags:,
                                   xs:, ys:, instructions:, overlap:)
        out = String.new(encoding: Encoding::BINARY)
        out << [num_contours].pack("s>")
        out << bbox.pack("s>*")
        out << end_pts.pack("n*")
        out << [instructions.bytesize].pack("n")
        out << instructions

        prev_x = prev_y = 0
        tt_flags = []
        x_bytes = String.new(encoding: Encoding::BINARY)
        y_bytes = String.new(encoding: Encoding::BINARY)

        xs.each_with_index do |x, i|
          y = ys[i]
          dx = x - prev_x
          dy = y - prev_y
          prev_x = x
          prev_y = y

          base = on_curve_flags[i]
          base |= FLAG_OVERLAP_SIMPLE if overlap && i.zero?

          flag = encode_axis_bits(base, x_bytes, short_bit: FLAG_X_SHORT,
                                                 same_bit: FLAG_X_SAME_OR_POS,
                                                 value: dx)
          flag = encode_axis_bits(flag, y_bytes, short_bit: FLAG_Y_SHORT,
                                                 same_bit: FLAG_Y_SAME_OR_POS,
                                                 value: dy)
          tt_flags << flag
        end

        out << encode_flags_rle(tt_flags)
        out << x_bytes
        out << y_bytes
        out
      end

      # Encode one axis delta into standard TrueType byte layout. Returns
      # the updated flag value (X bits if short_bit is FLAG_X_SHORT, Y bits
      # if short_bit is FLAG_Y_SHORT).
      def encode_axis_bits(base, out, short_bit:, same_bit:, value:)
        if value.zero?
          base | same_bit
        elsif value.abs <= 255
          flag = base | short_bit
          flag |= same_bit if value.positive?
          out << (value.abs & 0xFF)
          flag
        else
          out << [value & 0xFFFF].pack("n")
          base
        end
      end

      # Run-length encode the flags array per OFF spec: when two or more
      # consecutive flags are identical, emit REPEAT_FLAG followed by count.
      def encode_flags_rle(flags)
        out = String.new(encoding: Encoding::BINARY)
        i = 0
        while i < flags.size
          flag = flags[i]
          count = 1
          while i + count < flags.size && flags[i + count] == flag && count < 255
            count += 1
          end
          if count > 1
            out << (flag | FLAG_REPEAT).chr(Encoding::BINARY)
            out << count.chr(Encoding::BINARY)
            i += count
          else
            out << flag.chr(Encoding::BINARY)
            i += 1
          end
        end
        out
      end

      # Build loca table from accumulated glyph offsets per spec section 5.3.
      def build_loca(offsets)
        if @index_format.zero?
          offsets.map { |o| o / 2 }.pack("n*")
        else
          offsets.pack("N*")
        end
      end
    end
  end
end
