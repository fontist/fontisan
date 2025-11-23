# frozen_string_literal: true

require "stringio"

module Fontisan
  module Tables
    class Cff
      # CFF DICT (Dictionary) structure builder
      #
      # [`DictBuilder`](lib/fontisan/tables/cff/dict_builder.rb) constructs
      # binary DICT structures from hash representations. DICTs in CFF use a
      # compact operand-operator format similar to PostScript.
      #
      # The builder encodes operands in various compact formats and writes
      # operators according to the CFF specification.
      #
      # Operand Encoding:
      # - Small integers (-107 to +107): Single byte (32-246)
      # - Medium integers (108 to 1131): Two bytes (247-250 + byte)
      # - Medium integers (-1131 to -108): Two bytes (251-254 + byte)
      # - Larger integers: Three bytes (28 + 2 bytes) or five bytes (29 + 4 bytes)
      # - Real numbers: Nibble-encoded (30 + nibbles + 0xF terminator)
      #
      # Operators:
      # - Single-byte: 0-21
      # - Two-byte: 12 followed by second byte
      #
      # Reference: CFF specification section 4 "DICT Data"
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
      #
      # @example Building a DICT
      #   dict_hash = { version: 391, notice: 392, charset: 0 }
      #   dict_data = Fontisan::Tables::Cff::DictBuilder.build(dict_hash)
      class DictBuilder
        # Operator mapping (name => byte(s))
        OPERATORS = {
          version: 0,
          notice: 1,
          full_name: 2,
          family_name: 3,
          weight: 4,
          charset: 15,
          encoding: 16,
          charstrings: 17,
          private: 18,
          copyright: [12, 0],
          is_fixed_pitch: [12, 1],
          italic_angle: [12, 2],
          underline_position: [12, 3],
          underline_thickness: [12, 4],
          paint_type: [12, 5],
          charstring_type: [12, 6],
          font_matrix: [12, 7],
          stroke_width: [12, 8],
          synthetic_base: [12, 20],
          postscript: [12, 21],
          base_font_name: [12, 22],
          base_font_blend: [12, 23],
          # Private DICT operators
          subrs: 19,
          default_width_x: 20,
          nominal_width_x: 21,
        }.freeze

        # Build DICT structure from hash
        #
        # @param dict_hash [Hash] Hash of operator => value pairs
        # @return [String] Binary DICT data
        # @raise [ArgumentError] If dict_hash is invalid
        def self.build(dict_hash)
          validate_dict!(dict_hash)

          return "".b if dict_hash.empty?

          output = StringIO.new("".b)

          # Encode each operator with its operands
          dict_hash.each do |operator_name, value|
            # Get operator bytes
            operator_bytes = operator_for_name(operator_name)
            raise ArgumentError, "Unknown operator: #{operator_name}" unless operator_bytes

            # Write operands (value can be single value or array)
            if value.is_a?(Array)
              value.each { |v| write_operand(output, v) }
            else
              write_operand(output, value)
            end

            # Write operator
            write_operator(output, operator_bytes)
          end

          output.string
        end

        # Validate dict parameter
        #
        # @param dict_hash [Object] Dictionary to validate
        # @raise [ArgumentError] If dict_hash is invalid
        def self.validate_dict!(dict_hash)
          unless dict_hash.is_a?(Hash)
            raise ArgumentError,
                  "dict_hash must be Hash, got: #{dict_hash.class}"
          end
        end
        private_class_method :validate_dict!

        # Get operator bytes for operator name
        #
        # @param operator_name [Symbol] Operator name
        # @return [Integer, Array<Integer>, nil] Operator byte(s) or nil
        def self.operator_for_name(operator_name)
          OPERATORS[operator_name]
        end
        private_class_method :operator_for_name

        # Write an operand value to output
        #
        # @param io [StringIO] Output stream
        # @param value [Integer, Float] Operand value
        def self.write_operand(io, value)
          if value.is_a?(Float)
            write_real(io, value)
          else
            write_integer(io, value)
          end
        end
        private_class_method :write_operand

        # Write an integer operand
        #
        # @param io [StringIO] Output stream
        # @param value [Integer] Integer value
        def self.write_integer(io, value)
          if value >= -107 && value <= 107
            # Single byte: 32-246 represents -107 to +107
            io.putc(value + 139)
          elsif value >= 108 && value <= 1131
            # Positive two-byte: 247-250
            adjusted = value - 108
            b0 = 247 + (adjusted / 256)
            b1 = adjusted % 256
            io.putc(b0)
            io.putc(b1)
          elsif value >= -1131 && value <= -108
            # Negative two-byte: 251-254
            adjusted = -value - 108
            b0 = 251 + (adjusted / 256)
            b1 = adjusted % 256
            io.putc(b0)
            io.putc(b1)
          elsif value >= -32768 && value <= 32767
            # Three-byte signed 16-bit
            io.putc(28)
            io.write([value].pack("s>")) # Signed 16-bit big-endian
          else
            # Five-byte signed 32-bit
            io.putc(29)
            io.write([value].pack("l>")) # Signed 32-bit big-endian
          end
        end
        private_class_method :write_integer

        # Write a real number operand
        #
        # Real numbers are encoded using nibbles (4-bit values).
        # Each nibble represents a digit or special character.
        #
        # Nibble values:
        # - 0-9: Decimal digits
        # - a (10): Decimal point
        # - b (11): Positive exponent (E)
        # - c (12): Negative exponent (E-)
        # - e (14): Minus sign
        # - f (15): End of number
        #
        # @param io [StringIO] Output stream
        # @param value [Float] Real number value
        def self.write_real(io, value)
          io.putc(30) # Real number marker

          # Convert to string representation
          str = value.to_s

          # Handle special cases
          str = "0" if str == "0.0"

          # Convert string to nibbles
          nibbles = []

          str.each_char do |char|
            case char
            when "0".."9"
              nibbles << char.to_i
            when "."
              nibbles << 0xa
            when "-"
              nibbles << 0xe
            when "e", "E"
              # Check if next char is minus
              nibbles << 0xb # Default to positive exponent
            end
          end

          # Handle negative exponent
          if str.include?("e-") || str.include?("E-")
            # Replace last 0xb with 0xc
            exp_index = nibbles.rindex(0xb)
            nibbles[exp_index] = 0xc if exp_index
          end

          # Add terminator
          nibbles << 0xf

          # Pack nibbles into bytes
          nibbles.each_slice(2) do |high, low|
            low ||= 0xf # Pad with terminator if odd number
            byte = (high << 4) | low
            io.putc(byte)
          end
        end
        private_class_method :write_real

        # Write an operator to output
        #
        # @param io [StringIO] Output stream
        # @param operator_bytes [Integer, Array<Integer>] Operator byte(s)
        def self.write_operator(io, operator_bytes)
          if operator_bytes.is_a?(Array)
            # Two-byte operator
            operator_bytes.each { |byte| io.putc(byte) }
          else
            # Single-byte operator
            io.putc(operator_bytes)
          end
        end
        private_class_method :write_operator
      end
    end
  end
end
