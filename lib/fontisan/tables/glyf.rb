# frozen_string_literal: true

require_relative "../binary/base_record"
require_relative "glyf/simple_glyph"
require_relative "glyf/compound_glyph"
require_relative "glyf/curve_converter"
require_relative "glyf/glyph_builder"

module Fontisan
  module Tables
    # Parser for the 'glyf' (Glyph Data) table
    #
    # The glyf table contains TrueType glyph outline data. Each glyph is
    # described by either a simple glyph (with contours and points) or a
    # compound glyph (composed of other glyphs with transformations).
    #
    # The glyf table is accessed via offsets from the loca table, which
    # provides the byte offset and size for each glyph. Empty glyphs
    # (e.g., space characters) have zero size in loca.
    #
    # Glyph types are determined by numberOfContours:
    # - numberOfContours >= 0: Simple glyph with that many contours
    # - numberOfContours == -1: Compound glyph composed of other glyphs
    #
    # The glyf table is context-dependent and requires:
    # - loca table (for glyph offsets and sizes)
    # - head table (for coordinate interpretation and flags)
    #
    # Reference: OpenType specification, glyf table
    # https://docs.microsoft.com/en-us/typography/opentype/spec/glyf
    #
    # @example Accessing a glyph
    #   # Get required tables first
    #   head = font.table('head')
    #   loca = font.table('loca')
    #   loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)
    #
    #   # Parse glyf table
    #   data = font.read_table_data('glyf')
    #   glyf = Fontisan::Tables::Glyf.read(data)
    #
    #   # Get a specific glyph
    #   glyph = glyf.glyph_for(42, loca, head)
    #   puts glyph.simple? ? "Simple glyph" : "Compound glyph"
    #   puts glyph.bounding_box  # => [xMin, yMin, xMax, yMax]
    class Glyf < Binary::BaseRecord
      # Store the raw data for deferred parsing
      attr_accessor :raw_data

      # Cache for parsed glyphs
      # @return [Hash<Integer, SimpleGlyph|CompoundGlyph>]
      attr_reader :glyphs_cache

      # Override read to capture raw data
      #
      # @param io [IO, String] Input data
      # @return [Glyf] Parsed table instance
      def self.read(io)
        instance = new

        # Initialize cache
        instance.instance_variable_set(:@glyphs_cache, {})

        # Handle nil or empty data gracefully
        instance.raw_data = if io.nil?
                              "".b
                            elsif io.is_a?(String)
                              io
                            else
                              io.read || "".b
                            end

        instance
      end

      # Get glyph data for a specific glyph ID
      #
      # This method retrieves and parses the glyph at the specified ID.
      # It uses the loca table to determine the offset and size, then
      # parses the glyph data to create either a SimpleGlyph or CompoundGlyph.
      #
      # Results are cached to avoid re-parsing the same glyph multiple times.
      #
      # @param glyph_id [Integer] Glyph ID (0-based, 0 is .notdef)
      # @param loca [Loca] Parsed loca table with offsets
      # @param head [Head] Parsed head table for coordinate interpretation
      # @return [SimpleGlyph, CompoundGlyph, nil] Parsed glyph or nil if empty/invalid
      # @raise [ArgumentError] If loca is not parsed or tables are invalid
      # @raise [Fontisan::CorruptedTableError] If glyph data is corrupted
      #
      # @example Getting a simple glyph
      #   glyph = glyf.glyph_for(65, loca, head)  # 'A' character
      #   if glyph.simple?
      #     puts "Contours: #{glyph.num_contours}"
      #     puts "Points: #{glyph.x_coordinates.length}"
      #   end
      def glyph_for(glyph_id, loca, head)
        # Return cached glyph if available
        return glyphs_cache[glyph_id] if glyphs_cache.key?(glyph_id)

        # Validate inputs
        validate_context!(loca, head, glyph_id)

        # Get offset and size from loca table
        offset = loca.offset_for(glyph_id)
        size = loca.size_of(glyph_id)

        # Empty glyph (e.g., space character)
        if size.nil? || size.zero?
          glyphs_cache[glyph_id] = nil
          return nil
        end

        # Validate offset and size
        if offset + size > raw_data.length
          raise Fontisan::CorruptedTableError,
                "Glyph #{glyph_id} extends beyond glyf table: " \
                "offset=#{offset}, size=#{size}, table_size=#{raw_data.length}"
        end

        # Extract glyph data
        glyph_data = raw_data[offset, size]

        # Parse glyph
        glyph = parse_glyph_data(glyph_data, glyph_id)
        glyphs_cache[glyph_id] = glyph
      end

      # Clear the glyph cache to free memory
      #
      # This is useful for long-running processes that parse many glyphs
      # but don't need to keep them all in memory.
      #
      # @return [void]
      def clear_cache
        glyphs_cache.clear
      end

      # Get the number of cached glyphs
      #
      # @return [Integer] Number of glyphs in cache
      def cache_size
        glyphs_cache.size
      end

      # Check if a glyph is cached
      #
      # @param glyph_id [Integer] Glyph ID to check
      # @return [Boolean] True if glyph is cached
      def cached?(glyph_id)
        glyphs_cache.key?(glyph_id)
      end

      # Lazy initialization of glyphs cache
      #
      # @return [Hash] The glyphs cache
      def glyphs_cache
        @glyphs_cache ||= {}
      end

      private

      # Validate context and glyph ID
      #
      # @param loca [Loca] Loca table
      # @param head [Head] Head table
      # @param glyph_id [Integer] Glyph ID
      # @raise [ArgumentError] If validation fails
      def validate_context!(loca, head, glyph_id)
        unless loca.respond_to?(:offset_for) && loca.respond_to?(:size_of)
          raise ArgumentError,
                "loca must be a parsed Loca table with offset_for and size_of methods"
        end

        unless loca.parsed?
          raise ArgumentError,
                "loca table must be parsed with parse_with_context before use"
        end

        unless head.respond_to?(:units_per_em)
          raise ArgumentError,
                "head must be a parsed Head table"
        end

        if glyph_id.nil? || glyph_id.negative?
          raise ArgumentError,
                "glyph_id must be >= 0, got: #{glyph_id.inspect}"
        end

        if glyph_id >= loca.num_glyphs
          raise ArgumentError,
                "glyph_id #{glyph_id} exceeds number of glyphs (#{loca.num_glyphs})"
        end
      end

      # Parse glyph data into SimpleGlyph or CompoundGlyph
      #
      # @param data [String] Binary glyph data
      # @param glyph_id [Integer] Glyph ID
      # @return [SimpleGlyph, CompoundGlyph] Parsed glyph
      # @raise [Fontisan::CorruptedTableError] If data is insufficient or invalid
      def parse_glyph_data(data, glyph_id)
        # Need at least 10 bytes for glyph header
        if data.length < 10
          raise Fontisan::CorruptedTableError,
                "Insufficient glyph data for glyph #{glyph_id}: " \
                "need at least 10 bytes, got #{data.length}"
        end

        # Parse numberOfContours (signed 16-bit) at offset 0
        num_contours_raw = data[0, 2].unpack1("n")
        num_contours = to_signed_16(num_contours_raw)

        # Determine glyph type and parse accordingly
        if num_contours >= 0
          SimpleGlyph.parse(data, glyph_id)
        elsif num_contours == -1
          CompoundGlyph.parse(data, glyph_id)
        else
          raise Fontisan::CorruptedTableError,
                "Invalid numberOfContours for glyph #{glyph_id}: #{num_contours}. " \
                "Must be >= 0 for simple glyphs or -1 for compound glyphs."
        end
      end

      # Convert unsigned 16-bit value to signed
      #
      # @param value [Integer] Unsigned 16-bit value
      # @return [Integer] Signed 16-bit value
      def to_signed_16(value)
        value > 0x7FFF ? value - 0x10000 : value
      end
    end
  end
end
