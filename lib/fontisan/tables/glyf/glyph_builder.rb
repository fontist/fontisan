# frozen_string_literal: true

require_relative "../../models/outline"
require_relative "curve_converter"

module Fontisan
  module Tables
    # Builds binary TrueType glyph data from universal outline representation
    #
    # [`GlyphBuilder`](lib/fontisan/tables/glyf/glyph_builder.rb) converts the format-agnostic
    # [`Outline`](lib/fontisan/models/outline.rb) model into binary TrueType glyph format.
    # It handles both simple and compound glyphs with proper encoding:
    #
    # **Simple Glyphs**:
    # - Converts universal outline to TrueType contours
    # - Uses [`CurveConverter`](lib/fontisan/tables/glyf/curve_converter.rb) for cubic→quadratic conversion
    # - Delta-encodes coordinates for compact storage
    # - Applies flag compression with run-length encoding
    # - Calculates accurate bounding box
    #
    # **Compound Glyphs**:
    # - Encodes component references
    # - Supports transformation matrices
    # - Handles positioning via points or offsets
    #
    # @example Building a simple glyph from outline
    #   outline = Fontisan::Models::Outline.new(...)
    #   binary_data = Fontisan::Tables::GlyphBuilder.build_simple_glyph(outline)
    #
    # @example Building a compound glyph
    #   components = [
    #     { glyph_index: 10, x_offset: 100, y_offset: 0 },
    #     { glyph_index: 20, x_offset: 300, y_offset: 0 }
    #   ]
    #   bbox = { x_min: 0, y_min: 0, x_max: 500, y_max: 700 }
    #   binary_data = Fontisan::Tables::GlyphBuilder.build_compound_glyph(components, bbox)
    class GlyphBuilder
      # Flag constants (matching SimpleGlyph)
      ON_CURVE_POINT = 0x01
      X_SHORT_VECTOR = 0x02
      Y_SHORT_VECTOR = 0x04
      REPEAT_FLAG = 0x08
      X_IS_SAME_OR_POSITIVE_X_SHORT = 0x10
      Y_IS_SAME_OR_POSITIVE_Y_SHORT = 0x20

      # Component flag constants (matching CompoundGlyph)
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

      # Build a simple TrueType glyph from universal outline
      #
      # Converts the universal outline to TrueType format with:
      # - Quadratic curves (cubic curves converted via [`CurveConverter`](lib/fontisan/tables/glyf/curve_converter.rb))
      # - Delta-encoded coordinates
      # - Flag compression
      # - Accurate bounding box
      #
      # @param outline [Fontisan::Models::Outline] Universal outline
      # @param instructions [String] Optional TrueType instructions (default: empty)
      # @return [String] Binary glyph data
      # @raise [ArgumentError] If outline is invalid or empty
      def self.build_simple_glyph(outline, instructions: "".b)
        raise ArgumentError, "outline cannot be nil" if outline.nil?
        raise ArgumentError, "outline must be Outline" unless outline.is_a?(Fontisan::Models::Outline)
        raise ArgumentError, "outline cannot be empty" if outline.empty?

        # Convert outline to TrueType contours
        contours = outline.to_truetype_contours
        raise ArgumentError, "no contours in outline" if contours.empty?

        # Calculate bounding box from contours
        bbox = calculate_bounding_box(contours)

        # Build binary data
        build_simple_glyph_data(contours, bbox, instructions)
      end

      # Build a compound TrueType glyph
      #
      # Creates a compound glyph by referencing other glyphs with optional
      # transformations. Each component can specify positioning and scaling.
      #
      # @param components [Array<Hash>] Component descriptions
      #   Each component hash can contain:
      #   - `:glyph_index` (Integer, required): Referenced glyph ID
      #   - `:x_offset` (Integer): X offset (default: 0)
      #   - `:y_offset` (Integer): Y offset (default: 0)
      #   - `:scale` (Float): Uniform scale (optional)
      #   - `:scale_x` (Float): X-axis scale (optional)
      #   - `:scale_y` (Float): Y-axis scale (optional)
      #   - `:scale_01` (Float): Matrix element (0,1) (optional)
      #   - `:scale_10` (Float): Matrix element (1,0) (optional)
      #   - `:use_my_metrics` (Boolean): Use component's metrics (default: false)
      #   - `:overlap` (Boolean): Mark as overlapping (default: false)
      # @param bbox [Hash] Bounding box {:x_min, :y_min, :x_max, :y_max}
      # @param instructions [String] Optional TrueType instructions (default: empty)
      # @return [String] Binary glyph data
      # @raise [ArgumentError] If parameters are invalid
      def self.build_compound_glyph(components, bbox, instructions: "".b)
        raise ArgumentError, "components cannot be nil" if components.nil?
        raise ArgumentError, "components must be Array" unless components.is_a?(Array)
        raise ArgumentError, "components cannot be empty" if components.empty?

        validate_bbox!(bbox)

        build_compound_glyph_data(components, bbox, instructions)
      end

      private_class_method def self.build_simple_glyph_data(contours, bbox, instructions)
        num_contours = contours.length

        # Build endPtsOfContours array
        end_pts_of_contours = []
        total_points = 0
        contours.each do |contour|
          total_points += contour.length
          end_pts_of_contours << (total_points - 1)
        end

        # Flatten all points
        all_points = contours.flatten

        # Encode flags and coordinates
        flags_data, x_coords_data, y_coords_data = encode_coordinates(all_points)

        # Build binary data
        data = (+"").force_encoding(Encoding::BINARY)

        # Header (10 bytes)
        data << [num_contours].pack("n") # numberOfContours
        data << [bbox[:x_min], bbox[:y_min], bbox[:x_max], bbox[:y_max]].pack("n4")

        # endPtsOfContours
        data << end_pts_of_contours.pack("n*")

        # Instructions
        data << [instructions.bytesize].pack("n")
        data << instructions if instructions.bytesize.positive?

        # Flags
        data << flags_data

        # Coordinates
        data << x_coords_data
        data << y_coords_data

        data
      end

      private_class_method def self.build_compound_glyph_data(components, bbox, instructions)
        data = (+"").force_encoding(Encoding::BINARY)

        # Header (10 bytes) - numberOfContours = -1 for compound
        data << [-1].pack("n") # Use signed pack, will convert to 0xFFFF
        data << [bbox[:x_min], bbox[:y_min], bbox[:x_max], bbox[:y_max]].pack("n4")

        # Encode components
        has_instructions = instructions.bytesize.positive?
        components.each_with_index do |component, index|
          is_last = (index == components.length - 1)
          component_data = encode_component(component, is_last, has_instructions)
          data << component_data
        end

        # Instructions (if any)
        if has_instructions
          data << [instructions.bytesize].pack("n")
          data << instructions
        end

        data
      end

      private_class_method def self.encode_component(component, is_last, has_instructions)
        validate_component!(component)

        glyph_index = component[:glyph_index]
        x_offset = component[:x_offset] || 0
        y_offset = component[:y_offset] || 0

        # Build flags
        flags = ARGS_ARE_XY_VALUES # Always use x,y offsets

        # Determine if we need 16-bit arguments
        if x_offset.abs > 127 || y_offset.abs > 127
          flags |= ARG_1_AND_2_ARE_WORDS
        end

        # Add transformation flags
        if component[:scale_01] || component[:scale_10]
          # 2x2 matrix
          flags |= WE_HAVE_A_TWO_BY_TWO
        elsif component[:scale_x] && component[:scale_y]
          # Separate x,y scale
          flags |= WE_HAVE_AN_X_AND_Y_SCALE
        elsif component[:scale]
          # Uniform scale
          flags |= WE_HAVE_A_SCALE
        end

        # Add more components flag if not last
        flags |= MORE_COMPONENTS unless is_last

        # Add instructions flag if last and has instructions
        flags |= WE_HAVE_INSTRUCTIONS if is_last && has_instructions

        # Add optional flags
        flags |= USE_MY_METRICS if component[:use_my_metrics]
        flags |= OVERLAP_COMPOUND if component[:overlap]

        # Build binary data
        data = (+"").force_encoding(Encoding::BINARY)
        data << [flags, glyph_index].pack("n2")

        # Encode arguments
        data << if (flags & ARG_1_AND_2_ARE_WORDS).zero?
                  # 8-bit signed
                  [x_offset, y_offset].pack("c2")
                else
                  # 16-bit signed
                  [x_offset, y_offset].pack("n2")
                end

        # Encode transformation
        if (flags & WE_HAVE_A_TWO_BY_TWO) != 0
          # 2x2 matrix (4 F2DOT14 values)
          scale_x = component[:scale_x] || 1.0
          scale_y = component[:scale_y] || 1.0
          scale_01 = component[:scale_01] || 0.0
          scale_10 = component[:scale_10] || 0.0
          data << [
            float_to_f2dot14(scale_x),
            float_to_f2dot14(scale_01),
            float_to_f2dot14(scale_10),
            float_to_f2dot14(scale_y),
          ].pack("n4")
        elsif (flags & WE_HAVE_AN_X_AND_Y_SCALE) != 0
          # Separate x,y scale (2 F2DOT14 values)
          scale_x = component[:scale_x] || 1.0
          scale_y = component[:scale_y] || 1.0
          data << [
            float_to_f2dot14(scale_x),
            float_to_f2dot14(scale_y),
          ].pack("n2")
        elsif (flags & WE_HAVE_A_SCALE) != 0
          # Uniform scale (1 F2DOT14 value)
          scale = component[:scale] || 1.0
          data << [float_to_f2dot14(scale)].pack("n")
        end

        data
      end

      private_class_method def self.encode_coordinates(points)
        flags = []
        x_deltas = []
        y_deltas = []

        prev_x = 0
        prev_y = 0

        # Calculate deltas and determine flags
        points.each do |point|
          x = point[:x]
          y = point[:y]
          on_curve = point[:on_curve]

          dx = x - prev_x
          dy = y - prev_y

          flag = 0
          flag |= ON_CURVE_POINT if on_curve

          # X coordinate encoding
          if dx.zero?
            flag |= X_IS_SAME_OR_POSITIVE_X_SHORT
          elsif dx >= -255 && dx <= 255
            flag |= X_SHORT_VECTOR
            flag |= X_IS_SAME_OR_POSITIVE_X_SHORT if dx.positive?
            x_deltas << dx.abs
          else
            x_deltas << dx
          end

          # Y coordinate encoding
          if dy.zero?
            flag |= Y_IS_SAME_OR_POSITIVE_Y_SHORT
          elsif dy >= -255 && dy <= 255
            flag |= Y_SHORT_VECTOR
            flag |= Y_IS_SAME_OR_POSITIVE_Y_SHORT if dy.positive?
            y_deltas << dy.abs
          else
            y_deltas << dy
          end

          flags << flag
          prev_x = x
          prev_y = y
        end

        # Apply RLE compression to flags
        flags_data = compress_flags(flags)

        # Encode coordinates
        x_coords_data = encode_coordinate_values(flags, x_deltas, :x)
        y_coords_data = encode_coordinate_values(flags, y_deltas, :y)

        [flags_data, x_coords_data, y_coords_data]
      end

      private_class_method def self.compress_flags(flags)
        data = (+"").force_encoding(Encoding::BINARY)
        i = 0

        while i < flags.length
          flag = flags[i]
          count = 1

          # Count consecutive identical flags
          while i + count < flags.length && flags[i + count] == flag && count < 256
            count += 1
          end

          if count > 1
            # Use repeat flag
            data << [flag | REPEAT_FLAG].pack("C")
            data << [count - 1].pack("C") # Repeat count (0 means repeat once more)
            i += count
          else
            # Single flag
            data << [flag].pack("C")
            i += 1
          end
        end

        data
      end

      private_class_method def self.encode_coordinate_values(flags, deltas, axis)
        data = (+"").force_encoding(Encoding::BINARY)
        short_flag = axis == :x ? X_SHORT_VECTOR : Y_SHORT_VECTOR
        same_flag = axis == :x ? X_IS_SAME_OR_POSITIVE_X_SHORT : Y_IS_SAME_OR_POSITIVE_Y_SHORT

        delta_index = 0

        flags.each do |flag|
          if (flag & short_flag) != 0
            # 1-byte coordinate (already absolute value in deltas)
            data << [deltas[delta_index]].pack("C")
            delta_index += 1
          elsif (flag & same_flag) != 0
            # Same as previous (delta = 0), no data
          else
            # 2-byte signed coordinate
            delta = deltas[delta_index]
            # Pack as signed 16-bit big-endian
            data << [delta].pack("n") # Will need to convert to signed
            delta_index += 1
          end
        end

        data
      end

      private_class_method def self.calculate_bounding_box(contours)
        x_min = Float::INFINITY
        y_min = Float::INFINITY
        x_max = -Float::INFINITY
        y_max = -Float::INFINITY

        contours.each do |contour|
          contour.each do |point|
            x = point[:x]
            y = point[:y]

            x_min = x if x < x_min
            y_min = y if y < y_min
            x_max = x if x > x_max
            y_max = y if y > y_max
          end
        end

        {
          x_min: x_min.round,
          y_min: y_min.round,
          x_max: x_max.round,
          y_max: y_max.round,
        }
      end

      private_class_method def self.float_to_f2dot14(value)
        # Convert float to F2DOT14 fixed-point format
        # F2DOT14: 2 bits integer, 14 bits fractional
        # Range: -2.0 to ~1.99993896484375
        raise ArgumentError, "value out of F2DOT14 range" if value < -2.0 || value > 2.0

        fixed = (value * 16_384.0).round
        # Convert to unsigned 16-bit
        fixed.negative? ? fixed + 65_536 : fixed
      end

      private_class_method def self.validate_bbox!(bbox)
        raise ArgumentError, "bbox cannot be nil" if bbox.nil?
        raise ArgumentError, "bbox must be Hash" unless bbox.is_a?(Hash)

        required = %i[x_min y_min x_max y_max]
        missing = required - bbox.keys
        unless missing.empty?
          raise ArgumentError, "bbox missing keys: #{missing.join(', ')}"
        end

        required.each do |key|
          value = bbox[key]
          unless value.is_a?(Numeric)
            raise ArgumentError, "bbox[:#{key}] must be Numeric"
          end
        end

        if bbox[:x_min] > bbox[:x_max]
          raise ArgumentError, "bbox x_min must be <= x_max"
        end

        if bbox[:y_min] > bbox[:y_max]
          raise ArgumentError, "bbox y_min must be <= y_max"
        end
      end

      private_class_method def self.validate_component!(component)
        raise ArgumentError, "component must be Hash" unless component.is_a?(Hash)
        unless component[:glyph_index]
          raise ArgumentError, "component must have :glyph_index"
        end
        unless component[:glyph_index].is_a?(Integer)
          raise ArgumentError, "component :glyph_index must be Integer"
        end
        if component[:glyph_index].negative?
          raise ArgumentError, "component :glyph_index must be non-negative"
        end
      end
    end
  end
end
