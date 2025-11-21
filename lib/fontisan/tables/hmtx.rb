# frozen_string_literal: true

require_relative "../binary/base_record"

module Fontisan
  module Tables
    # Parser for the 'hmtx' (Horizontal Metrics) table
    #
    # The hmtx table contains horizontal metrics for each glyph in the font.
    # It provides advance width and left sidebearing values needed for proper
    # glyph positioning and text layout.
    #
    # Structure:
    # - hMetrics[numberOfHMetrics]: Array of LongHorMetric records
    #   Each record contains:
    #   - advanceWidth (uint16): Advance width in FUnits
    #   - lsb (int16): Left side bearing in FUnits
    # - leftSideBearings[numGlyphs - numberOfHMetrics]: Array of int16 values
    #   Additional LSB values for glyphs beyond numberOfHMetrics
    #
    # The table is context-dependent and requires:
    # - numberOfHMetrics from hhea table
    # - numGlyphs from maxp table
    #
    # Reference: OpenType specification, hmtx table
    # https://docs.microsoft.com/en-us/typography/opentype/spec/hmtx
    #
    # @example Parsing hmtx with context
    #   # Get required tables first
    #   hhea = font.table('hhea')
    #   maxp = font.table('maxp')
    #
    #   # Parse hmtx with context
    #   data = font.read_table_data('hmtx')
    #   hmtx = Fontisan::Tables::Hmtx.read(data)
    #   hmtx.parse_with_context(hhea.number_of_h_metrics, maxp.num_glyphs)
    #
    #   # Get metrics for a glyph
    #   metric = hmtx.metric_for(42)
    #   puts "Advance width: #{metric[:advance_width]}"
    #   puts "LSB: #{metric[:lsb]}"
    class Hmtx < Binary::BaseRecord
      # LongHorMetric record structure
      #
      # @!attribute advance_width
      #   @return [Integer] Advance width in FUnits
      # @!attribute lsb
      #   @return [Integer] Left side bearing in FUnits
      class LongHorMetric < Binary::BaseRecord
        uint16 :advance_width
        int16 :lsb

        # Convert to hash for convenience
        #
        # @return [Hash] Hash with :advance_width and :lsb keys
        def to_h
          { advance_width: advance_width, lsb: lsb }
        end
      end

      # Store the raw data for deferred parsing
      attr_accessor :raw_data

      # Parsed horizontal metrics array
      # @return [Array<Hash>] Array of metrics hashes
      attr_reader :h_metrics

      # Parsed left side bearings array
      # @return [Array<Integer>] Array of LSB values
      attr_reader :left_side_bearings

      # Number of horizontal metrics from hhea table
      # @return [Integer] Number of LongHorMetric records
      attr_reader :number_of_h_metrics

      # Total number of glyphs from maxp table
      # @return [Integer] Total glyph count
      attr_reader :num_glyphs

      # Override read to capture raw data
      #
      # @param io [IO, String] Input data
      # @return [Hmtx] Parsed table instance
      def self.read(io)
        instance = new

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

      # Parse the table with font context
      #
      # This method must be called after reading the table data, providing
      # the numberOfHMetrics from hhea and numGlyphs from maxp.
      #
      # @param number_of_h_metrics [Integer] Number of LongHorMetric records (from hhea)
      # @param num_glyphs [Integer] Total number of glyphs (from maxp)
      # @raise [ArgumentError] If context parameters are invalid
      # @raise [Fontisan::CorruptedTableError] If table data is insufficient
      def parse_with_context(number_of_h_metrics, num_glyphs)
        validate_context_params(number_of_h_metrics, num_glyphs)

        @number_of_h_metrics = number_of_h_metrics
        @num_glyphs = num_glyphs

        io = StringIO.new(raw_data)
        io.set_encoding(Encoding::BINARY)

        # Parse hMetrics array
        @h_metrics = parse_h_metrics(io, number_of_h_metrics)

        # Parse additional left side bearings
        lsb_count = num_glyphs - number_of_h_metrics
        @left_side_bearings = parse_left_side_bearings(io, lsb_count)

        validate_parsed_data!(io)
      end

      # Get horizontal metrics for a specific glyph ID
      #
      # For glyph IDs less than numberOfHMetrics, returns the corresponding
      # hMetrics entry. For glyph IDs >= numberOfHMetrics, uses the last
      # advance width from hMetrics with the indexed left side bearing.
      #
      # @param glyph_id [Integer] Glyph ID (0-based)
      # @return [Hash, nil] Hash with :advance_width and :lsb keys, or nil if invalid
      # @raise [RuntimeError] If table has not been parsed with context
      #
      # @example Getting metrics
      #   metric = hmtx.metric_for(0)  # .notdef glyph
      #   metric = hmtx.metric_for(65) # 'A' glyph (if mapped to 65)
      def metric_for(glyph_id)
        raise "Table not parsed. Call parse_with_context first." unless @h_metrics

        return nil if glyph_id >= num_glyphs || glyph_id.negative?

        if glyph_id < h_metrics.length
          # Direct lookup in hMetrics array
          h_metrics[glyph_id]
        else
          # Use last advance width with indexed LSB
          lsb_index = glyph_id - h_metrics.length
          {
            advance_width: h_metrics.last[:advance_width],
            lsb: left_side_bearings[lsb_index],
          }
        end
      end

      # Check if the table has been parsed with context
      #
      # @return [Boolean] True if parsed, false otherwise
      def parsed?
        !@h_metrics.nil?
      end

      # Get the expected minimum size for this table
      #
      # @return [Integer] Minimum size in bytes, or nil if not parsed
      def expected_min_size
        return nil unless parsed?

        # numberOfHMetrics × 4 bytes (uint16 + int16)
        # + (numGlyphs - numberOfHMetrics) × 2 bytes (int16)
        (number_of_h_metrics * 4) + ((num_glyphs - number_of_h_metrics) * 2)
      end

      private

      # Validate context parameters
      #
      # @param number_of_h_metrics [Integer] Number of hMetrics
      # @param num_glyphs [Integer] Total glyphs
      # @raise [ArgumentError] If parameters are invalid
      def validate_context_params(number_of_h_metrics, num_glyphs)
        if number_of_h_metrics.nil? || number_of_h_metrics < 1
          raise ArgumentError,
                "numberOfHMetrics must be >= 1, got: #{number_of_h_metrics.inspect}"
        end

        if num_glyphs.nil? || num_glyphs < 1
          raise ArgumentError,
                "numGlyphs must be >= 1, got: #{num_glyphs.inspect}"
        end

        if number_of_h_metrics > num_glyphs
          raise ArgumentError,
                "numberOfHMetrics (#{number_of_h_metrics}) cannot exceed " \
                "numGlyphs (#{num_glyphs})"
        end
      end

      # Parse horizontal metrics array
      #
      # @param io [StringIO] Input stream
      # @param count [Integer] Number of metrics to parse
      # @return [Array<Hash>] Array of metric hashes
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_h_metrics(io, count)
        metrics = []
        count.times do |i|
          advance_width = read_uint16(io)
          lsb = read_int16(io)

          if advance_width.nil? || lsb.nil?
            raise Fontisan::CorruptedTableError,
                  "Insufficient data for hMetric at index #{i}"
          end

          metrics << { advance_width: advance_width, lsb: lsb }
        end
        metrics
      end

      # Parse left side bearings array
      #
      # @param io [StringIO] Input stream
      # @param count [Integer] Number of LSBs to parse
      # @return [Array<Integer>] Array of LSB values
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_left_side_bearings(io, count)
        return [] if count.zero?

        lsbs = []
        count.times do |i|
          lsb = read_int16(io)

          if lsb.nil?
            raise Fontisan::CorruptedTableError,
                  "Insufficient data for LSB at index #{i}"
          end

          lsbs << lsb
        end
        lsbs
      end

      # Validate that all expected data was parsed
      #
      # @param io [StringIO] Input stream
      # @raise [Fontisan::CorruptedTableError] If unexpected data remains
      def validate_parsed_data!(io)
        remaining = io.read
        return if remaining.nil? || remaining.empty?

        # Some fonts may have padding, which is acceptable
        # Only warn if there's more than 3 bytes of extra data
        if remaining.length > 3
          warn "Warning: hmtx table has #{remaining.length} unexpected " \
               "bytes after parsing"
        end
      end

      # Read unsigned 16-bit integer
      #
      # @param io [StringIO] Input stream
      # @return [Integer, nil] Value or nil if insufficient data
      def read_uint16(io)
        data = io.read(2)
        return nil if data.nil? || data.length < 2

        data.unpack1("n") # Big-endian unsigned 16-bit
      end

      # Read signed 16-bit integer
      #
      # @param io [StringIO] Input stream
      # @return [Integer, nil] Value or nil if insufficient data
      def read_int16(io)
        data = io.read(2)
        return nil if data.nil? || data.length < 2

        # Unpack as unsigned, then convert to signed
        value = data.unpack1("n")
        value >= 0x8000 ? value - 0x10000 : value
      end
    end
  end
end
