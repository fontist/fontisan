# frozen_string_literal: true

require_relative "dict_builder"

module Fontisan
  module Tables
    class Cff
      # Builds CFF Private DICT with hint parameters
      #
      # Private DICT contains font-level hint information used for rendering quality.
      # This writer validates hint parameters against CFF spec limits and serializes
      # them into binary DICT format.
      #
      # Supported hint parameters:
      # - blue_values: Alignment zones (max 14 values, pairs)
      # - other_blues: Additional zones (max 10 values, pairs)
      # - family_blues: Family alignment zones (max 14 values, pairs)
      # - family_other_blues: Family zones (max 10 values, pairs)
      # - std_hw: Standard horizontal stem width
      # - std_vw: Standard vertical stem width
      # - stem_snap_h: Horizontal stem snap widths (max 12)
      # - stem_snap_v: Vertical stem snap widths (max 12)
      # - blue_scale, blue_shift, blue_fuzz: Overshoot parameters
      # - force_bold: Bold flag
      # - language_group: 0=Latin, 1=CJK
      class PrivateDictWriter
        # CFF specification limits for hint parameters
        HINT_LIMITS = {
          blue_values: { max: 14, pairs: true },
          other_blues: { max: 10, pairs: true },
          family_blues: { max: 14, pairs: true },
          family_other_blues: { max: 10, pairs: true },
          stem_snap_h: { max: 12 },
          stem_snap_v: { max: 12 },
        }.freeze

        # Initialize writer with optional source Private DICT
        #
        # @param source_dict [PrivateDict, nil] Source to copy non-hint params from
        def initialize(source_dict = nil)
          @params = {}
          parse_source(source_dict) if source_dict
        end

        # Update hint parameters
        #
        # @param hint_params [Hash] Hint parameters to add/update
        # @raise [ArgumentError] If parameters are invalid
        def update_hints(hint_params)
          validate!(hint_params)
          @params.merge!(hint_params.transform_keys(&:to_sym))
        end

        # Serialize to binary DICT format
        #
        # @return [String] Binary DICT data
        def serialize
          DictBuilder.build(@params)
        end

        # Get serialized size in bytes
        #
        # @return [Integer] Size in bytes
        def size
          serialize.bytesize
        end

        private

        # Parse non-hint parameters from source Private DICT
        #
        # @param source_dict [PrivateDict] Source dictionary
        def parse_source(source_dict)
          return unless source_dict.respond_to?(:to_h)

          # Extract only non-hint params (subrs, widths)
          @params = source_dict.to_h.select do |k, _|
            %i[subrs default_width_x nominal_width_x].include?(k)
          end
        end

        # Validate hint parameters against CFF spec
        #
        # @param params [Hash] Hint parameters
        # @raise [ArgumentError] If validation fails
        def validate!(params)
          params.each do |key, value|
            k = key.to_sym
            validate_hint_param(k, value)
          end
        end

        # Validate individual hint parameter
        #
        # @param key [Symbol] Parameter name
        # @param value [Object] Parameter value
        # @raise [ArgumentError] If validation fails
        def validate_hint_param(key, value)
          # Check array limits
          if HINT_LIMITS[key]
            raise ArgumentError, "#{key} invalid" unless value.is_a?(Array)

            if value.length > HINT_LIMITS[key][:max]
              raise ArgumentError,
                    "#{key} too long"
            end
            if HINT_LIMITS[key][:pairs] && value.length.odd?
              raise ArgumentError, "#{key} must be pairs"
            end
          end

          # Check value-specific constraints
          case key
          when :std_hw, :std_vw
            raise ArgumentError, "#{key} negative" if value.negative?
          when :blue_scale
            raise ArgumentError, "#{key} not positive" if value <= 0
          when :blue_shift, :blue_fuzz
            raise ArgumentError, "#{key} invalid" unless value.is_a?(Numeric)
          when :force_bold
            raise ArgumentError, "#{key} must be 0 or 1" unless [0,
                                                                 1].include?(value)
          when :language_group
            raise ArgumentError, "#{key} must be 0 or 1" unless [0,
                                                                 1].include?(value)
          end
        end
      end
    end
  end
end
