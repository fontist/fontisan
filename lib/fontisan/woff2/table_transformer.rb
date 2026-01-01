# frozen_string_literal: true

module Fontisan
  module Woff2
    # Table transformer for WOFF2 encoding
    #
    # [`Woff2::TableTransformer`](lib/fontisan/woff2/table_transformer.rb)
    # handles table transformations that improve compression in WOFF2.
    # The WOFF2 spec defines transformations for glyf/loca and hmtx tables.
    #
    # Transformations implemented:
    # - glyf/loca: Combined stream format with specialized encoding
    # - hmtx: Delta encoding with 255UInt16 compression
    #
    # Reference: https://www.w3.org/TR/WOFF2/#table_tranforms
    #
    # @example Transform tables for WOFF2
    #   transformer = TableTransformer.new(font)
    #   glyf_data = transformer.transform_table("glyf")
    class TableTransformer
      # @return [Object] Font object with table access
      attr_reader :font

      # Initialize transformer with font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      def initialize(font)
        @font = font
      end

      # Transform a table for WOFF2 encoding
      #
      # @param tag [String] Table tag
      # @return [String, nil] Transformed table data
      def transform_table(tag)
        case tag
        when "glyf"
          transform_glyf
        when "loca"
          transform_loca
        when "hmtx"
          transform_hmtx
        else
          # No transformation, return original data
          get_table_data(tag)
        end
      end

      # Check if a table can be transformed
      #
      # @param tag [String] Table tag
      # @return [Boolean] True if table supports transformation
      def transformable?(tag)
        %w[glyf loca hmtx].include?(tag)
      end

      # Determine transformation version for a table
      #
      # @param tag [String] Table tag
      # @return [Integer] Transformation version
      def transformation_version(tag)
        case tag
        when "glyf", "loca"
          Directory::TRANSFORM_GLYF_LOCA
        when "hmtx"
          Directory::TRANSFORM_HMTX
        else
          Directory::TRANSFORM_NONE
        end
      end

      private

      # Transform glyf table
      #
      # Implements WOFF2 glyf transformation by splitting glyph data into 8 streams:
      # 1. nContour stream - number of contours per glyph
      # 2. nPoints stream - end points of contours (255UInt16)
      # 3. Flag stream - point flags with run-length encoding
      # 4. Glyph stream - x/y coordinates (delta-encoded)
      # 5. Composite stream - composite glyph data
      # 6. Bbox stream - bounding boxes
      # 7. Instruction stream - hinting instructions
      # 8. Composite bbox stream - not used in current implementation
      #
      # @return [String] Transformed glyf data
      def transform_glyf
        glyf_data = get_table_data("glyf")
        loca_data = get_table_data("loca")

        return glyf_data unless glyf_data && loca_data

        # Get number of glyphs from maxp table
        maxp_table = font.table("maxp")
        return glyf_data unless maxp_table

        num_glyphs = maxp_table.num_glyphs

        # Get head table to determine loca format
        head_table = font.table("head")
        return glyf_data unless head_table

        index_format = head_table.index_to_loc_format

        # Parse glyphs from glyf/loca tables
        glyphs = parse_glyphs(glyf_data, loca_data, num_glyphs, index_format)

        # Build transformed streams
        build_transformed_glyf(glyphs, num_glyphs, index_format)
      end

      # Transform loca table
      #
      # In WOFF2, loca is combined with glyf during transformation.
      # Return nil to indicate loca should be omitted from output.
      #
      # @return [nil]
      def transform_loca
        # loca is combined into transformed glyf, so return nil
        nil
      end

      # Transform hmtx table
      #
      # Implements WOFF2 hmtx transformation using delta encoding and 255UInt16.
      #
      # @return [String] Transformed hmtx data
      def transform_hmtx
        hmtx_data = get_table_data("hmtx")
        return hmtx_data unless hmtx_data

        # Get required metadata
        hhea_table = font.table("hhea")
        maxp_table = font.table("maxp")
        return hmtx_data unless hhea_table && maxp_table

        num_h_metrics = hhea_table.number_of_h_metrics
        num_glyphs = maxp_table.num_glyphs

        # Parse hmtx table
        advance_widths, lsbs = parse_hmtx_table(hmtx_data, num_h_metrics, num_glyphs)

        # Build transformed hmtx table
        build_transformed_hmtx(advance_widths, lsbs, num_h_metrics, num_glyphs)
      end

      # Get raw table data from font
      #
      # @param tag [String] Table tag
      # @return [String, nil] Table data or nil if not found
      def get_table_data(tag)
        return nil unless font.respond_to?(:table_data)

        font.table_data[tag]
      end

      # Parse glyphs from glyf and loca tables
      #
      # @param glyf_data [String] glyf table data
      # @param loca_data [String] loca table data
      # @param num_glyphs [Integer] Number of glyphs
      # @param index_format [Integer] Loca format (0=short, 1=long)
      # @return [Array<Hash>] Array of glyph hashes
      def parse_glyphs(glyf_data, loca_data, num_glyphs, index_format)
        # Parse loca offsets
        offsets = parse_loca_offsets(loca_data, num_glyphs, index_format)

        glyphs = []
        num_glyphs.times do |i|
          start_offset = offsets[i]
          end_offset = offsets[i + 1]

          if start_offset == end_offset
            # Empty glyph
            glyphs << { type: :empty, data: nil }
          else
            glyph_data = glyf_data[start_offset...end_offset]
            glyphs << parse_glyph(glyph_data)
          end
        end

        glyphs
      end

      # Parse loca table to get glyph offsets
      #
      # @param loca_data [String] loca table data
      # @param num_glyphs [Integer] Number of glyphs
      # @param index_format [Integer] Format (0=short, 1=long)
      # @return [Array<Integer>] Glyph offsets
      def parse_loca_offsets(loca_data, num_glyphs, index_format)
        offsets = []
        io = StringIO.new(loca_data)

        (num_glyphs + 1).times do
          offsets << if index_format.zero?
                       # Short format (uint16, actual offset = value * 2)
                       (io.read(2)&.unpack1("n") || 0) * 2
                     else
                       # Long format (uint32)
                       io.read(4)&.unpack1("N") || 0
                     end
        end

        offsets
      end

      # Parse a single glyph
      #
      # @param data [String] Glyph data
      # @return [Hash] Glyph information
      def parse_glyph(data)
        io = StringIO.new(data)

        num_contours = io.read(2)&.unpack1("n") || 0
        num_contours = num_contours > 0x7FFF ? num_contours - 0x10000 : num_contours

        if num_contours.zero?
          { type: :empty, data: nil }
        elsif num_contours.positive?
          parse_simple_glyph(io, num_contours, data)
        else
          parse_composite_glyph(io, data)
        end
      end

      # Parse simple glyph
      #
      # @param io [StringIO] Data stream
      # @param num_contours [Integer] Number of contours
      # @param data [String] Full glyph data
      # @return [Hash] Glyph information
      def parse_simple_glyph(io, num_contours, _data)
        # Read bounding box
        x_min = read_int16(io)
        y_min = read_int16(io)
        x_max = read_int16(io)
        y_max = read_int16(io)

        # Read end points of contours
        end_pts = []
        num_contours.times { end_pts << io.read(2)&.unpack1("n") }

        total_points = end_pts.last + 1

        # Read instruction length and instructions
        inst_length = io.read(2)&.unpack1("n") || 0
        instructions = inst_length.positive? ? io.read(inst_length) : ""

        # Read flags
        flags = []
        while flags.size < total_points
          flag = io.read(1)&.unpack1("C")
          flags << flag

          if (flag & 0x08) != 0 # REPEAT_FLAG
            repeat_count = io.read(1)&.unpack1("C")
            repeat_count.times { flags << flag }
          end
        end

        # Read x-coordinates
        x_coords = read_coordinates(io, flags, 0x02, 0x10)

        # Read y-coordinates
        y_coords = read_coordinates(io, flags, 0x04, 0x20)

        {
          type: :simple,
          num_contours: num_contours,
          bbox: [x_min, y_min, x_max, y_max],
          end_pts: end_pts,
          instructions: instructions,
          flags: flags,
          x_coords: x_coords,
          y_coords: y_coords,
        }
      end

      # Parse composite glyph
      #
      # @param io [StringIO] Data stream
      # @param data [String] Full glyph data
      # @return [Hash] Glyph information
      def parse_composite_glyph(io, data)
        # Read bounding box at start
        x_min = read_int16(io)
        y_min = read_int16(io)
        x_max = read_int16(io)
        y_max = read_int16(io)

        # Read composite components
        components = []
        instructions = ""

        loop do
          start_pos = io.pos
          flags = io.read(2)&.unpack1("n")
          glyph_index = io.read(2)&.unpack1("n")

          component = { flags: flags, glyph_index: glyph_index }

          # Read arguments based on flags
          if (flags & 0x0001).zero?
            arg1 = io.read(1)&.unpack1("c")
            arg2 = io.read(1)&.unpack1("c")
          else # ARG_1_AND_2_ARE_WORDS
            arg1 = read_int16(io)
            arg2 = read_int16(io)
          end
          component[:arg1] = arg1
          component[:arg2] = arg2

          # Read transformation based on flags
          if (flags & 0x0008) != 0 # WE_HAVE_A_SCALE
            component[:scale] = io.read(2)&.unpack1("n")
          elsif (flags & 0x0040) != 0 # WE_HAVE_AN_X_AND_Y_SCALE
            component[:x_scale] = io.read(2)&.unpack1("n")
            component[:y_scale] = io.read(2)&.unpack1("n")
          elsif (flags & 0x0080) != 0 # WE_HAVE_A_TWO_BY_TWO
            component[:x_scale] = io.read(2)&.unpack1("n")
            component[:scale01] = io.read(2)&.unpack1("n")
            component[:scale10] = io.read(2)&.unpack1("n")
            component[:y_scale] = io.read(2)&.unpack1("n")
          end

          # Store raw component data
          end_pos = io.pos
          component[:raw_data] = data[start_pos...end_pos]

          components << component

          (flags & 0x0100) != 0

          break if (flags & 0x0020).zero? # MORE_COMPONENTS
        end

        # Read instructions if present
        if components.last && (components.last[:flags] & 0x0100) != 0
          inst_length = io.read(2)&.unpack1("n") || 0
          instructions = inst_length.positive? ? io.read(inst_length) : ""
        end

        {
          type: :composite,
          bbox: [x_min, y_min, x_max, y_max],
          components: components,
          instructions: instructions,
        }
      end

      # Parse hmtx table
      #
      # @param hmtx_data [String] hmtx table data
      # @param num_h_metrics [Integer] Number of hMetric entries
      # @param num_glyphs [Integer] Total number of glyphs
      # @return [Array<Array<Integer>, Array<Integer>>] [advance_widths, lsbs]
      def parse_hmtx_table(hmtx_data, num_h_metrics, num_glyphs)
        io = StringIO.new(hmtx_data)
        advance_widths = []
        lsbs = []

        # Read longHorMetric array (advance width + LSB pairs)
        num_h_metrics.times do
          advance_width = io.read(2)&.unpack1("n") || 0
          lsb = read_int16(io)

          advance_widths << advance_width
          lsbs << lsb
        end

        # Read remaining LSB values (these glyphs share last advance width)
        (num_glyphs - num_h_metrics).times do
          lsb = read_int16(io)
          lsbs << lsb
        end

        [advance_widths, lsbs]
      end

      # Build transformed hmtx table
      #
      # Uses proportional encoding with deltas for advance widths
      # and explicit LSB values.
      #
      # @param advance_widths [Array<Integer>] Advance widths
      # @param lsbs [Array<Integer>] Left side bearings
      # @param num_h_metrics [Integer] Number of hMetric entries
      # @param num_glyphs [Integer] Total number of glyphs
      # @return [String] Transformed hmtx data
      def build_transformed_hmtx(advance_widths, lsbs, num_h_metrics, num_glyphs)
        data = String.new(encoding: Encoding::BINARY)

        # Flags: Use proportional encoding (not explicit) and explicit LSBs
        # 0x00 = proportional advance widths
        # 0x02 = explicit LSB values
        flags = 0x02
        data << [flags].pack("C")

        # Write advance widths using proportional encoding
        # First advance width is explicit
        data << encode_255_uint16(advance_widths[0])

        # Remaining advance widths as deltas
        (1...num_h_metrics).each do |i|
          delta = advance_widths[i] - advance_widths[i - 1]
          data << [delta].pack("n") # int16 delta
        end

        # Write all LSB values explicitly
        num_glyphs.times do |i|
          lsb = lsbs[i] || 0
          data << [lsb].pack("n") # int16 LSB
        end

        data
      end

      # Read coordinates from glyph data
      #
      # @param io [StringIO] Data stream
      # @param flags [Array<Integer>] Point flags
      # @param short_flag [Integer] Flag for short vector
      # @param same_or_pos_flag [Integer] Flag for same/positive
      # @return [Array<Integer>] Coordinates
      def read_coordinates(io, flags, short_flag, same_or_pos_flag)
        coords = []
        value = 0

        flags.each do |flag|
          if (flag & short_flag) != 0
            delta = io.read(1)&.unpack1("C")
            delta = -delta if (flag & same_or_pos_flag).zero?
          elsif (flag & same_or_pos_flag) != 0
            delta = 0
          else
            delta = read_int16(io)
          end

          value += delta
          coords << value
        end

        coords
      end

      # Build transformed glyf data from parsed glyphs
      #
      # @param glyphs [Array<Hash>] Parsed glyphs
      # @param num_glyphs [Integer] Number of glyphs
      # @param index_format [Integer] Loca format
      # @return [String] Transformed glyf data
      def build_transformed_glyf(glyphs, num_glyphs, index_format)
        # Build 8 streams
        n_contour_stream = String.new(encoding: Encoding::BINARY)
        n_points_stream = String.new(encoding: Encoding::BINARY)
        flag_stream = String.new(encoding: Encoding::BINARY)
        glyph_stream = String.new(encoding: Encoding::BINARY)
        composite_stream = String.new(encoding: Encoding::BINARY)
        bbox_stream = String.new(encoding: Encoding::BINARY)
        instruction_stream = String.new(encoding: Encoding::BINARY)

        glyphs.each do |glyph|
          case glyph[:type]
          when :empty
            n_contour_stream << [0].pack("n")
          when :simple
            n_contour_stream << [glyph[:num_contours]].pack("n")

            # Write end points as deltas (255UInt16)
            prev_pt = -1
            glyph[:end_pts].each do |pt|
              delta = pt - prev_pt - 1
              n_points_stream << encode_255_uint16(delta)
              prev_pt = pt
            end

            # Write flags with run-length encoding
            write_flags_rle(flag_stream, glyph[:flags])

            # Write coordinates as deltas
            write_coordinates(glyph_stream, glyph[:x_coords])
            write_coordinates(glyph_stream, glyph[:y_coords])

            # Write bounding box
            glyph[:bbox].each { |v| bbox_stream << [v].pack("n") }

            # Write instructions
            instruction_stream << encode_255_uint16(glyph[:instructions].bytesize)
            instruction_stream << glyph[:instructions] if glyph[:instructions].bytesize.positive?

          when :composite
            n_contour_stream << [-1].pack("n")

            # Write all component data
            glyph[:components].each { |c| composite_stream << c[:raw_data] }

            # Write bounding box
            glyph[:bbox].each { |v| bbox_stream << [v].pack("n") }

            # Write instructions if present
            if glyph[:instructions].bytesize.positive?
              instruction_stream << [glyph[:instructions].bytesize].pack("n")
              instruction_stream << glyph[:instructions]
            end
          end
        end

        # Build header and combine streams
        data = String.new(encoding: Encoding::BINARY)
        data << [0].pack("N") # version
        data << [num_glyphs].pack("n")
        data << [index_format].pack("n")

        # Write stream sizes and data
        [n_contour_stream, n_points_stream, flag_stream, glyph_stream,
         composite_stream, bbox_stream, instruction_stream, ""].each do |stream|
          data << [stream.bytesize].pack("N")
          data << stream
        end

        data
      end

      # Write flags with run-length encoding
      #
      # @param stream [String] Output stream
      # @param flags [Array<Integer>] Flags to encode
      def write_flags_rle(stream, flags)
        i = 0
        while i < flags.size
          flag = flags[i]
          count = 1

          # Count repeats
          while i + count < flags.size && flags[i + count] == flag && count < 255
            count += 1
          end

          if count > 1
            stream << [flag | 0x08].pack("C") # Set REPEAT_FLAG
            stream << [count - 1].pack("C") # Repeat count (not including first)
            i += count
          else
            stream << [flag].pack("C")
            i += 1
          end
        end
      end

      # Write coordinates as deltas
      #
      # @param stream [String] Output stream
      # @param coords [Array<Integer>] Coordinates
      def write_coordinates(stream, coords)
        prev = 0
        coords.each do |coord|
          delta = coord - prev

          stream << if delta.abs <= 255
                      [delta.abs].pack("C")
                    else
                      [delta].pack("n")
                    end

          prev = coord
        end
      end

      # Encode 255UInt16 value
      #
      # @param value [Integer] Value to encode
      # @return [String] Encoded bytes
      def encode_255_uint16(value)
        if value < 253
          [value].pack("C")
        elsif value < 506
          [253, value - 253].pack("CC")
        elsif value < 65536
          [254].pack("C") + [value].pack("n")
        else
          [255].pack("C") + [value - 506].pack("n")
        end
      end

      # Read signed 16-bit integer
      #
      # @param io [StringIO] Input stream
      # @return [Integer] Signed value
      def read_int16(io)
        value = io.read(2)&.unpack1("n") || 0
        value > 0x7FFF ? value - 0x10000 : value
      end
    end
  end
end
