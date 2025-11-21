# frozen_string_literal: true

require "stringio"
require_relative "../../binary/base_record"

module Fontisan
  module Tables
    class Cff
      # CFF DICT (Dictionary) structure parser
      #
      # DICTs in CFF use a compact operand-operator format similar to PostScript.
      # Operands are pushed onto a stack, then an operator consumes them.
      #
      # Operand Encoding:
      # - 32-247: Small integers (values -107 to +107)
      # - 28: 3-byte signed integer follows
      # - 29: 5-byte signed integer follows
      # - 30: Real number (nibble-encoded)
      # - 247-254: 2-byte signed integers
      # - 255: Reserved
      # - 0-21, 22-27: Operators (single or two-byte)
      #
      # Reference: CFF specification section 4 "DICT Data"
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
      #
      # @example Parsing a DICT
      #   data = top_dict_index[0]
      #   dict = Fontisan::Tables::Cff::Dict.new(data)
      #   puts dict[:charset]  # => offset to charset
      #   puts dict[:version]  # => version SID
      class Dict
        # Common DICT operators shared across Top DICT and Private DICT
        #
        # Key: operator byte(s), Value: operator name symbol
        OPERATORS = {
          0 => :version,
          1 => :notice,
          2 => :full_name,
          3 => :family_name,
          4 => :weight,
          [12, 0] => :copyright,
          [12, 1] => :is_fixed_pitch,
          [12, 2] => :italic_angle,
          [12, 3] => :underline_position,
          [12, 4] => :underline_thickness,
          [12, 5] => :paint_type,
          [12, 6] => :charstring_type,
          [12, 7] => :font_matrix,
          [12, 8] => :stroke_width,
          [12, 20] => :synthetic_base,
          [12, 21] => :postscript,
          [12, 22] => :base_font_name,
          [12, 23] => :base_font_blend,
        }.freeze

        # @return [Hash] Parsed dictionary as key-value pairs
        attr_reader :dict

        # @return [String] Raw binary data of the DICT
        attr_reader :data

        # Initialize and parse a DICT from binary data
        #
        # @param data [String, IO, StringIO] Binary DICT data
        def initialize(data)
          @data = data.is_a?(String) ? data : data.read
          @dict = {}
          @io = StringIO.new(@data)
          parse!
        end

        # Get a value from the dictionary by operator name
        #
        # @param key [Symbol] Operator name (e.g., :charset, :encoding)
        # @return [Object, nil] Value for the operator, or nil if not present
        def [](key)
          @dict[key]
        end

        # Set a value in the dictionary
        #
        # @param key [Symbol] Operator name
        # @param value [Object] Value to set
        def []=(key, value)
          @dict[key] = value
        end

        # Check if the dictionary contains a specific operator
        #
        # @param key [Symbol] Operator name
        # @return [Boolean] True if operator is present
        def has_key?(key)
          @dict.key?(key)
        end

        # Get all operator names in this DICT
        #
        # @return [Array<Symbol>] Array of operator names
        def keys
          @dict.keys
        end

        # Get all values in this DICT
        #
        # @return [Array<Object>] Array of values
        def values
          @dict.values
        end

        # Convert DICT to Hash
        #
        # @return [Hash] Dictionary as hash
        def to_h
          @dict.dup
        end

        # Number of entries in the DICT
        #
        # @return [Integer] Entry count
        def size
          @dict.size
        end

        # Check if DICT is empty
        #
        # @return [Boolean] True if no entries
        def empty?
          @dict.empty?
        end

        private

        # Parse the DICT structure
        #
        # DICTs use a stack-based format:
        # 1. Read operands and push onto operand stack
        # 2. When operator is encountered, pop operands and process
        # 3. Store result in dictionary
        def parse!
          operand_stack = []

          until @io.eof?
            byte = read_byte

            if operator?(byte)
              # Process operator with current operand stack
              operator = read_operator(byte)
              process_operator(operator, operand_stack)
              operand_stack.clear
            else
              # Read operand and push onto stack
              @io.pos -= 1 # Unread the byte
              operand = read_operand
              operand_stack << operand
            end
          end
        end

        # Check if a byte is an operator
        #
        # @param byte [Integer] Byte value
        # @return [Boolean] True if operator byte
        def operator?(byte)
          # Operators are 0-21 or escape (12) followed by another byte
          byte <= 21 || byte == 12
        end

        # Read an operator (single or two-byte)
        #
        # @param first_byte [Integer] First operator byte
        # @return [Integer, Array<Integer>] Operator identifier
        def read_operator(first_byte)
          if first_byte == 12
            # Two-byte operator (escape operator)
            second_byte = read_byte
            [first_byte, second_byte]
          else
            # Single-byte operator
            first_byte
          end
        end

        # Process an operator with its operands
        #
        # @param operator [Integer, Array<Integer>] Operator identifier
        # @param operands [Array] Operand stack
        def process_operator(operator, operands)
          operator_name = operator_name_for(operator)
          return unless operator_name

          # Store the operand(s) in the dictionary
          # Most operators take a single operand, some take arrays
          value = operands.size == 1 ? operands.first : operands.dup
          @dict[operator_name] = value
        end

        # Get the operator name for an operator byte(s)
        #
        # @param operator [Integer, Array<Integer>] Operator identifier
        # @return [Symbol, nil] Operator name or nil if unknown
        def operator_name_for(operator)
          # Check in the OPERATORS table (common operators)
          self.class::OPERATORS[operator] || derived_operators[operator]
        end

        # Get derived class-specific operators
        #
        # Subclasses override this to add their specific operators
        #
        # @return [Hash] Additional operators for this DICT type
        def derived_operators
          {}
        end

        # Read a single operand from the DICT data
        #
        # Operands can be:
        # - Small integers (1 byte: 32-246 or 247-254 with next byte)
        # - Medium integers (3 bytes: 28 + 2 bytes)
        # - Large integers (5 bytes: 29 + 4 bytes)
        # - Real numbers (30 + nibble-encoded decimal)
        #
        # @return [Integer, Float] The operand value
        def read_operand
          byte = read_byte

          case byte
          when 28
            # 3-byte signed integer
            read_int16
          when 29
            # 5-byte signed integer
            read_int32
          when 30
            # Real number (nibble-encoded)
            read_real
          when 32..246
            # Small integer: -107 to +107
            byte - 139
          when 247..250
            # Positive 2-byte integer
            second_byte = read_byte
            (byte - 247) * 256 + second_byte + 108
          when 251..254
            # Negative 2-byte integer
            second_byte = read_byte
            -(byte - 251) * 256 - second_byte - 108
          else
            raise CorruptedTableError,
                  "Invalid DICT operand byte: #{byte}"
          end
        end

        # Read a 16-bit signed integer (big-endian)
        #
        # @return [Integer] Signed 16-bit value
        def read_int16
          bytes = @io.read(2)
          if bytes.nil? || bytes.bytesize < 2
            raise CorruptedTableError,
                  "Unexpected end of DICT"
          end

          value = bytes.unpack1("n") # Unsigned 16-bit big-endian
          # Convert to signed
          value > 0x7FFF ? value - 0x10000 : value
        end

        # Read a 32-bit signed integer (big-endian)
        #
        # @return [Integer] Signed 32-bit value
        def read_int32
          bytes = @io.read(4)
          if bytes.nil? || bytes.bytesize < 4
            raise CorruptedTableError,
                  "Unexpected end of DICT"
          end

          value = bytes.unpack1("N") # Unsigned 32-bit big-endian
          # Convert to signed
          value > 0x7FFFFFFF ? value - 0x100000000 : value
        end

        # Read a real number (nibble-encoded)
        #
        # Real numbers in CFF are encoded as a sequence of nibbles (4-bit values)
        # where each nibble represents a digit or special character.
        #
        # Nibble values:
        # - 0-9: Decimal digits
        # - a (10): Decimal point
        # - b (11): Positive exponent (E)
        # - c (12): Negative exponent (E-)
        # - d (13): Reserved
        # - e (14): Minus sign
        # - f (15): End of number
        #
        # @return [Float] The decoded real number
        def read_real
          nibbles = []

          loop do
            byte = read_byte
            high_nibble = (byte >> 4) & 0x0F
            low_nibble = byte & 0x0F

            break if high_nibble == 0xF

            nibbles << high_nibble

            break if low_nibble == 0xF

            nibbles << low_nibble
          end

          # Convert nibbles to string representation
          str = +""
          nibbles.each do |nibble|
            case nibble
            when 0..9
              str << nibble.to_s
            when 0xa # Decimal point
              str << "."
            when 0xb # Positive exponent (E)
              str << "e"
            when 0xc # Negative exponent (E-)
              str << "e-"
            when 0xe # Minus sign
              str << "-"
            when 0xd, 0xf # Reserved or end marker
              # Skip
            end
          end

          # Convert to float
          str.to_f
        end

        # Read a single byte from the IO
        #
        # @return [Integer] Byte value (0-255)
        def read_byte
          byte = @io.getbyte
          raise CorruptedTableError, "Unexpected end of DICT" if byte.nil?

          byte
        end
      end
    end
  end
end
