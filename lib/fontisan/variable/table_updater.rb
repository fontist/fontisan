# frozen_string_literal: true

require "stringio"

module Fontisan
  module Variable
    # Updates font tables with applied variation deltas
    #
    # This class is responsible for taking original table data and applying
    # calculated deltas to create updated tables for static font instances.
    # It handles:
    # - Updating hmtx with varied advance widths and sidebearings
    # - Updating hhea with varied ascent/descent/line gap
    # - Updating OS/2 with varied metrics
    # - Updating head table's modified timestamp
    #
    # Each update method takes the original table and delta values,
    # then reconstructs the table binary with updated values.
    #
    # @example Update hmtx table
    #   updater = TableUpdater.new
    #   new_hmtx = updater.update_hmtx(
    #     original_hmtx_data,
    #     varied_metrics,
    #     num_h_metrics,
    #     num_glyphs
    #   )
    class TableUpdater
      # Update hmtx table with varied metrics
      #
      # @param original_data [String] Original hmtx table binary
      # @param varied_metrics [Hash<Integer, Hash>] Varied metrics by glyph ID
      #   { glyph_id => { advance_width: 500, lsb: 50 } }
      # @param num_h_metrics [Integer] Number of hMetrics from hhea
      # @param num_glyphs [Integer] Total glyphs from maxp
      # @return [String] Updated hmtx table binary
      def update_hmtx(original_data, varied_metrics, num_h_metrics, num_glyphs)
        io = StringIO.new(original_data)
        io.set_encoding(Encoding::BINARY)

        # Parse original hMetrics
        h_metrics = []
        num_h_metrics.times do
          advance_width = io.read(2)&.unpack1("n") || 0
          lsb = io.read(2)&.unpack1("n") || 0
          lsb = lsb >= 0x8000 ? lsb - 0x10000 : lsb # Convert to signed
          h_metrics << { advance_width: advance_width, lsb: lsb }
        end

        # Parse additional LSBs
        lsb_count = num_glyphs - num_h_metrics
        left_side_bearings = []
        lsb_count.times do
          lsb = io.read(2)&.unpack1("n") || 0
          lsb = lsb >= 0x8000 ? lsb - 0x10000 : lsb
          left_side_bearings << lsb
        end

        # Apply varied metrics
        varied_metrics.each do |glyph_id, metrics|
          if glyph_id < num_h_metrics
            if metrics[:advance_width]
              h_metrics[glyph_id][:advance_width] =
                metrics[:advance_width]
            end
            h_metrics[glyph_id][:lsb] = metrics[:lsb] if metrics[:lsb]
          else
            lsb_index = glyph_id - num_h_metrics
            left_side_bearings[lsb_index] = metrics[:lsb] if metrics[:lsb]
          end
        end

        # Build updated hmtx binary
        output = String.new(encoding: Encoding::BINARY)

        # Write hMetrics
        h_metrics.each do |metric|
          output << [metric[:advance_width]].pack("n")
          # Convert signed LSB to unsigned for packing
          lsb_unsigned = metric[:lsb].negative? ? metric[:lsb] + 0x10000 : metric[:lsb]
          output << [lsb_unsigned].pack("n")
        end

        # Write additional LSBs
        left_side_bearings.each do |lsb|
          lsb_unsigned = lsb.negative? ? lsb + 0x10000 : lsb
          output << [lsb_unsigned].pack("n")
        end

        output
      end

      # Update hhea table with varied metrics
      #
      # @param original_data [String] Original hhea table binary
      # @param varied_metrics [Hash] Varied font metrics
      #   { ascent: 2048, descent: -512, line_gap: 0 }
      # @return [String] Updated hhea table binary
      def update_hhea(original_data, varied_metrics)
        io = StringIO.new(original_data)
        io.set_encoding(Encoding::BINARY)

        # Read all fields
        version = io.read(4)
        ascent = io.read(2)&.unpack1("n") || 0
        ascent = ascent >= 0x8000 ? ascent - 0x10000 : ascent
        descent = io.read(2)&.unpack1("n") || 0
        descent = descent >= 0x8000 ? descent - 0x10000 : descent
        line_gap = io.read(2)&.unpack1("n") || 0
        line_gap = line_gap >= 0x8000 ? line_gap - 0x10000 : line_gap

        # Read remaining fields
        rest = io.read

        # Apply varied metrics
        ascent = varied_metrics[:ascent] if varied_metrics[:ascent]
        descent = varied_metrics[:descent] if varied_metrics[:descent]
        line_gap = varied_metrics[:line_gap] if varied_metrics[:line_gap]

        # Build updated hhea binary
        output = String.new(encoding: Encoding::BINARY)
        output << version

        # Convert signed values to unsigned for packing
        ascent_unsigned = ascent.negative? ? ascent + 0x10000 : ascent
        descent_unsigned = descent.negative? ? descent + 0x10000 : descent
        line_gap_unsigned = line_gap.negative? ? line_gap + 0x10000 : line_gap

        output << [ascent_unsigned].pack("n")
        output << [descent_unsigned].pack("n")
        output << [line_gap_unsigned].pack("n")
        output << rest

        output
      end

      # Update OS/2 table with varied metrics
      #
      # @param original_data [String] Original OS/2 table binary
      # @param varied_metrics [Hash] Varied font metrics from MVAR
      # @return [String] Updated OS/2 table binary
      def update_os2(original_data, varied_metrics)
        return original_data if varied_metrics.empty?

        io = StringIO.new(original_data)
        io.set_encoding(Encoding::BINARY)

        # Read version to determine table size
        io.read(2)&.unpack1("n") || 0
        io.rewind

        # For simplicity, return original if no specific OS/2 metrics to update
        # This would need to be expanded based on MVAR tags present
        original_data
      end

      # Update head table's modified timestamp
      #
      # @param original_data [String] Original head table binary
      # @param timestamp [Time] New modification time
      # @return [String] Updated head table binary
      def update_head_modified(original_data, timestamp = Time.now)
        io = StringIO.new(original_data)
        io.set_encoding(Encoding::BINARY)

        # Read up to modified timestamp
        header = io.read(28) # version through created timestamp
        _old_modified = io.read(8) # Skip old modified timestamp
        rest = io.read # Remaining data

        # Convert Time to LONGDATETIME (seconds since 1904-01-01)
        # Difference between 1904 and 1970 (Unix epoch) is 2082844800 seconds
        longdatetime = timestamp.to_i + 2_082_844_800

        # Build updated head binary
        output = String.new(encoding: Encoding::BINARY)
        output << header
        output << [longdatetime].pack("q>") # 64-bit big-endian signed integer
        output << rest

        output
      end

      # Build updated table with varied values
      #
      # This is a generic helper for building updated table binaries
      #
      # @param original_data [String] Original table binary
      # @param updates [Hash] Hash of offset => new_value pairs
      # @return [String] Updated table binary
      def apply_updates(original_data, updates)
        data = original_data.dup

        updates.each do |offset, value|
          # Handle different value types
          packed_value = case value
                         when Integer
                           if value >= -32768 && value <= 32767
                             # int16
                             unsigned = value.negative? ? value + 0x10000 : value
                             [unsigned].pack("n")
                           else
                             # int32
                             [value].pack("N")
                           end
                         when String
                           value
                         else
                           value.to_s
                         end

          data[offset, packed_value.bytesize] = packed_value
        end

        data
      end
    end
  end
end
