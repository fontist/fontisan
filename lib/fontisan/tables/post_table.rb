# frozen_string_literal: true

require_relative "../sfnt_table"
require_relative "post"

module Fontisan
  module Tables
    # OOP representation of the 'post' (PostScript) table
    #
    # The post table contains PostScript information, primarily glyph names.
    # Different versions exist (1.0, 2.0, 2.5, 3.0, 4.0) with varying
    # glyph name storage strategies.
    #
    # This class extends SfntTable to provide post-specific validation and
    # convenience methods for accessing PostScript metrics and glyph names.
    #
    # @example Accessing post table data
    #   post = font.sfnt_table("post")
    #   post.italic_angle      # => 0.0
    #   post.underline_position # => -100
    #   post.underline_thickness # => 50
    #   post.glyph_name_for(42) # => "A"
    class PostTable < SfntTable
      # Get post table version
      #
      # @return [Float, nil] Version number (1.0, 2.0, 2.5, 3.0, or 4.0)
      def version
        return nil unless parsed

        parsed.version
      end

      # Get italic angle in degrees
      #
      # Positive value means counter-clockwise tilt
      #
      # @return [Float, nil] Italic angle in degrees, or nil if not parsed
      def italic_angle
        return nil unless parsed

        parsed.italic_angle
      end

      # Check if font is italic
      #
      # @return [Boolean] true if italic_angle != 0
      def italic?
        angle = italic_angle
        !angle.nil? && angle != 0
      end

      # Get underline position
      #
      # Distance from baseline to top of underline (negative for under baseline)
      #
      # @return [Integer, nil] Underline position in FUnits, or nil if not parsed
      def underline_position
        parsed&.underline_position
      end

      # Get underline thickness
      #
      # @return [Integer, nil] Underline thickness in FUnits, or nil if not parsed
      def underline_thickness
        parsed&.underline_thickness
      end

      # Check if font is fixed pitch (monospaced)
      #
      # @return [Boolean] true if font is monospaced
      def fixed_pitch?
        return false unless parsed

        parsed.is_fixed_pitch == 1
      end

      # Get minimum memory for Type 42 fonts
      #
      # @return [Integer, nil] Minimum memory in bytes, or nil if not parsed
      def min_mem_type42
        parsed&.min_mem_type42
      end

      # Get maximum memory for Type 42 fonts
      #
      # @return [Integer, nil] Maximum memory in bytes, or nil if not parsed
      def max_mem_type42
        parsed&.max_mem_type42
      end

      # Get minimum memory for Type 1 fonts
      #
      # @return [Integer, nil] Minimum memory in bytes, or nil if not parsed
      def min_mem_type1
        parsed&.min_mem_type1
      end

      # Get maximum memory for Type 1 fonts
      #
      # @return [Integer, nil] Maximum memory in bytes, or nil if not parsed
      def max_mem_type1
        parsed&.max_mem_type1
      end

      # Get all glyph names
      #
      # Only available for version 1.0 and 2.0
      #
      # @return [Array<String>] Array of glyph names
      def glyph_names
        return [] unless parsed

        parsed.glyph_names || []
      end

      # Get glyph name by ID
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [String, nil] Glyph name, or nil if not found
      def glyph_name_for(glyph_id)
        names = glyph_names
        return nil if glyph_id.negative? || glyph_id >= names.length

        names[glyph_id]
      end

      # Check if glyph names are available
      #
      # @return [Boolean] true if glyph names can be retrieved
      def has_glyph_names?
        return false unless parsed

        parsed.has_glyph_names?
      end

      # Get the number of glyphs with names
      #
      # @return [Integer] Number of named glyphs
      def named_glyph_count
        glyph_names.length
      end

      protected

      # Validate the parsed post table
      #
      # @return [Boolean] true if valid
      # @raise [InvalidFontError] if post table is invalid
      def validate_parsed_table?
        return true unless parsed

        # Validate version
        unless parsed.valid_version?
          raise InvalidFontError,
                "Invalid post table version: #{parsed.version} " \
                "(must be 1.0, 2.0, 2.5, 3.0, or 4.0)"
        end

        # Validate italic angle
        unless parsed.valid_italic_angle?
          raise InvalidFontError,
                "Invalid post italic angle: #{parsed.italic_angle} " \
                "(must be between -60 and 60 degrees)"
        end

        # Validate fixed pitch flag
        unless parsed.valid_fixed_pitch_flag?
          raise InvalidFontError,
                "Invalid post is_fixed_pitch: #{parsed.is_fixed_pitch} " \
                "(must be 0 or 1)"
        end

        # Validate version 2.0 data completeness
        unless parsed.complete_version_2_data?
          raise InvalidFontError,
                "Invalid post version 2.0 table: incomplete data"
        end

        true
      end
    end
  end
end
