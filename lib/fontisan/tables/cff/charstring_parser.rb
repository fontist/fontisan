# frozen_string_literal: true

require "stringio"

module Fontisan
  module Tables
    class Cff
      # CharString parser that converts binary CharString data to operation list
      #
      # Unlike [`CharString`](lib/fontisan/tables/cff/charstring.rb) which
      # interprets and executes CharStrings for rendering, CharStringParser
      # parses CharStrings into a list of operations that can be modified and
      # rebuilt. This enables CharString manipulation for hint injection,
      # subroutine optimization, and other transformations.
      #
      # Operation Format:
      # ```ruby
      # {
      #   type: :operator,
      #   name: :rmoveto,
      #   operands: [100, 200]
      # }
      # ```
      #
      # Reference: Adobe Type 2 CharString Format
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5177.Type2.pdf
      #
      # @example Parse a CharString
      #   parser = CharStringParser.new(charstring_data)
      #   operations = parser.parse
      #   operations.each { |op| puts "#{op[:name]} #{op[:operands]}" }
      class CharStringParser
        # Type 2 CharString operators (from CharString class)
        OPERATORS = {
          # Path construction operators
          1 => :hstem,
          3 => :vstem,
          4 => :vmoveto,
          5 => :rlineto,
          6 => :hlineto,
          7 => :vlineto,
          8 => :rrcurveto,
          10 => :callsubr,
          11 => :return,
          14 => :endchar,
          18 => :hstemhm,
          19 => :hintmask,
          20 => :cntrmask,
          21 => :rmoveto,
          22 => :hmoveto,
          23 => :vstemhm,
          24 => :rcurveline,
          25 => :rlinecurve,
          26 => :vvcurveto,
          27 => :hhcurveto,
          28 => :shortint,
          29 => :callgsubr,
          30 => :vhcurveto,
          31 => :hvcurveto,
          # 12 prefix for two-byte operators
          [12, 3] => :and,
          [12, 4] => :or,
          [12, 5] => :not,
          [12, 9] => :abs,
          [12, 10] => :add,
          [12, 11] => :sub,
          [12, 12] => :div,
          [12, 14] => :neg,
          [12, 15] => :eq,
          [12, 18] => :drop,
          [12, 20] => :put,
          [12, 21] => :get,
          [12, 22] => :ifelse,
          [12, 23] => :random,
          [12, 24] => :mul,
          [12, 26] => :sqrt,
          [12, 27] => :dup,
          [12, 28] => :exch,
          [12, 29] => :index,
          [12, 30] => :roll,
          [12, 34] => :hflex,
          [12, 35] => :flex,
          [12, 36] => :hflex1,
          [12, 37] => :flex1,
        }.freeze

        # Operators that require hint mask bytes
        HINTMASK_OPERATORS = %i[hintmask cntrmask].freeze

        # @return [String] Binary CharString data
        attr_reader :data

        # @return [Array<Hash>] Parsed operations
        attr_reader :operations

        # Initialize parser with CharString data
        #
        # @param data [String] Binary CharString data
        # @param stem_count [Integer] Number of stem hints (for hintmask)
        def initialize(data, stem_count: 0)
          @data = data
          @stem_count = stem_count
          @operations = []
        end

        # Parse CharString to operation list
        #
        # @return [Array<Hash>] Array of operation hashes
        def parse
          @operations = []
          io = StringIO.new(@data)
          operand_stack = []

          until io.eof?
            byte = io.getbyte

            if operator_byte?(byte)
              # Operator byte - read operator and create operation
              operator = read_operator(io, byte)

              # Read hint mask data if needed
              hint_data = nil
              if HINTMASK_OPERATORS.include?(operator)
                hint_bytes = (@stem_count + 7) / 8
                hint_data = io.read(hint_bytes) if hint_bytes.positive?
              end

              # Create operation
              @operations << {
                type: :operator,
                name: operator,
                operands: operand_stack.dup,
                hint_data: hint_data
              }

              # Clear operand stack
              operand_stack.clear
            else
              # Operand byte - read number and push to stack
              io.pos -= 1
              number = read_number(io)
              operand_stack << number
            end
          end

          @operations
        rescue StandardError => e
          raise CorruptedTableError,
                "Failed to parse CharString: #{e.message}"
        end

        # Update stem count (needed for hintmask operations)
        #
        # @param count [Integer] Number of stem hints
        def stem_count=(count)
          @stem_count = count
        end

        private

        # Check if byte is an operator
        #
        # @param byte [Integer] Byte value
        # @return [Boolean] True if operator byte
        def operator_byte?(byte)
          (byte <= 31 && byte != 28) # Operators are 0-31 except 28 (shortint)
        end

        # Read operator from CharString
        #
        # @param io [StringIO] Input stream
        # @param first_byte [Integer] First operator byte
        # @return [Symbol] Operator name
        def read_operator(io, first_byte)
          if first_byte == 12
            # Two-byte operator
            second_byte = io.getbyte
            raise CorruptedTableError, "Unexpected end of CharString" if
              second_byte.nil?

            operator_key = [first_byte, second_byte]
            OPERATORS[operator_key] || :unknown
          else
            # Single-byte operator
            OPERATORS[first_byte] || :unknown
          end
        end

        # Read a number (integer or real) from CharString
        #
        # @param io [StringIO] Input stream
        # @return [Integer, Float] The number value
        def read_number(io)
          byte = io.getbyte
          raise CorruptedTableError, "Unexpected end of CharString" if
            byte.nil?

          case byte
          when 28
            # 3-byte signed integer (16-bit)
            b1 = io.getbyte
            b2 = io.getbyte
            raise CorruptedTableError, "Unexpected end of CharString reading shortint" if
              b1.nil? || b2.nil?
            value = (b1 << 8) | b2
            value > 0x7FFF ? value - 0x10000 : value
          when 32..246
            # Small integer: -107 to +107
            byte - 139
          when 247..250
            # Positive 2-byte integer: +108 to +1131
            b2 = io.getbyte
            raise CorruptedTableError, "Unexpected end of CharString reading positive integer" if
              b2.nil?
            (byte - 247) * 256 + b2 + 108
          when 251..254
            # Negative 2-byte integer: -108 to -1131
            b2 = io.getbyte
            raise CorruptedTableError, "Unexpected end of CharString reading negative integer" if
              b2.nil?
            -(byte - 251) * 256 - b2 - 108
          when 255
            # 5-byte signed integer (32-bit) as fixed-point 16.16
            bytes = io.read(4)
            raise CorruptedTableError, "Unexpected end of CharString reading fixed-point" if
              bytes.nil? || bytes.length < 4
            value = bytes.unpack1("l>") # Signed 32-bit big-endian
            value / 65536.0 # Convert to float
          else
            raise CorruptedTableError,
                  "Invalid CharString number byte: #{byte}"
          end
        end
      end
    end
  end
end