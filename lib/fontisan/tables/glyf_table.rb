# frozen_string_literal: true

require_relative "../sfnt_table"
require_relative "glyf"

module Fontisan
  module Tables
    # OOP representation of the 'glyf' (Glyph Data) table
    #
    # The glyf table contains TrueType glyph outline data. Each glyph is
    # described by either a simple glyph (with contours and points) or a
    # compound glyph (composed of other glyphs with transformations).
    #
    # This class extends SfntTable to provide glyf-specific convenience
    # methods for accessing glyph data. The glyf table requires context
    # from the loca and head tables to function properly.
    #
    # @example Accessing glyphs
    #   glyf = font.sfnt_table("glyf")
    #   loca = font.table("loca")
    #   head = font.table("head")
    #
    #   glyf.parse_with_context(loca, head)
    #   glyph = glyf.glyph_for(42)  # Get glyph by ID
    #   glyph.simple?  # => true or false
    #   glyph.bounding_box  # => [xMin, yMin, xMax, yMax]
    class GlyfTable < SfntTable
      # Cache for context tables
      attr_reader :loca_table, :head_table

      # Parse the glyf table with required context
      #
      # The glyf table cannot be used without context from loca and head tables.
      # This method must be called before accessing glyph data.
      #
      # @param loca [Tables::Loca] Parsed loca table
      # @param head [Tables::Head] Parsed head table
      # @return [self] Returns self for chaining
      # @raise [ArgumentError] if context is invalid
      def parse_with_context(loca, head)
        unless loca && head
          raise ArgumentError,
                "glyf table requires both loca and head tables as context"
        end

        @loca_table = loca
        @head_table = head

        # Ensure parsed data is loaded
        parse

        self
      end

      # Check if table has been parsed with context
      #
      # @return [Boolean] true if context is available
      def has_context?
        !@loca_table.nil? && !@head_table.nil?
      end

      # Get a glyph by ID
      #
      # @param glyph_id [Integer] Glyph ID (0-based, 0 is .notdef)
      # @return [SimpleGlyph, CompoundGlyph, nil] Parsed glyph or nil if empty
      # @raise [ArgumentError] if context not set
      def glyph_for(glyph_id)
        ensure_context!
        return nil unless parsed

        parsed.glyph_for(glyph_id, @loca_table, @head_table)
      end

      # Check if a glyph is simple (has contours)
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Boolean] true if glyph is simple
      def simple_glyph?(glyph_id)
        glyph = glyph_for(glyph_id)
        return false if glyph.nil?

        glyph.respond_to?(:num_contours) && glyph.num_contours >= 0
      end

      # Check if a glyph is compound
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Boolean] true if glyph is compound
      def compound_glyph?(glyph_id)
        glyph = glyph_for(glyph_id)
        return false if glyph.nil?

        glyph.respond_to?(:num_contours) && glyph.num_contours == -1
      end

      # Check if a glyph is empty
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Boolean] true if glyph has no data
      def empty_glyph?(glyph_id)
        glyph_for(glyph_id).nil?
      end

      # Get glyph bounding box
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<Integer>, nil] [xMin, yMin, xMax, yMax] or nil
      def glyph_bounding_box(glyph_id)
        glyph = glyph_for(glyph_id)
        return nil if glyph.nil?

        [glyph.x_min, glyph.y_min, glyph.x_max, glyph.y_max]
      end

      # Get number of contours for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Integer, nil] Number of contours, or nil
      def glyph_contour_count(glyph_id)
        glyph = glyph_for(glyph_id)
        return nil if glyph.nil?

        glyph.num_contours if glyph.respond_to?(:num_contours)
      end

      # Get number of points for a simple glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Integer, nil] Number of points, or nil
      def glyph_point_count(glyph_id)
        glyph = glyph_for(glyph_id)
        return nil if glyph.nil? || !glyph.respond_to?(:num_points)

        glyph.num_points
      end

      # Get glyph cache size
      #
      # @return [Integer] Number of cached glyphs
      def cache_size
        return 0 unless parsed

        parsed.cache_size
      end

      # Clear glyph cache
      #
      # @return [void]
      def clear_cache
        return unless parsed

        parsed.clear_cache
      end

      # Validate all glyphs are accessible
      #
      # @param num_glyphs [Integer] Total number of glyphs to check
      # @return [Boolean] true if all glyphs can be accessed
      def all_glyphs_accessible?(num_glyphs)
        ensure_context!
        return false unless parsed

        parsed.all_glyphs_accessible?(@loca_table, @head_table, num_glyphs)
      end

      # Validate no glyphs are clipped
      #
      # @param num_glyphs [Integer] Total number of glyphs to check
      # @return [Boolean] true if no glyphs exceed font bounds
      def no_clipped_glyphs?(num_glyphs)
        ensure_context!
        return false unless parsed

        parsed.no_clipped_glyphs?(@loca_table, @head_table, num_glyphs)
      end

      # Validate all glyphs have valid contour counts
      #
      # @param glyph_id [Integer] Glyph ID to check
      # @return [Boolean] true if contour count is valid
      def valid_contour_count?(glyph_id)
        ensure_context!
        return false unless parsed

        parsed.valid_contour_count?(glyph_id, @loca_table, @head_table)
      end

      # Validate glyphs have sound instructions
      #
      # @param num_glyphs [Integer] Total number of glyphs to check
      # @return [Boolean] true if all instructions are valid
      def instructions_sound?(num_glyphs)
        ensure_context!
        return false unless parsed

        parsed.instructions_sound?(@loca_table, @head_table, num_glyphs)
      end

      # Get glyph statistics
      #
      # @param num_glyphs [Integer] Total number of glyphs
      # @return [Hash] Statistics about the glyphs
      def statistics(num_glyphs)
        ensure_context!
        return {} unless parsed

        simple_count = 0
        compound_count = 0
        empty_count = 0

        (0...num_glyphs).each do |gid|
          if empty_glyph?(gid)
            empty_count += 1
          elsif simple_glyph?(gid)
            simple_count += 1
          elsif compound_glyph?(gid)
            compound_count += 1
          end
        end

        {
          total_glyphs: num_glyphs,
          simple_glyphs: simple_count,
          compound_glyphs: compound_count,
          empty_glyphs: empty_count,
          cached_glyphs: cache_size,
        }
      end

      private

      # Ensure context tables are set
      #
      # @raise [ArgumentError] if context not set
      def ensure_context!
        unless has_context?
          raise ArgumentError,
                "glyf table requires context. Call parse_with_context(loca, head) first"
        end
      end

      protected

      # Validate the parsed glyf table
      #
      # @return [Boolean] true if valid
      # @raise [InvalidFontError] if glyf table is invalid
      def validate_parsed_table?
        # Glyf table validation requires context, so we can't validate here
        # Validation is deferred until context is provided
        true
      end
    end
  end
end
