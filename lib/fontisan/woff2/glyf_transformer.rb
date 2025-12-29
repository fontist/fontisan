# frozen_string_literal: true

require "stringio"

module Fontisan
  module Woff2
    # Reconstructs glyf and loca tables from WOFF2 transformed format
    #
    # WOFF2 glyf table transformation splits glyph data into separate streams
    # for better compression. This transformer reconstructs the standard
    # `glyf` and `loca` table formats from the transformed data.
    #
    # Transformation format (Section 5 of WOFF2 spec):
    # - Separate streams for nContour, nPoints, flags, x-coords, y-coords
    # - Variable-length integer encoding (255UInt16)
    # - Composite glyph components stored separately
    #
    # See: https://www.w3.org/TR/WOFF2/#glyf_table_format
    #
    # @example Reconstructing tables
    #   result = GlyfTransformer.reconstruct(transformed_data, num_glyphs)
    #   glyf_data = result[:glyf]
    #   loca_data = result[:loca]
    class GlyfTransformer
      # Glyph flags
      ON_CURVE_POINT = 0x01
      X_SHORT_VECTOR = 0x02
      Y_SHORT_VECTOR = 0x04
      REPEAT_FLAG = 0x08
      X_IS_SAME_OR_POSITIVE_X_SHORT_VECTOR = 0x10
      Y_IS_SAME_OR_POSITIVE_Y_SHORT_VECTOR = 0x20

      # Composite glyph flags
      ARG_1_AND_2_ARE_WORDS = 0x0001
      ARGS_ARE_XY_VALUES = 0x0002
      ROUND_XY_TO_GRID = 0x0004
      WE_HAVE_A_SCALE = 0x0008
      MORE_COMPONENTS = 0x0020
      WE_HAVE_AN_X_AND_Y_SCALE = 0x0040
      WE_HAVE_A_TWO_BY_TWO = 0x0080
      WE_HAVE_INSTRUCTIONS = 0x0100
      USE_MY_METRICS = 0x0200
      OVERLAP_COMPOUND = 0x0400
      HAVE_VARIATIONS = 0x1000 # Variable font variation data follows

      # Reconstruct glyf and loca tables from transformed data
      #
      # @param transformed_data [String] The transformed glyf table data
      # @param num_glyphs [Integer] Number of glyphs from maxp table
      # @param variable_font [Boolean] Whether this is a variable font with variation data
      # @return [Hash] { glyf: String, loca: String }
      # @raise [InvalidFontError] If data is corrupted or invalid
      def self.reconstruct(transformed_data, num_glyphs, variable_font: false)
        io = StringIO.new(transformed_data)

        # Check minimum size for header
        if io.size < 8
          raise InvalidFontError,
                "Transformed glyf data too small: #{io.size} bytes"
        end

        # Read header
        read_uint32(io)
        num_glyphs_in_data = read_uint16(io)
        index_format = read_uint16(io)

        if num_glyphs_in_data != num_glyphs
          raise InvalidFontError,
                "Glyph count mismatch: expected #{num_glyphs}, got #{num_glyphs_in_data}"
        end

        # Read nContour stream
        n_contour_data = read_stream_safely(io, "nContour",
                                            variable_font: variable_font)

        # Read nPoints stream
        n_points_data = read_stream_safely(io, "nPoints",
                                           variable_font: variable_font)

        # Read flag stream
        flag_data = read_stream_safely(io, "flag", variable_font: variable_font)

        # Read glyph stream (coordinates, instructions, composite data)
        glyph_data = read_stream_safely(io, "glyph",
                                        variable_font: variable_font)

        # Read composite stream
        composite_data = read_stream_safely(io, "composite",
                                            variable_font: variable_font)

        # Read bbox stream
        bbox_data = read_stream_safely(io, "bbox", variable_font: variable_font)

        # Read instruction stream
        instruction_data = read_stream_safely(io, "instruction",
                                              variable_font: variable_font)

        # Parse streams
        n_contours = parse_n_contour_stream(StringIO.new(n_contour_data),
                                            num_glyphs)

        # Reconstruct glyphs
        glyphs = reconstruct_glyphs(
          n_contours,
          StringIO.new(n_points_data),
          StringIO.new(flag_data),
          StringIO.new(glyph_data),
          StringIO.new(composite_data),
          StringIO.new(bbox_data),
          StringIO.new(instruction_data),
          variable_font: variable_font,
        )

        # Build glyf and loca tables
        build_tables(glyphs, index_format)
      end

      # Safely read a stream with bounds checking
      #
      # @param io [StringIO] Input stream
      # @param stream_name [String] Name of stream for error messages
      # @param variable_font [Boolean] Whether this is a variable font (allows incomplete streams)
      # @return [String] Stream data (empty if not available)
      def self.read_stream_safely(io, _stream_name, variable_font: false)
        remaining = io.size - io.pos
        if remaining < 4
          # Not enough data for stream size - return empty stream
          return ""
        end

        # Read stream size safely
        size_bytes = io.read(4)
        return "" unless size_bytes && size_bytes.bytesize == 4

        stream_size = size_bytes.unpack1("N")
        remaining = io.size - io.pos

        if remaining < stream_size
          # Stream size extends beyond available data
          # Read what we can
          io.read(remaining) || ""
          # For variable fonts, we may have incomplete streams - just return what we have

        else
          io.read(stream_size) || ""
        end
      end

      # Read variable-length 255UInt16 integer
      #
      # Format from WOFF2 spec:
      # - value < 253: one byte
      # - value == 253: 253 + next uint16
      # - value == 254: 253 * 2 + next uint16
      # - value == 255: 253 * 3 + next uint16
      #
      # @param io [StringIO] Input stream
      # @return [Integer] Decoded value, or 0 if not enough data
      def self.read_255_uint16(io)
        return 0 if io.eof? || (io.size - io.pos) < 1

        code_byte = io.read(1)
        return 0 unless code_byte && code_byte.bytesize == 1

        code = code_byte.unpack1("C")

        case code
        when 255
          return 0 if io.eof? || (io.size - io.pos) < 2

          value_bytes = io.read(2)
          return 0 unless value_bytes && value_bytes.bytesize == 2

          759 + value_bytes.unpack1("n")  # 253 * 3 + value
        when 254
          return 0 if io.eof? || (io.size - io.pos) < 2

          value_bytes = io.read(2)
          return 0 unless value_bytes && value_bytes.bytesize == 2

          506 + value_bytes.unpack1("n")  # 253 * 2 + value
        when 253
          return 0 if io.eof? || (io.size - io.pos) < 2

          value_bytes = io.read(2)
          return 0 unless value_bytes && value_bytes.bytesize == 2

          253 + value_bytes.unpack1("n")
        else
          code
        end
      end

      # Parse nContour stream
      #
      # @param io [StringIO] Input stream
      # @param num_glyphs [Integer] Number of glyphs
      # @return [Array<Integer>] Number of contours per glyph (-1 for composite)
      def self.parse_n_contour_stream(io, num_glyphs)
        n_contours = []
        num_glyphs.times do
          # For variable fonts, stream may be incomplete
          break if io.eof? || (io.size - io.pos) < 2

          value = read_int16(io)
          n_contours << value
        end

        # Pad with zeros if we have fewer contours than glyphs
        while n_contours.size < num_glyphs
          n_contours << 0
        end

        n_contours
      end

      # Reconstruct all glyphs
      #
      # @param n_contours [Array<Integer>] Contour counts
      # @param n_points_io [StringIO] Points stream
      # @param flag_io [StringIO] Flag stream
      # @param glyph_io [StringIO] Glyph data stream
      # @param composite_io [StringIO] Composite glyph stream
      # @param bbox_io [StringIO] Bounding box stream
      # @param instruction_io [StringIO] Instruction stream
      # @param variable_font [Boolean] Whether this is a variable font
      # @return [Array<String>] Reconstructed glyph data
      def self.reconstruct_glyphs(n_contours, n_points_io, flag_io, glyph_io,
                                   composite_io, bbox_io, instruction_io, variable_font: false)
        glyphs = []

        n_contours.each do |num_contours|
          if num_contours.zero?
            # Empty glyph
            glyphs << ""
          elsif num_contours.positive?
            # Simple glyph
            glyphs << reconstruct_simple_glyph(
              num_contours, n_points_io, flag_io,
              glyph_io, bbox_io, instruction_io
            )
          elsif num_contours == -1
            # Composite glyph
            glyphs << reconstruct_composite_glyph(
              composite_io, bbox_io, instruction_io, variable_font: variable_font
            )
          else
            raise InvalidFontError, "Invalid nContours value: #{num_contours}"
          end
        end

        glyphs
      end

      # Reconstruct a simple glyph
      #
      # @param num_contours [Integer] Number of contours
      # @param n_points_io [StringIO] Points stream
      # @param flag_io [StringIO] Flag stream
      # @param glyph_io [StringIO] Glyph data stream
      # @param bbox_io [StringIO] Bounding box stream
      # @param instruction_io [StringIO] Instruction stream
      # @return [String] Glyph data in standard format
      def self.reconstruct_simple_glyph(num_contours, n_points_io, flag_io,
                                        glyph_io, bbox_io, instruction_io)
        # Read end points of contours
        end_pts_of_contours = []
        num_contours.times do
          if end_pts_of_contours.empty?
            end_pts_of_contours << read_255_uint16(n_points_io)
          else
            delta = read_255_uint16(n_points_io)
            end_pts_of_contours << end_pts_of_contours.last + delta + 1
          end
        end

        total_points = end_pts_of_contours.last + 1

        # Read flags
        flags = read_flags(flag_io, total_points)

        # Read coordinates
        x_coordinates = read_coordinates(glyph_io, flags, X_SHORT_VECTOR,
                                         X_IS_SAME_OR_POSITIVE_X_SHORT_VECTOR)
        y_coordinates = read_coordinates(glyph_io, flags, Y_SHORT_VECTOR,
                                         Y_IS_SAME_OR_POSITIVE_Y_SHORT_VECTOR)

        # Read bounding box safely
        bbox_remaining = bbox_io.size - bbox_io.pos
        if bbox_remaining < 8
          # Not enough data, use default bounding box
          x_min = y_min = x_max = y_max = 0
        else
          bbox_bytes = bbox_io.read(8)
          if bbox_bytes && bbox_bytes.bytesize == 8
            x_min, y_min, x_max, y_max = bbox_bytes.unpack("n4")
            # Convert to signed
            x_min = x_min > 0x7FFF ? x_min - 0x10000 : x_min
            y_min = y_min > 0x7FFF ? y_min - 0x10000 : y_min
            x_max = x_max > 0x7FFF ? x_max - 0x10000 : x_max
            y_max = y_max > 0x7FFF ? y_max - 0x10000 : y_max
          else
            x_min = y_min = x_max = y_max = 0
          end
        end

        # Read instructions safely
        instruction_length = 0
        instructions = ""

        inst_remaining = instruction_io.size - instruction_io.pos
        if inst_remaining >= 2
          inst_length_data = read_255_uint16(instruction_io)
          if inst_length_data
            instruction_length = inst_length_data
            if instruction_length.positive?
              inst_remaining = instruction_io.size - instruction_io.pos
              instructions = if inst_remaining >= instruction_length
                               instruction_io.read(instruction_length) || ""
                             else
                               # Read what we can
                               instruction_io.read(inst_remaining) || ""
                             end
            end
          end
        end

        # Build glyph data in standard format
        build_simple_glyph_data(num_contours, x_min, y_min, x_max, y_max,
                                end_pts_of_contours, instructions, flags,
                                x_coordinates, y_coordinates)
      end

      # Reconstruct a composite glyph
      #
      # @param composite_io [StringIO] Composite stream
      # @param bbox_io [StringIO] Bounding box stream
      # @param instruction_io [StringIO] Instruction stream
      # @param variable_font [Boolean] Whether this is a variable font
      # @return [String] Glyph data in standard format
      def self.reconstruct_composite_glyph(composite_io, bbox_io,
instruction_io, variable_font: false)
        # Track available bytes to prevent EOF errors
        composite_size = composite_io.size - composite_io.pos

        # Validate minimum size (at least flags + glyph_index + args)
        return "" if composite_size < 8

        # Read bounding box safely
        bbox_remaining = bbox_io.size - bbox_io.pos
        if bbox_remaining < 8
          # Not enough data for bounding box, return empty glyph
          return ""
        end

        bbox_bytes = bbox_io.read(8)
        unless bbox_bytes && bbox_bytes.bytesize == 8
          return ""
        end

        x_min, y_min, x_max, y_max = bbox_bytes.unpack("n4")
        # Convert to signed
        x_min = x_min > 0x7FFF ? x_min - 0x10000 : x_min
        y_min = y_min > 0x7FFF ? y_min - 0x10000 : y_min
        x_max = x_max > 0x7FFF ? x_max - 0x10000 : x_max
        y_max = y_max > 0x7FFF ? y_max - 0x10000 : y_max

        # Read composite data
        composite_data = +""
        has_instructions = false
        has_variations = false

        loop do
          # Check if we have enough bytes for flags and glyph_index
          remaining = composite_io.size - composite_io.pos
          break if composite_io.eof? || remaining < 4

          # Read flags and glyph_index safely
          component_header = composite_io.read(4)
          break unless component_header && component_header.bytesize == 4

          flags, glyph_index = component_header.unpack("n2")

          # Write flags and index
          composite_data << [flags].pack("n")
          composite_data << [glyph_index].pack("n")

          # Read arguments (depend on flags)
          remaining = composite_io.size - composite_io.pos
          if (flags & ARG_1_AND_2_ARE_WORDS).zero?
            break if composite_io.eof? || remaining < 2

            arg_bytes = composite_io.read(2)
            break unless arg_bytes && arg_bytes.bytesize == 2

            arg1, arg2 = arg_bytes.unpack("c2")
            composite_data << [arg1, arg2].pack("c2")
          else
            break if composite_io.eof? || remaining < 4

            arg_bytes = composite_io.read(4)
            break unless arg_bytes && arg_bytes.bytesize == 4

            arg1, arg2 = arg_bytes.unpack("n2")
            # Convert to signed
            arg1 = arg1 > 0x7FFF ? arg1 - 0x10000 : arg1
            arg2 = arg2 > 0x7FFF ? arg2 - 0x10000 : arg2
            composite_data << [arg1, arg2].pack("n2")
          end

          # Read transformation matrix (depends on flags) with bounds checking
          if (flags & WE_HAVE_A_SCALE) != 0
            remaining = composite_io.size - composite_io.pos
            break if composite_io.eof? || remaining < 2

            scale_bytes = composite_io.read(2)
            break unless scale_bytes && scale_bytes.bytesize == 2

            scale = scale_bytes.unpack1("n")
            composite_data << [scale].pack("n")
          elsif (flags & WE_HAVE_AN_X_AND_Y_SCALE) != 0
            remaining = composite_io.size - composite_io.pos
            break if composite_io.eof? || remaining < 4

            scale_bytes = composite_io.read(4)
            break unless scale_bytes && scale_bytes.bytesize == 4

            x_scale, y_scale = scale_bytes.unpack("n2")
            composite_data << [x_scale, y_scale].pack("n2")
          elsif (flags & WE_HAVE_A_TWO_BY_TWO) != 0
            remaining = composite_io.size - composite_io.pos
            break if composite_io.eof? || remaining < 8

            matrix_bytes = composite_io.read(8)
            break unless matrix_bytes && matrix_bytes.bytesize == 8

            x_scale, scale01, scale10, y_scale = matrix_bytes.unpack("n4")
            composite_data << [x_scale, scale01, scale10, y_scale].pack("n4")
          end

          # Check for variable font variation data
          # Only parse if this is a variable font and the flag is set
          if variable_font && (flags & HAVE_VARIATIONS) != 0
            has_variations = true
            # Read tuple variation count and data
            remaining = composite_io.size - composite_io.pos
            if !composite_io.eof? && remaining >= 2
              # Read tuple count safely
              tuple_bytes = composite_io.read(2)
              if tuple_bytes && tuple_bytes.bytesize == 2
                tuple_count = tuple_bytes.unpack1("n")
                composite_data << [tuple_count].pack("n")

                # Each tuple has variation data - read and preserve it
                tuple_count.times do
                  remaining = composite_io.size - composite_io.pos
                  break if composite_io.eof? || remaining < 4

                  # Read variation data (2 int16 values per tuple)
                  var_bytes = composite_io.read(4)
                  break unless var_bytes && var_bytes.bytesize == 4

                  var1, var2 = var_bytes.unpack("n2")
                  # Convert to signed if needed
                  var1 = var1 > 0x7FFF ? var1 - 0x10000 : var1
                  var2 = var2 > 0x7FFF ? var2 - 0x10000 : var2
                  composite_data << [var1, var2].pack("n2")
                end
              end
            end
          end

          has_instructions = (flags & WE_HAVE_INSTRUCTIONS) != 0

          break if (flags & MORE_COMPONENTS).zero?
        end

        # Add instructions if present
        instructions = +""
        if has_instructions
          # Read instruction length safely
          remaining = instruction_io.size - instruction_io.pos
          if !instruction_io.eof? && remaining >= 2
            length_bytes = instruction_io.read(2)
            if length_bytes && length_bytes.bytesize == 2
              instruction_length = length_bytes.unpack1("n")
              if instruction_length.positive?
                remaining = instruction_io.size - instruction_io.pos
                instructions = if remaining >= instruction_length
                                 instruction_io.read(instruction_length) || ""
                               else
                                 # Read what we can
                                 instruction_io.read(remaining) || ""
                               end
              end
            end
          end
        end

        # Build composite glyph data
        data = +""
        data << [-1].pack("n") # numberOfContours = -1
        data << [x_min, y_min, x_max, y_max].pack("n4")
        data << composite_data
        data << [instructions.bytesize].pack("n") if has_instructions
        data << instructions if has_instructions

        data
      end

      # Read flags with repeat handling
      #
      # @param io [StringIO] Flag stream
      # @param count [Integer] Number of flags to read
      # @return [Array<Integer>] Flag values
      def self.read_flags(io, count)
        flags = []

        while flags.size < count
          # EOF protection for variable fonts
          break if io.eof? || (io.size - io.pos) < 1

          flag = read_uint8(io)
          flags << flag

          if (flag & REPEAT_FLAG) != 0
            break if io.eof? || (io.size - io.pos) < 1

            repeat_count = read_uint8(io)
            repeat_count.times { flags << flag }
          end
        end

        # Pad with zero flags if needed
        while flags.size < count
          flags << 0
        end

        flags
      end

      # Read coordinates
      #
      # @param io [StringIO] Glyph stream
      # @param flags [Array<Integer>] Flag values
      # @param short_flag [Integer] Flag bit for short vector
      # @param same_or_positive_flag [Integer] Flag bit for same/positive
      # @return [Array<Integer>] Coordinate values
      def self.read_coordinates(io, flags, short_flag, same_or_positive_flag)
        coords = []
        value = 0

        flags.each do |flag|
          # EOF protection
          if (flag & short_flag) != 0
            break if io.eof? || (io.size - io.pos) < 1

            # Short vector (one byte)
            delta = read_uint8(io)
            delta = -delta if (flag & same_or_positive_flag).zero?
          elsif (flag & same_or_positive_flag) != 0
            # Same as previous (delta = 0)
            delta = 0
          else
            break if io.eof? || (io.size - io.pos) < 2

            # Long vector (two bytes, signed)
            delta = read_int16(io)
          end

          value += delta
          coords << value
        end

        # Pad with last value if needed
        last_val = coords.last || 0
        while coords.size < flags.size
          coords << last_val
        end

        coords
      end

      # Build simple glyph data in standard format
      #
      # @return [String] Glyph data
      def self.build_simple_glyph_data(num_contours, x_min, y_min, x_max, y_max,
                                       end_pts, instructions, flags, x_coords, y_coords)
        data = +""
        data << [num_contours].pack("n")
        data << [x_min, y_min, x_max, y_max].pack("n4")

        end_pts.each { |pt| data << [pt].pack("n") }

        data << [instructions.bytesize].pack("n")
        data << instructions

        flags.each { |flag| data << [flag].pack("C") }

        # Write x-coordinates
        prev_x = 0
        x_coords.each do |x|
          delta = x - prev_x
          prev_x = x

          data << if delta.abs <= 255
                    [delta.abs].pack("C")
                  else
                    [delta].pack("n")
                  end
        end

        # Write y-coordinates
        prev_y = 0
        y_coords.each do |y|
          delta = y - prev_y
          prev_y = y

          data << if delta.abs <= 255
                    [delta.abs].pack("C")
                  else
                    [delta].pack("n")
                  end
        end

        data
      end

      # Build glyf and loca tables
      #
      # @param glyphs [Array<String>] Glyph data
      # @param index_format [Integer] Loca format (0 = short, 1 = long)
      # @return [Hash] { glyf: String, loca: String }
      def self.build_tables(glyphs, index_format)
        glyf_data = +""
        loca_offsets = [0]

        glyphs.each do |glyph|
          glyf_data << glyph

          # Add padding to 4-byte boundary
          padding = (4 - (glyph.bytesize % 4)) % 4
          glyf_data << ("\x00" * padding)

          loca_offsets << glyf_data.bytesize
        end

        # Build loca table
        loca_data = +""
        if index_format.zero?
          # Short format (divide offsets by 2)
          loca_offsets.each do |offset|
            loca_data << [offset / 2].pack("n")
          end
        else
          # Long format
          loca_offsets.each do |offset|
            loca_data << [offset].pack("N")
          end
        end

        { glyf: glyf_data, loca: loca_data }
      end

      # Helper methods for reading binary data

      def self.read_uint8(io)
        io.read(1)&.unpack1("C") || raise(EOFError, "Unexpected end of stream")
      end

      def self.read_int8(io)
        io.read(1)&.unpack1("c") || raise(EOFError, "Unexpected end of stream")
      end

      def self.read_uint16(io)
        io.read(2)&.unpack1("n") || raise(EOFError, "Unexpected end of stream")
      end

      def self.read_int16(io)
        value = read_uint16(io)
        value > 0x7FFF ? value - 0x10000 : value
      end

      def self.read_uint32(io)
        io.read(4)&.unpack1("N") || raise(EOFError, "Unexpected end of stream")
      end

      def self.read_f2dot14(io)
        read_uint16(io)
      end
    end
  end
end
