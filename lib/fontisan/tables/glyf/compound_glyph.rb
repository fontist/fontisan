# frozen_string_literal: true

module Fontisan
  module Tables
    # Represents a compound TrueType glyph composed of other glyphs
    #
    # A compound glyph is built by referencing other glyphs (components)
    # and applying transformations to them. Each component references
    # another glyph by ID and specifies positioning and optional scaling,
    # rotation, or affine transformation.
    #
    # The glyph structure consists of:
    # - Header: numberOfContours (-1), xMin, yMin, xMax, yMax (10 bytes)
    # - Components: array of component descriptions (variable length)
    # - Instructions: optional TrueType hinting instructions
    #
    # Each component has:
    # - flags (uint16): component flags
    # - glyphIndex (uint16): referenced glyph ID
    # - arguments: positioning (arg1, arg2) - interpretation depends on flags
    # - transformation: optional scale/rotation/affine matrix
    #
    # Component flags (16-bit) indicate:
    # - Bit 0 (0x0001): ARG_1_AND_2_ARE_WORDS - arguments are 16-bit
    # - Bit 1 (0x0002): ARGS_ARE_XY_VALUES - arguments are x,y offsets
    # - Bit 2 (0x0004): ROUND_XY_TO_GRID - round x,y to grid
    # - Bit 3 (0x0008): WE_HAVE_A_SCALE - uniform scale follows
    # - Bit 5 (0x0020): MORE_COMPONENTS - more components follow
    # - Bit 6 (0x0040): WE_HAVE_AN_X_AND_Y_SCALE - separate x,y scale
    # - Bit 7 (0x0080): WE_HAVE_A_TWO_BY_TWO - 2x2 affine matrix
    # - Bit 8 (0x0100): WE_HAVE_INSTRUCTIONS - instructions follow components
    # - Bit 9 (0x0200): USE_MY_METRICS - use this component's metrics
    # - Bit 10 (0x0400): OVERLAP_COMPOUND - component outlines overlap
    # - Bit 11 (0x0800): SCALED_COMPONENT_OFFSET - scale offset values
    # - Bit 12 (0x1000): UNSCALED_COMPONENT_OFFSET - don't scale offsets
    #
    # Reference: OpenType specification, glyf table - Compound Glyph Description
    # https://docs.microsoft.com/en-us/typography/opentype/spec/glyf#compound-glyph-description
    class CompoundGlyph
      # Component flag constants
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
      SCALED_COMPONENT_OFFSET = 0x0800
      UNSCALED_COMPONENT_OFFSET = 0x1000

      # Component data structure
      Component = Struct.new(
        :flags,
        :glyph_index,
        :arg1,
        :arg2,
        :scale_x,
        :scale_y,
        :scale_01,
        :scale_10,
        keyword_init: true,
      ) do
        # Check if arguments are x,y offsets (vs point numbers)
        def args_are_xy?
          (flags & ARGS_ARE_XY_VALUES) != 0
        end

        # Check if using this component's metrics
        def use_my_metrics?
          (flags & USE_MY_METRICS) != 0
        end

        # Check if component has uniform scale
        def has_scale?
          (flags & WE_HAVE_A_SCALE) != 0
        end

        # Check if component has separate x,y scale
        def has_xy_scale?
          (flags & WE_HAVE_AN_X_AND_Y_SCALE) != 0
        end

        # Check if component has 2x2 transformation matrix
        def has_2x2?
          (flags & WE_HAVE_A_TWO_BY_TWO) != 0
        end

        # Check if component overlaps with others
        def overlap?
          (flags & OVERLAP_COMPOUND) != 0
        end

        # Get transformation matrix as array [a, b, c, d, e, f]
        # representing affine transformation: x' = a*x + c*y + e, y' = b*x + d*y + f
        #
        # @return [Array<Float>] Transformation matrix [a, b, c, d, e, f]
        def transformation_matrix
          if has_2x2?
            [scale_x, scale_01, scale_10, scale_y, arg1, arg2]
          elsif has_xy_scale?
            [scale_x, 0.0, 0.0, scale_y, arg1, arg2]
          elsif has_scale?
            [scale_x, 0.0, 0.0, scale_x, arg1, arg2]
          else
            [1.0, 0.0, 0.0, 1.0, arg1, arg2]
          end
        end
      end

      # Glyph header fields
      attr_reader :glyph_id
      attr_reader :x_min, :y_min, :x_max, :y_max, :instruction_length,
                  :instructions

      # Compound glyph data
      attr_reader :components

      # Parse compound glyph data
      #
      # @param data [String] Binary glyph data
      # @param glyph_id [Integer] Glyph ID for error reporting
      # @return [CompoundGlyph] Parsed compound glyph
      # @raise [Fontisan::CorruptedTableError] If data is insufficient or invalid
      def self.parse(data, glyph_id)
        glyph = new(glyph_id)
        glyph.parse_data(data)
        glyph
      end

      # Initialize a new compound glyph
      #
      # @param glyph_id [Integer] Glyph ID
      def initialize(glyph_id)
        @glyph_id = glyph_id
        @components = []
      end

      # Parse glyph data
      #
      # @param data [String] Binary glyph data
      # @raise [Fontisan::CorruptedTableError] If parsing fails
      def parse_data(data)
        io = StringIO.new(data)
        io.set_encoding(Encoding::BINARY)

        parse_header(io)
        parse_components(io)
        parse_instructions(io) if has_instructions?

        validate_parsed_data!
      end

      # Check if this is a simple glyph
      #
      # @return [Boolean] Always false for CompoundGlyph
      def simple?
        false
      end

      # Check if this is a compound glyph
      #
      # @return [Boolean] Always true for CompoundGlyph
      def compound?
        true
      end

      # Check if glyph has no components
      #
      # @return [Boolean] True if no components
      def empty?
        components.empty?
      end

      # Get bounding box as array
      #
      # @return [Array<Integer>] Bounding box [xMin, yMin, xMax, yMax]
      def bounding_box
        [x_min, y_min, x_max, y_max]
      end

      # Get all component glyph IDs (for dependency tracking)
      #
      # This method returns the glyph IDs of all components that make up
      # this compound glyph. This is essential for subsetting operations,
      # where all dependent glyphs must be included.
      #
      # @return [Array<Integer>] Array of component glyph IDs
      #
      # @example Getting component dependencies
      #   glyph = glyf.glyph_for(100, loca, head)
      #   if glyph.compound?
      #     deps = glyph.component_glyph_ids
      #     puts "Glyph 100 depends on: #{deps.join(', ')}"
      #   end
      def component_glyph_ids
        components.map(&:glyph_index)
      end

      # Check if glyph uses a specific component
      #
      # @param glyph_id [Integer] Glyph ID to check
      # @return [Boolean] True if glyph uses this component
      def uses_component?(glyph_id)
        component_glyph_ids.include?(glyph_id)
      end

      # Get number of components
      #
      # @return [Integer] Component count
      def num_components
        components.length
      end

      # Check if any component uses metrics from referenced glyph
      #
      # @return [Boolean] True if any component has USE_MY_METRICS flag
      def uses_component_metrics?
        components.any?(&:use_my_metrics?)
      end

      # Get the component that provides metrics (if any)
      #
      # @return [Component, nil] Component with USE_MY_METRICS flag, or nil
      def metrics_component
        components.find(&:use_my_metrics?)
      end

      private

      # Parse glyph header (10 bytes)
      #
      # @param io [StringIO] Input stream
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_header(io)
        header = io.read(10)
        if header.nil? || header.length < 10
          raise Fontisan::CorruptedTableError,
                "Insufficient header data for compound glyph #{glyph_id}"
        end

        values = header.unpack("n5")
        num_contours = to_signed_16(values[0])
        @x_min = to_signed_16(values[1])
        @y_min = to_signed_16(values[2])
        @x_max = to_signed_16(values[3])
        @y_max = to_signed_16(values[4])

        if num_contours != -1
          raise Fontisan::CorruptedTableError,
                "Compound glyph #{glyph_id} must have numberOfContours = -1, got #{num_contours}"
        end
      end

      # Parse all components
      #
      # @param io [StringIO] Input stream
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_components(io)
        loop do
          component = parse_component(io)
          @components << component

          # Check if more components follow
          break unless (component.flags & MORE_COMPONENTS) != 0
        end
      end

      # Parse a single component
      #
      # @param io [StringIO] Input stream
      # @return [Component] Parsed component
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_component(io)
        # Read flags and glyph index
        header = io.read(4)
        if header.nil? || header.length < 4
          raise Fontisan::CorruptedTableError,
                "Insufficient component header data for compound glyph #{glyph_id}"
        end

        flags, glyph_index = header.unpack("n2")

        # Parse arguments (position or point indices)
        arg1, arg2 = parse_component_arguments(io, flags)

        # Parse transformation (scale, rotation, or 2x2 matrix)
        scale_x, scale_y, scale_01, scale_10 = parse_component_transformation(
          io, flags
        )

        Component.new(
          flags: flags,
          glyph_index: glyph_index,
          arg1: arg1,
          arg2: arg2,
          scale_x: scale_x,
          scale_y: scale_y,
          scale_01: scale_01,
          scale_10: scale_10,
        )
      end

      # Parse component arguments (arg1, arg2)
      #
      # Arguments can be:
      # - 8-bit or 16-bit depending on ARG_1_AND_2_ARE_WORDS flag
      # - Interpreted as x,y offsets if ARGS_ARE_XY_VALUES is set
      # - Otherwise interpreted as point indices for alignment
      #
      # @param io [StringIO] Input stream
      # @param flags [Integer] Component flags
      # @return [Array<Integer>] [arg1, arg2]
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_component_arguments(io, flags)
        if (flags & ARG_1_AND_2_ARE_WORDS).zero?
          # 8-bit signed arguments
          data = io.read(2)
          if data.nil? || data.length < 2
            raise Fontisan::CorruptedTableError,
                  "Insufficient argument data for compound glyph #{glyph_id}"
          end

          values = data.unpack("C2")
          [to_signed_8(values[0]), to_signed_8(values[1])]
        else
          # 16-bit signed arguments
          data = io.read(4)
          if data.nil? || data.length < 4
            raise Fontisan::CorruptedTableError,
                  "Insufficient argument data for compound glyph #{glyph_id}"
          end

          values = data.unpack("n2")
          [to_signed_16(values[0]), to_signed_16(values[1])]
        end
      end

      # Parse component transformation
      #
      # Transformation can be:
      # - Uniform scale (1 value)
      # - Separate x,y scale (2 values)
      # - 2x2 affine matrix (4 values)
      # - None (identity transformation)
      #
      # @param io [StringIO] Input stream
      # @param flags [Integer] Component flags
      # @return [Array<Float>] [scale_x, scale_y, scale_01, scale_10]
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_component_transformation(io, flags)
        if (flags & WE_HAVE_A_TWO_BY_TWO) != 0
          # 2x2 transformation matrix (4 F2DOT14 values)
          data = io.read(8)
          if data.nil? || data.length < 8
            raise Fontisan::CorruptedTableError,
                  "Insufficient 2x2 matrix data for compound glyph #{glyph_id}"
          end

          values = data.unpack("n4").map { |v| f2dot14_to_float(v) }
          [values[0], values[3], values[1], values[2]] # [xscale, yscale, scale01, scale10]
        elsif (flags & WE_HAVE_AN_X_AND_Y_SCALE) != 0
          # Separate x and y scale (2 F2DOT14 values)
          data = io.read(4)
          if data.nil? || data.length < 4
            raise Fontisan::CorruptedTableError,
                  "Insufficient x,y scale data for compound glyph #{glyph_id}"
          end

          values = data.unpack("n2").map { |v| f2dot14_to_float(v) }
          [values[0], values[1], 0.0, 0.0]
        elsif (flags & WE_HAVE_A_SCALE) != 0
          # Uniform scale (1 F2DOT14 value)
          data = io.read(2)
          if data.nil? || data.length < 2
            raise Fontisan::CorruptedTableError,
                  "Insufficient scale data for compound glyph #{glyph_id}"
          end

          scale = f2dot14_to_float(data.unpack1("n"))
          [scale, scale, 0.0, 0.0]
        else
          # No transformation (identity)
          [1.0, 1.0, 0.0, 0.0]
        end
      end

      # Parse instructions if present
      #
      # @param io [StringIO] Input stream
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_instructions(io)
        length_data = io.read(2)
        if length_data.nil? || length_data.length < 2
          raise Fontisan::CorruptedTableError,
                "Insufficient instruction length data for compound glyph #{glyph_id}"
        end

        @instruction_length = length_data.unpack1("n")

        if @instruction_length.positive?
          @instructions = io.read(@instruction_length)
          if @instructions.nil? || @instructions.length < @instruction_length
            raise Fontisan::CorruptedTableError,
                  "Insufficient instruction data for compound glyph #{glyph_id}"
          end
        else
          @instructions = "".b
        end
      end

      # Check if any component has instructions flag set
      #
      # @return [Boolean] True if instructions should be present
      def has_instructions?
        components.any? { |c| (c.flags & WE_HAVE_INSTRUCTIONS) != 0 }
      end

      # Validate parsed data consistency
      #
      # @raise [Fontisan::CorruptedTableError] If validation fails
      def validate_parsed_data!
        if components.empty?
          raise Fontisan::CorruptedTableError,
                "Compound glyph #{glyph_id} has no components"
        end

        # Check for duplicate USE_MY_METRICS flags
        metrics_components = components.select(&:use_my_metrics?)
        if metrics_components.length > 1
          raise Fontisan::CorruptedTableError,
                "Compound glyph #{glyph_id} has multiple components with USE_MY_METRICS flag"
        end

        # Validate component glyph indices
        components.each_with_index do |component, i|
          if component.glyph_index.nil? || component.glyph_index.negative?
            raise Fontisan::CorruptedTableError,
                  "Invalid glyph index in component #{i} of compound glyph #{glyph_id}"
          end

          # Check for circular reference (component referencing self)
          if component.glyph_index == glyph_id
            raise Fontisan::CorruptedTableError,
                  "Circular reference: compound glyph #{glyph_id} references itself"
          end
        end
      end

      # Convert unsigned 16-bit value to signed
      #
      # @param value [Integer] Unsigned 16-bit value
      # @return [Integer] Signed 16-bit value
      def to_signed_16(value)
        value > 0x7FFF ? value - 0x10000 : value
      end

      # Convert unsigned 8-bit value to signed
      #
      # @param value [Integer] Unsigned 8-bit value
      # @return [Integer] Signed 8-bit value
      def to_signed_8(value)
        value > 0x7F ? value - 0x100 : value
      end

      # Convert F2DOT14 fixed-point to float
      #
      # F2DOT14 is a signed 2.14 fixed-point number:
      # - 2 bits for integer part (including sign)
      # - 14 bits for fractional part
      # Range: -2.0 to ~1.99993896484375
      #
      # @param value [Integer] Unsigned 16-bit F2DOT14 value
      # @return [Float] Float value
      def f2dot14_to_float(value)
        signed = to_signed_16(value)
        signed / 16_384.0 # 2^14 = 16384
      end
    end
  end
end
