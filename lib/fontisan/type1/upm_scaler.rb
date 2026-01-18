# frozen_string_literal: true

module Fontisan
  module Type1
    # UPM (Units Per Em) Scaler
    #
    # [`UPMScaler`](lib/fontisan/type1/upm_scaler.rb) handles scaling of font metrics
    # from the source font's UPM to a target UPM.
    #
    # Traditional Type 1 fonts use 1000 UPM, while modern TTF fonts typically use
    # 2048 or other values. This scaler converts metrics appropriately.
    #
    # @example Scale to Type 1 standard
    #   scaler = Fontisan::Type1::UPMScaler.type1_standard(font)
    #   scaled_width = scaler.scale(1024)  # => 500 for 2048 UPM font
    #
    # @example Keep native UPM
    #   scaler = Fontisan::Type1::UPMScaler.native(font)
    #   scaled_width = scaler.scale(1024)  # => 1024 (no scaling)
    class UPMScaler
      # @return [Integer] Source font's units per em
      attr_reader :source_upm

      # @return [Integer] Target units per em
      attr_reader :target_upm

      # @return [Rational] Scale factor (target / source)
      attr_reader :scale_factor

      # Initialize a new UPM scaler
      #
      # @param font [Fontisan::Font] Source font
      # @param target_upm [Integer] Target UPM (default: 1000 for Type 1)
      def initialize(font, target_upm: 1000)
        @font = font
        @source_upm = font.units_per_em
        @target_upm = target_upm
        @scale_factor = Rational(target_upm, source_upm)
      end

      # Scale a single value
      #
      # @param value [Integer, Float] Value to scale
      # @return [Integer] Scaled value (rounded)
      def scale(value)
        return 0 if value.nil? || value.zero?

        (value * scale_factor).round
      end

      # Scale an array of values
      #
      # @param values [Array<Integer, Float>] Values to scale
      # @return [Array<Integer>] Scaled values
      def scale_array(values)
        values.map { |v| scale(v) }
      end

      # Scale a coordinate pair [x, y]
      #
      # @param value [Array<Integer, Float>] Coordinate pair
      # @return [Array<Integer>] Scaled coordinates
      def scale_pair(value)
        [scale(value[0]), scale(value[1])]
      end

      # Scale a bounding box [llx, lly, urx, ury]
      #
      # @param bbox [Array<Integer, Float>] Bounding box
      # @return [Array<Integer>] Scaled bounding box
      def scale_bbox(bbox)
        return nil if bbox.nil?

        bbox.map { |v| scale(v) }
      end

      # Scale a character width
      #
      # @param width [Integer, Float] Character width
      # @return [Integer] Scaled width
      def scale_width(width)
        scale(width)
      end

      # Check if scaling is needed
      #
      # @return [Boolean] True if source and target UPM differ
      def scaling_needed?
        @source_upm != @target_upm
      end

      # Create scaler with native UPM (no scaling)
      #
      # @param font [Fontisan::Font] Source font
      # @return [UPMScaler] Scaler with native UPM
      def self.native(font)
        new(font, target_upm: font.units_per_em)
      end

      # Create scaler with Type 1 standard UPM (1000)
      #
      # @param font [Fontisan::Font] Source font
      # @return [UPMScaler] Scaler with 1000 UPM
      def self.type1_standard(font)
        new(font, target_upm: 1000)
      end

      # Create scaler with custom UPM
      #
      # @param font [Fontisan::Font] Source font
      # @param upm [Integer] Target UPM
      # @return [UPMScaler] Scaler with custom UPM
      def self.custom(font, upm:)
        new(font, target_upm: upm)
      end
    end
  end
end
