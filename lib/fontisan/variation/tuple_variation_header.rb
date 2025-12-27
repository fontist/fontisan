# frozen_string_literal: true

require_relative "../binary/base_record"

module Fontisan
  module Variation
    # Tuple variation header structure
    #
    # Used by both gvar and cvar tables to describe variation tuples.
    # Each tuple header contains metadata about peak coordinates,
    # intermediate regions, and point number handling.
    class TupleVariationHeader < Binary::BaseRecord
      uint16 :variation_data_size
      uint16 :tuple_index

      # Tuple index flags
      EMBEDDED_PEAK_TUPLE = 0x8000
      INTERMEDIATE_REGION = 0x4000
      PRIVATE_POINT_NUMBERS = 0x2000
      TUPLE_INDEX_MASK = 0x0FFF

      # Check if tuple has embedded peak coordinates
      #
      # @return [Boolean] True if embedded
      def embedded_peak_tuple?
        (tuple_index & EMBEDDED_PEAK_TUPLE) != 0
      end

      # Check if tuple has intermediate region
      #
      # @return [Boolean] True if intermediate region
      def intermediate_region?
        (tuple_index & INTERMEDIATE_REGION) != 0
      end

      # Check if tuple has private point numbers
      #
      # @return [Boolean] True if private points
      def private_point_numbers?
        (tuple_index & PRIVATE_POINT_NUMBERS) != 0
      end

      # Get shared tuple index
      #
      # @return [Integer] Tuple index
      def shared_tuple_index
        tuple_index & TUPLE_INDEX_MASK
      end
    end
  end
end
