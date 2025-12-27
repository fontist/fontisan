# frozen_string_literal: true

module Fontisan
  module Hints
    # Applies rendering hints to TrueType font tables
    #
    # This applier writes TrueType hint data into font-level tables:
    # - fpgm (Font Program) - bytecode executed once at font initialization
    # - prep (Control Value Program) - bytecode for glyph preparation
    # - cvt (Control Values) - array of 16-bit values for hinting metrics
    #
    # The applier ensures proper table structure with correct checksums
    # and does not corrupt the font if hint application fails.
    #
    # @example Apply hints from a HintSet
    #   applier = TrueTypeHintApplier.new
    #   tables = {}
    #   updated_tables = applier.apply(hint_set, tables)
    class TrueTypeHintApplier
      # Apply TrueType hints to font tables
      #
      # @param hint_set [HintSet] Hint data to apply
      # @param tables [Hash] Font tables to update
      # @return [Hash] Updated font tables
      def apply(hint_set, tables)
        return tables if hint_set.nil? || hint_set.empty?
        return tables unless hint_set.format == "truetype"

        # Write fpgm table if present
        if hint_set.font_program && !hint_set.font_program.empty?
          tables["fpgm"] = build_fpgm_table(hint_set.font_program)
        end

        # Write prep table if present
        if hint_set.control_value_program && !hint_set.control_value_program.empty?
          tables["prep"] = build_prep_table(hint_set.control_value_program)
        end

        # Write cvt table if present
        if hint_set.control_values && !hint_set.control_values.empty?
          tables["cvt "] = build_cvt_table(hint_set.control_values)
        end

        # Future enhancement: Apply per-glyph hints to glyf table
        # For now, font-level tables only

        tables
      end

      private

      # Build fpgm (Font Program) table
      #
      # @param program_data [String] Raw bytecode
      # @return [Hash] Table structure with tag, data, and checksum
      def build_fpgm_table(program_data)
        {
          tag: "fpgm",
          data: program_data,
          checksum: calculate_checksum(program_data),
        }
      end

      # Build prep (Control Value Program) table
      #
      # @param program_data [String] Raw bytecode
      # @return [Hash] Table structure with tag, data, and checksum
      def build_prep_table(program_data)
        {
          tag: "prep",
          data: program_data,
          checksum: calculate_checksum(program_data),
        }
      end

      # Build cvt (Control Values) table
      #
      # CVT values are 16-bit signed integers (FWORD) in big-endian format.
      # Each value represents a design-space coordinate used for hinting.
      #
      # @param control_values [Array<Integer>] Array of 16-bit signed values
      # @return [Hash] Table structure with tag, data, and checksum
      def build_cvt_table(control_values)
        # Pack as 16-bit big-endian signed integers (s> = signed big-endian)
        data = control_values.pack("s>*")

        {
          tag: "cvt ",
          data: data,
          checksum: calculate_checksum(data),
        }
      end

      # Calculate OpenType table checksum
      #
      # OpenType spec requires tables to be checksummed as 32-bit unsigned
      # integers in big-endian format. The table is padded to a multiple of
      # 4 bytes with zeros before checksum calculation.
      #
      # @param data [String] Table data
      # @return [Integer] 32-bit checksum
      def calculate_checksum(data)
        # Pad to 4-byte boundary with zeros
        padding_needed = (4 - data.length % 4) % 4
        padded = data + ("\x00" * padding_needed)

        # Sum as 32-bit unsigned integers in big-endian
        checksum = 0
        (0...padded.length).step(4) do |i|
          checksum = (checksum + padded[i, 4].unpack1("N")) & 0xFFFFFFFF
        end

        checksum
      end
    end
  end
end
