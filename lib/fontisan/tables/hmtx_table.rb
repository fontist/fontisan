# frozen_string_literal: true

require_relative "../sfnt_table"
require_relative "hmtx"

module Fontisan
  module Tables
    # OOP representation of the 'hmtx' (Horizontal Metrics) table
    #
    # The hmtx table contains horizontal metrics for each glyph in the font,
    # providing advance width and left sidebearing values needed for proper
    # glyph positioning and text layout.
    #
    # This class extends SfntTable to provide hmtx-specific convenience
    # methods for accessing glyph metrics. The hmtx table requires context
    # from the hhea and maxp tables to function properly.
    #
    # @example Accessing horizontal metrics
    #   hmtx = font.sfnt_table("hmtx")
    #   hhea = font.table("hhea")
    #   maxp = font.table("maxp")
    #
    #   hmtx.parse_with_context(hhea.number_of_h_metrics, maxp.num_glyphs)
    #   metric = hmtx.metric_for(42)  # Get glyph metrics
    #   metric[:advance_width] # => 1000
    #   metric[:lsb]         # => 50
    class HmtxTable < SfntTable
      # Cache for context tables
      attr_reader :hhea_table, :maxp_table

      # Parse the hmtx table with required context
      #
      # The hmtx table cannot be used without context from hhea and maxp tables.
      #
      # @param number_of_h_metrics [Integer] Number of LongHorMetric records (from hhea)
      # @param num_glyphs [Integer] Total number of glyphs (from maxp)
      # @return [self] Returns self for chaining
      # @raise [ArgumentError] if context is invalid
      def parse_with_context(number_of_h_metrics, num_glyphs)
        unless number_of_h_metrics && num_glyphs
          raise ArgumentError,
                "hmtx table requires number_of_h_metrics and num_glyphs"
        end

        @number_of_h_metrics = number_of_h_metrics
        @num_glyphs = num_glyphs

        # Ensure parsed data is loaded
        parse

        # Parse with context
        parsed.parse_with_context(number_of_h_metrics, num_glyphs)

        self
      end

      # Check if table has been parsed with context
      #
      # @return [Boolean] true if context is available
      def has_context?
        !@number_of_h_metrics.nil? && !@num_glyphs.nil?
      end

      # Get horizontal metrics for a glyph
      #
      # @param glyph_id [Integer] Glyph ID (0-based)
      # @return [Hash, nil] Hash with :advance_width and :lsb keys, or nil
      # @raise [ArgumentError] if context not set
      def metric_for(glyph_id)
        ensure_context!
        return nil unless parsed

        parsed.metric_for(glyph_id)
      end

      # Get advance width for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Integer, nil] Advance width in FUnits, or nil
      def advance_width_for(glyph_id)
        metric = metric_for(glyph_id)
        metric&.dig(:advance_width)
      end

      # Get left sidebearing for a glyph
      #
      # @param glyph_id [integer] Glyph ID
      # @return [Integer, nil] Left sidebearing in FUnits, or nil
      def lsb_for(glyph_id)
        metric = metric_for(glyph_id)
        metric&.dig(:lsb)
      end

      # Get number of horizontal metrics
      #
      # @return [Integer, nil] Number of hMetrics, or nil if not parsed
      def number_of_h_metrics
        return @number_of_h_metrics if @number_of_h_metrics
        return nil unless parsed

        parsed.number_of_h_metrics
      end

      # Get total number of glyphs
      #
      # @return [Integer, nil] Total glyph count, or nil if not parsed
      def num_glyphs
        return @num_glyphs if @num_glyphs
        return nil unless parsed

        parsed.num_glyphs
      end

      # Check if a glyph has its own metrics
      #
      # Glyphs with ID < numberOfHMetrics have their own advance width
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Boolean] true if glyph has unique metrics
      def has_unique_metrics?(glyph_id)
        num = number_of_h_metrics
        return false if num.nil?

        glyph_id < num
      end

      # Get all advance widths
      #
      # @return [Array<Integer>] Array of advance widths
      def all_advance_widths
        return [] unless has_context?

        (0...num_glyphs).map { |gid| advance_width_for(gid) || 0 }
      end

      # Get all left sidebearings
      #
      # @return [Array<Integer>] Array of LSB values
      def all_lsbs
        return [] unless has_context?

        (0...num_glyphs).map { |gid| lsb_for(gid) || 0 }
      end

      # Get metrics statistics
      #
      # @return [Hash] Statistics about horizontal metrics
      def statistics
        return {} unless has_context?

        widths = all_advance_widths
        lsbs = all_lsbs

        {
          num_glyphs: num_glyphs,
          number_of_h_metrics: number_of_h_metrics,
          min_advance_width: widths.min,
          max_advance_width: widths.max,
          avg_advance_width: widths.sum.fdiv(widths.size).round(2),
          min_lsb: lsbs.min,
          max_lsb: lsbs.max,
        }
      end

      private

      # Ensure context tables are set
      #
      # @raise [ArgumentError] if context not set
      def ensure_context!
        unless has_context?
          raise ArgumentError,
                "hmtx table requires context. " \
                "Call parse_with_context(number_of_h_metrics, num_glyphs) first"
        end
      end

      protected

      # Validate the parsed hmtx table
      #
      # @return [Boolean] true if valid
      # @raise [InvalidFontError] if hmtx table is invalid
      def validate_parsed_table?
        # Hmtx table validation requires context, so we can't validate here
        # Validation is deferred until context is provided
        true
      end
    end
  end
end
