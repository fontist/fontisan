# frozen_string_literal: true

require "bindata"
require "stringio"

module Fontisan
  module Binary
    # Base class for all BinData record definitions
    #
    # Provides common configuration for OpenType binary structures:
    # - Big-endian byte order (OpenType standard)
    # - Common helper methods
    #
    # All table parsers and binary structures should inherit from this class
    # to ensure consistent behavior across the codebase.
    #
    # @example Defining a simple structure
    #   class MyTable < Binary::BaseRecord
    #     uint16 :version
    #     uint16 :count
    #   end
    class BaseRecord < BinData::Record
      endian :big # OpenType uses big-endian byte order

      # Override read to handle nil/empty/String inputs gracefully.
      #
      # String inputs are wrapped in a StringIO so the rest of the
      # read path always works against an IO-like object.
      #
      # @param io [String, IO, StringIO, nil] binary data or IO source
      def self.read(io)
        return new if io.nil?

        io = StringIO.new(io) if io.is_a?(String)
        return new if io.is_a?(StringIO) && io.eof?

        # Store the original data for later parsing
        data = io.read
        io.rewind
        instance = super(io)

        instance.raw_data = data
        instance
      end

      # Get the raw binary data that was read
      #
      # @return [String] Raw binary data
      def raw_data
        @raw_data || to_binary_s
      end

      # Set the raw binary data read from the source.
      attr_writer :raw_data

      # Check if the record is valid
      #
      # @return [Boolean] True if valid, false otherwise
      def valid?
        true
      end

      private

      # Convert 16.16 fixed-point integer to float
      #
      # @param value [Integer] Fixed-point value
      # @return [Float] Floating-point value
      def fixed_to_float(value)
        # Treat as unsigned for the conversion
        unsigned = value & 0xFFFFFFFF
        integer_part = (unsigned >> 16) & 0xFFFF
        fractional_part = unsigned & 0xFFFF

        # Handle sign for the integer part
        integer_part -= 0x10000 if integer_part >= 0x8000

        integer_part + (fractional_part / 65_536.0)
      end
    end
  end
end
