# frozen_string_literal: true

require_relative "../sfnt_table"
require_relative "loca"

module Fontisan
  module Tables
    # OOP representation of the 'loca' (Index to Location) table
    #
    # The loca table provides offsets to glyph data in the glyf table.
    # Each glyph has an entry indicating where its data begins in the glyf table.
    #
    # This class extends SfntTable to provide loca-specific convenience
    # methods for accessing glyph locations. The loca table requires context
    # from the head and maxp tables to function properly.
    #
    # @example Accessing glyph locations
    #   loca = font.sfnt_table("loca")
    #   head = font.table("head")
    #   maxp = font.table("maxp")
    #
    #   loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)
    #   offset = loca.offset_for(42)  # Get offset for glyph 42
    #   size = loca.size_of(42)       # Get size of glyph 42
    #   loca.empty?(32)              # Check if glyph 32 is empty
    class LocaTable < SfntTable
      # Short format constant
      FORMAT_SHORT = 0

      # Long format constant
      FORMAT_LONG = 1

      # Cache for context
      attr_reader :index_to_loc_format, :num_glyphs

      # Parse the loca table with required context
      #
      # The loca table cannot be used without context from head and maxp tables.
      #
      # @param index_to_loc_format [Integer] Format (0 = short, 1 = long) from head
      # @param num_glyphs [Integer] Total number of glyphs from maxp
      # @return [self] Returns self for chaining
      # @raise [ArgumentError] if context is invalid
      def parse_with_context(index_to_loc_format, num_glyphs)
        unless index_to_loc_format && num_glyphs
          raise ArgumentError,
                "loca table requires index_to_loc_format and num_glyphs"
        end

        @index_to_loc_format = index_to_loc_format
        @num_glyphs = num_glyphs

        # Ensure parsed data is loaded
        parse

        # Parse with context
        parsed.parse_with_context(index_to_loc_format, num_glyphs)

        self
      end

      # Check if table has been parsed with context
      #
      # @return [Boolean] true if context is available
      def has_context?
        !@index_to_loc_format.nil? && !@num_glyphs.nil?
      end

      # Get the offset for a glyph ID in the glyf table
      #
      # @param glyph_id [Integer] Glyph ID (0-based)
      # @return [Integer, nil] Byte offset in glyf table, or nil if invalid
      # @raise [ArgumentError] if context not set
      def offset_for(glyph_id)
        ensure_context!
        return nil unless parsed

        parsed.offset_for(glyph_id)
      end

      # Calculate the size of glyph data for a glyph ID
      #
      # @param glyph_id [Integer] Glyph ID (0-based)
      # @return [Integer, nil] Size in bytes, or nil if invalid
      # @raise [ArgumentError] if context not set
      def size_of(glyph_id)
        ensure_context!
        return nil unless parsed

        parsed.size_of(glyph_id)
      end

      # Check if a glyph has no outline data
      #
      # @param glyph_id [Integer] Glyph ID (0-based)
      # @return [Boolean, nil] True if empty, false if has data, nil if invalid
      # @raise [ArgumentError] if context not set
      def empty?(glyph_id)
        ensure_context!
        return nil unless parsed

        parsed.empty?(glyph_id)
      end

      # Check if using short format (format 0)
      #
      # @return [Boolean] true if short format
      def short_format?
        return false unless parsed?

        @index_to_loc_format == FORMAT_SHORT
      end

      # Check if using long format (format 1)
      #
      # @return [Boolean] true if long format
      def long_format?
        return false unless parsed?

        @index_to_loc_format == FORMAT_LONG
      end

      # Get format name
      #
      # @return [String] "short" or "long"
      def format_name
        short_format? ? "short" : "long"
      end

      # Get all offsets
      #
      # @return [Array<Integer>] Array of glyph offsets
      def all_offsets
        return [] unless parsed?

        parsed.offsets || []
      end

      # Get all glyph sizes
      #
      # @return [Array<Integer>] Array of glyph sizes
      def all_sizes
        return [] unless has_context?

        (0...num_glyphs).map { |gid| size_of(gid) || 0 }
      end

      # Get empty glyph IDs
      #
      # @return [Array<Integer>] Array of empty glyph IDs
      def empty_glyph_ids
        return [] unless has_context?

        (0...num_glyphs).select { |gid| empty?(gid) }
      end

      # Get non-empty glyph IDs
      #
      # @return [Array<Integer>] Array of glyph IDs with data
      def non_empty_glyph_ids
        return [] unless has_context?

        (0...num_glyphs).reject { |gid| empty?(gid) }
      end

      # Get statistics about glyph locations
      #
      # @return [Hash] Statistics about loca table
      def statistics
        return {} unless has_context?

        sizes = all_sizes
        offsets = all_offsets

        {
          num_glyphs: num_glyphs,
          format: format_name,
          empty_glyph_count: empty_glyph_ids.length,
          non_empty_glyph_count: non_empty_glyph_ids.length,
          min_size: sizes.compact.min,
          max_size: sizes.compact.max,
          total_data_size: sizes.sum,
          glyf_table_size: offsets.last || 0,
        }
      end

      private

      # Ensure context tables are set
      #
      # @raise [ArgumentError] if context not set
      def ensure_context!
        unless has_context?
          raise ArgumentError,
                "loca table requires context. " \
                "Call parse_with_context(index_to_loc_format, num_glyphs) first"
        end
      end

      protected

      # Validate the parsed loca table
      #
      # @return [Boolean] true if valid
      # @raise [InvalidFontError] if loca table is invalid
      def validate_parsed_table?
        # Loca table validation requires context, so we can't validate here
        true
      end
    end
  end
end
