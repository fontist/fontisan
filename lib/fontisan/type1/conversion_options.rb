# frozen_string_literal: true

require_relative "encodings"

module Fontisan
  module Type1
    # Conversion options for Type 1 font generation
    #
    # [`ConversionOptions`](lib/fontisan/type1/conversion_options.rb) provides a unified
    # configuration interface for converting outline fonts (TTF, OTF, TTC, etc.) to
    # Type 1 formats (PFA, PFB, AFM, PFM, INF).
    #
    # @example Create Windows Type 1 options
    #   options = Fontisan::Type1::ConversionOptions.windows_type1
    #   options.upm_scale        # => 1000
    #   options.encoding         # => Fontisan::Type1::Encodings::AdobeStandard
    #   options.format           # => :pfb
    #
    # @example Create custom options
    #   options = Fontisan::Type1::ConversionOptions.new(
    #     upm_scale: 1000,
    #     encoding: Fontisan::Type1::Encodings::Unicode,
    #     format: :pfa
    #   )
    #
    # @see http://www.adobe.com/devnet/font/pdfs/5178.Type1.pdf
    class ConversionOptions
      # @return [Integer, :native] Target UPM (1000 for Type 1, :native to keep source UPM)
      attr_accessor :upm_scale

      # @return [Class] Encoding class (AdobeStandard, ISOLatin1, Unicode)
      attr_accessor :encoding

      # @return [Boolean] Decompose composite glyphs into base glyphs
      attr_accessor :decompose_composites

      # @return [Boolean] Convert quadratic curves to cubic
      attr_accessor :convert_curves

      # @return [Boolean] Apply autohinting to generated Type 1
      attr_accessor :autohint

      # @return [Boolean] Preserve native hinting from source font
      attr_accessor :preserve_hinting

      # @return [Symbol] Output format (:pfb or :pfa)
      attr_accessor :format

      # Default values based on TypeTool 3 and Adobe Type 1 specifications
      DEFAULTS = {
        upm_scale: 1000,
        encoding: Encodings::AdobeStandard,
        decompose_composites: false,
        convert_curves: true,
        autohint: false,
        preserve_hinting: false,
        format: :pfb,
      }.freeze

      # Initialize conversion options
      #
      # @param options [Hash] Option values
      # @option options [Integer, :native] :upm_scale Target UPM (default: 1000)
      # @option options [Class] :encoding Encoding class (default: AdobeStandard)
      # @option options [Boolean] :decompose_composites Decompose composites (default: false)
      # @option options [Boolean] :convert_curves Convert curves (default: true)
      # @option options [Boolean] :autohint Apply autohinting (default: false)
      # @option options [Boolean] :preserve_hinting Preserve hinting (default: false)
      # @option options [Symbol] :format Output format :pfb or :pfa (default: :pfb)
      def initialize(options = {})
        @upm_scale = options[:upm_scale] || DEFAULTS[:upm_scale]
        @encoding = options[:encoding] || DEFAULTS[:encoding]
        @decompose_composites = options[:decompose_composites] || DEFAULTS[:decompose_composites]
        @convert_curves = options.fetch(:convert_curves,
                                        DEFAULTS[:convert_curves])
        @autohint = options[:autohint] || DEFAULTS[:autohint]
        @preserve_hinting = options[:preserve_hinting] || DEFAULTS[:preserve_hinting]
        @format = options[:format] || DEFAULTS[:format]

        validate!
      end

      # Check if UPM scaling is needed
      #
      # @return [Boolean] True if upm_scale is not :native
      def needs_scaling?
        @upm_scale != :native
      end

      # Check if curve conversion is needed
      #
      # @return [Boolean] True if convert_curves is true
      def needs_curve_conversion?
        @convert_curves
      end

      # Check if autohinting is requested
      #
      # @return [Boolean] True if autohint is true
      def needs_autohinting?
        @autohint
      end

      # Convert to hash
      #
      # @return [Hash] Options as hash
      def to_hash
        {
          upm_scale: @upm_scale,
          encoding: @encoding,
          decompose_composites: @decompose_composites,
          convert_curves: @convert_curves,
          autohint: @autohint,
          preserve_hinting: @preserve_hinting,
          format: @format,
        }
      end

      # Create options for Windows Type 1 output
      #
      # @return [ConversionOptions] Options configured for Windows Type 1
      def self.windows_type1
        new(
          upm_scale: 1000,
          encoding: Encodings::AdobeStandard,
          format: :pfb,
        )
      end

      # Create options for Unix Type 1 output
      #
      # @return [ConversionOptions] Options configured for Unix Type 1
      def self.unix_type1
        new(
          upm_scale: 1000,
          encoding: Encodings::AdobeStandard,
          format: :pfa,
        )
      end

      # Create options with native UPM (no scaling)
      #
      # @return [ConversionOptions] Options with native UPM
      def self.native_upm
        new(
          upm_scale: :native,
          encoding: Encodings::Unicode,
          format: :pfb,
        )
      end

      # Create options for ISO-8859-1 encoding
      #
      # @return [ConversionOptions] Options with ISO Latin-1 encoding
      def self.iso_latin1
        new(
          upm_scale: 1000,
          encoding: Encodings::ISOLatin1,
          format: :pfb,
        )
      end

      # Create options with Unicode encoding
      #
      # @return [ConversionOptions] Options with Unicode encoding
      def self.unicode_encoding
        new(
          upm_scale: 1000,
          encoding: Encodings::Unicode,
          format: :pfb,
        )
      end

      # Create options for high-quality output (with curve conversion)
      #
      # @return [ConversionOptions] Options optimized for quality
      def self.high_quality
        new(
          upm_scale: 1000,
          encoding: Encodings::AdobeStandard,
          convert_curves: true,
          decompose_composites: true,
          format: :pfb,
        )
      end

      # Create options for minimal file size
      #
      # @return [ConversionOptions] Options optimized for size
      def self.minimal_size
        new(
          upm_scale: 1000,
          encoding: Encodings::AdobeStandard,
          convert_curves: false,
          decompose_composites: false,
          format: :pfa,
        )
      end

      private

      # Validate options
      #
      # @raise [ArgumentError] If options are invalid
      def validate!
        validate_upm_scale!
        validate_encoding!
        validate_format!
      end

      # Validate UPM scale value
      #
      # @raise [ArgumentError] If upm_scale is invalid
      def validate_upm_scale!
        return if @upm_scale == :native
        return if @upm_scale.is_a?(Integer) && @upm_scale.positive?

        raise ArgumentError,
              "upm_scale must be a positive integer or :native, got: #{@upm_scale.inspect}"
      end

      # Validate encoding class
      #
      # @raise [ArgumentError] If encoding is not a valid encoding class
      def validate_encoding!
        return if @encoding.is_a?(Class) && @encoding < Encodings::Encoding

        raise ArgumentError,
              "encoding must be an Encoding class (AdobeStandard, ISOLatin1, Unicode), got: #{@encoding.inspect}"
      end

      # Validate format value
      #
      # @raise [ArgumentError] If format is not :pfb or :pfa
      def validate_format!
        return if %i[pfb pfa].include?(@format)

        raise ArgumentError,
              "format must be :pfb or :pfa, got: #{@format.inspect}"
      end
    end
  end
end
