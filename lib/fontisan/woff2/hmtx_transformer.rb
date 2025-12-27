# frozen_string_literal: true

require "stringio"

module Fontisan
  module Woff2
    # Reconstructs hmtx table from WOFF2 transformed format
    #
    # WOFF2 hmtx transformation optimizes horizontal metrics by:
    # - Using variable-length encoding for advance widths
    # - Optionally deriving LSB from glyf bounding boxes
    # - Omitting redundant trailing advance widths
    #
    # See: https://www.w3.org/TR/WOFF2/#hmtx_table_format
    #
    # @example Reconstructing hmtx table
    #   hmtx_data = HmtxTransformer.reconstruct(
    #     transformed_data,
    #     num_glyphs,
    #     number_of_h_metrics
    #   )
    class HmtxTransformer
      # Flags for hmtx transformation
      HMTX_FLAG_EXPLICIT_ADVANCE_WIDTHS = 0x01
      HMTX_FLAG_EXPLICIT_LSB_VALUES = 0x02
      HMTX_FLAG_SYMMETRIC = 0x04

      # Reconstruct hmtx table from transformed data
      #
      # @param transformed_data [String] The transformed hmtx table data
      # @param num_glyphs [Integer] Number of glyphs
      # @param num_h_metrics [Integer] From hhea.numberOfHMetrics
      # @param glyf_lsbs [Array<Integer>, nil] LSB values from glyf bboxes (optional)
      # @return [String] Standard hmtx table data
      # @raise [InvalidFontError] If data is corrupted or invalid
      def self.reconstruct(transformed_data, num_glyphs, num_h_metrics, glyf_lsbs = nil)
        io = StringIO.new(transformed_data)

        # Read transformation flags
        flags = read_uint8(io)

        # Read advance widths
        advance_widths = []

        if (flags & HMTX_FLAG_EXPLICIT_ADVANCE_WIDTHS).zero?
          # Proportional encoding - read deltas
          # First advance width is explicit
          first_advance = read_255_uint16(io)
          advance_widths << first_advance

          # Remaining are deltas from previous
          (num_h_metrics - 1).times do
            delta = read_int16(io)
            advance_widths << (advance_widths.last + delta)
          end
        else
          # Explicit advance widths in transformed format
          num_h_metrics.times do
            advance_widths << read_255_uint16(io)
          end
        end

        # Read LSB values
        lsbs = []

        if (flags & HMTX_FLAG_EXPLICIT_LSB_VALUES) != 0
          # Explicit LSB values
          num_glyphs.times do
            lsbs << read_int16(io)
          end
        elsif glyf_lsbs
          # Use LSB values from glyf bounding boxes
          lsbs = glyf_lsbs
        else
          # Need to read LSB values for long metrics
          num_h_metrics.times do
            lsbs << read_int16(io)
          end

          # Remaining LSBs for glyphs that share the last advance width
          (num_glyphs - num_h_metrics).times do
            lsbs << read_int16(io)
          end
        end

        # Build standard hmtx table
        build_hmtx_table(advance_widths, lsbs, num_h_metrics, num_glyphs)
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
      # @return [Integer] Decoded value
      def self.read_255_uint16(io)
        code = read_uint8(io)

        case code
        when 255
          759 + read_uint16(io)  # 253 * 3 + value
        when 254
          506 + read_uint16(io)  # 253 * 2 + value
        when 253
          253 + read_uint16(io)
        else
          code
        end
      end

      # Build standard hmtx table format
      #
      # Standard hmtx format:
      # - longHorMetric[numberOfHMetrics] (advanceWidth, lsb pairs)
      # - int16[numGlyphs - numberOfHMetrics] (additional LSBs)
      #
      # @param advance_widths [Array<Integer>] Advance widths
      # @param lsbs [Array<Integer>] Left side bearings
      # @param num_h_metrics [Integer] Number of entries with full hMetrics
      # @param num_glyphs [Integer] Total number of glyphs
      # @return [String] Standard hmtx table data
      def self.build_hmtx_table(advance_widths, lsbs, num_h_metrics, num_glyphs)
        data = +""

        # Write longHorMetric array (advanceWidth + lsb pairs)
        num_h_metrics.times do |i|
          advance_width = advance_widths[i] || advance_widths.last
          lsb = lsbs[i] || 0

          data << [advance_width].pack("n")  # uint16 advanceWidth
          data << [lsb].pack("n")            # int16 lsb
        end

        # Write remaining LSB values
        # These glyphs all share the last advance width from the array
        (num_h_metrics...num_glyphs).each do |i|
          lsb = lsbs[i] || 0
          data << [lsb].pack("n") # int16 lsb
        end

        data
      end

      # Helper methods for reading binary data

      def self.read_uint8(io)
        io.read(1)&.unpack1("C") || raise(EOFError, "Unexpected end of stream")
      end

      def self.read_uint16(io)
        io.read(2)&.unpack1("n") || raise(EOFError, "Unexpected end of stream")
      end

      def self.read_int16(io)
        value = read_uint16(io)
        value > 0x7FFF ? value - 0x10000 : value
      end
    end
  end
end
