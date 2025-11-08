# frozen_string_literal: true

require "bindata"

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

      # Override read to handle nil data gracefully
      def self.read(io)
        return new if io.nil? || (io.respond_to?(:empty?) && io.empty?)

        super
      end

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
