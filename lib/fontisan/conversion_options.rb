# frozen_string_literal: true

module Fontisan
  # Conversion options for font format transformations
  #
  # Defines all options for opening (reading) and generating (writing) fonts
  # during conversion operations. Includes validation, defaults, and presets.
  #
  # @example Using options directly
  #   options = ConversionOptions.new(
  #     from: :ttf,
  #     to: :otf,
  #     opening: { convert_curves: true, scale_to_1000: true },
  #     generating: { hinting_mode: "auto" }
  #   )
  #
  # @example Using recommended options
  #   options = ConversionOptions.recommended(from: :ttf, to: :otf)
  #
  # @example Using a preset
  #   options = ConversionOptions.from_preset(:type1_to_modern)
  class ConversionOptions
    # Opening options (input processing)
    OPENING_OPTIONS = %i[
      decompose_composites
      convert_curves
      scale_to_1000
      scale_from_1000
      autohint
      generate_unicode
      store_custom_tables
      store_native_hinting
      interpret_ot
      read_all_records
      preserve_encoding
    ].freeze

    # Generating options (output processing)
    GENERATING_OPTIONS = %i[
      write_pfm
      write_afm
      write_inf
      select_encoding_automatically
      hinting_mode
      decompose_on_output
      write_custom_tables
      optimize_tables
      reencode_first_256
      encoding_vector
      compression
      transform_tables
      preserve_metadata
      strip_metadata
      target_format
    ].freeze

    # Valid hinting modes
    HINTING_MODES = %w[preserve auto none full].freeze

    # Valid compression modes
    COMPRESSION_MODES = %w[zlib brotli none].freeze

    attr_reader :from, :to, :opening, :generating

    # Initialize conversion options
    #
    # @param from [String, Symbol] Source format
    # @param to [String, Symbol] Target format
    # @param opening [Hash] Opening options
    # @param generating [Hash] Generating options
    def initialize(from:, to:, opening: {}, generating: {})
      @from = self.class.normalize_format(from)
      @to = self.class.normalize_format(to)
      @opening = apply_opening_defaults(opening)
      @generating = apply_generating_defaults(generating)
      validate!
    end

    # Get recommended options for a conversion pair
    #
    # @param from [String, Symbol] Source format
    # @param to [String, Symbol] Target format
    # @return [ConversionOptions] Pre-configured options
    def self.recommended(from:, to:)
      from_sym = normalize_format(from)
      to_sym = normalize_format(to)

      options = RECOMMENDED_OPTIONS.dig(from_sym, to_sym) || {}
      new(
        from: from_sym,
        to: to_sym,
        opening: options[:opening] || {},
        generating: options[:generating] || {},
      )
    end

    # Load options from a named preset
    #
    # @param preset_name [Symbol, String] Preset name
    # @return [ConversionOptions] Pre-configured options
    def self.from_preset(preset_name)
      preset_key = preset_name.to_sym
      preset = PRESETS.fetch(preset_key) do
        raise ArgumentError, "Unknown preset: #{preset_name}. " \
                            "Available: #{PRESETS.keys.join(', ')}"
      end

      new(
        from: preset[:from],
        to: preset[:to],
        opening: preset[:opening] || {},
        generating: preset[:generating] || {},
      )
    end

    # Check if an opening option is set
    #
    # @param key [Symbol] Option key
    # @return [Boolean] true if option is truthy
    def opening_option?(key)
      !!@opening[key]
    end

    # Check if a generating option has a specific value
    #
    # @param key [Symbol] Option key
    # @param value [Object] Value to check
    # @return [Boolean] true if option equals value
    def generating_option?(key, value = true)
      @generating[key] == value
    end

    # Get list of available presets
    #
    # @return [Array<Symbol>] Available preset names
    def self.available_presets
      PRESETS.keys
    end

    private

    # Normalize format symbol
    #
    # @param format [String, Symbol] Format identifier
    # @return [Symbol] Normalized format symbol
    def self.normalize_format(format)
      case format.to_s.downcase
      when "ttf", "truetype", "truetype-tt", "ot-tt" then :ttf
      when "otf", "cff", "opentype", "ot-ps", "opentype-ps" then :otf
      when "type1", "type-1", "t1", "pfb", "pfa" then :type1
      when "ttc" then :ttc
      when "otc" then :otc
      when "dfont", "suitcase" then :dfont
      when "woff" then :woff
      when "woff2" then :woff2
      when "svg" then :svg
      else
        raise ArgumentError, "Unknown format: #{format}. " \
                            "Supported: ttf, otf, type1, ttc, otc, dfont, woff, woff2, svg"
      end
    end

    # Apply default values for opening options
    #
    # @param options [Hash] User-provided options
    # @return [Hash] Options with defaults applied
    def apply_opening_defaults(options)
      defaults = OPENING_DEFAULTS.dig(@from, @to) || {}
      defaults.merge(options)
    end

    # Apply default values for generating options
    #
    # @param options [Hash] User-provided options
    # @return [Hash] Options with defaults applied
    def apply_generating_defaults(options)
      defaults = GENERATING_DEFAULTS.dig(@from, @to) || {}
      defaults.merge(options)
    end

    # Validate options
    #
    # @raise [ArgumentError] If options are invalid
    def validate!
      validate_opening_options!
      validate_generating_options!
    end

    # Validate opening options
    def validate_opening_options!
      @opening.each_key do |key|
        unless OPENING_OPTIONS.include?(key)
          raise ArgumentError, "Unknown opening option: #{key}. " \
                              "Available: #{OPENING_OPTIONS.join(', ')}"
        end
      end
    end

    # Validate generating options
    def validate_generating_options!
      @generating.each_key do |key|
        unless GENERATING_OPTIONS.include?(key)
          raise ArgumentError, "Unknown generating option: #{key}. " \
                              "Available: #{GENERATING_OPTIONS.join(', ')}"
        end
      end

      # Validate hinting_mode
      if @generating[:hinting_mode]
        mode = @generating[:hinting_mode].to_s
        unless HINTING_MODES.include?(mode)
          raise ArgumentError, "Invalid hinting_mode: #{mode}. " \
                              "Available: #{HINTING_MODES.join(', ')}"
        end
      end

      # Validate compression mode
      if @generating[:compression]
        comp = @generating[:compression].to_s
        unless COMPRESSION_MODES.include?(comp)
          raise ArgumentError, "Invalid compression: #{comp}. " \
                              "Available: #{COMPRESSION_MODES.join(', ')}"
        end
      end

      # Validate target_format for collection conversions
      if @generating[:target_format]
        target = @generating[:target_format].to_s
        unless ["ttf", "otf", "preserve"].include?(target)
          raise ArgumentError, "Invalid target_format: #{target}"
        end
      end
    end

    # Default opening options per conversion pair
    OPENING_DEFAULTS = {
      ttf: {
        ttf: { decompose_composites: false, convert_curves: false,
               store_custom_tables: true },
        otf: { convert_curves: true, scale_to_1000: true,
               autohint: true, decompose_composites: false },
        type1: { convert_curves: true, scale_to_1000: true,
                 autohint: true, decompose_composites: false },
      },
      otf: {
        ttf: { convert_curves: true, decompose_composites: false,
               interpret_ot: true },
        otf: { decompose_composites: false, store_custom_tables: true },
        type1: { decompose_composites: false },
      },
      type1: {
        ttf: { decompose_composites: false, generate_unicode: true,
               read_all_records: true },
        otf: { decompose_composites: false, generate_unicode: true,
               read_all_records: true },
      },
    }.freeze

    # Default generating options per conversion pair
    GENERATING_DEFAULTS = {
      ttf: {
        ttf: { hinting_mode: "preserve", write_custom_tables: true,
               optimize_tables: true },
        otf: { hinting_mode: "auto", decompose_on_output: false,
               write_custom_tables: true },
        type1: { write_pfm: true, write_afm: true, write_inf: true,
                 select_encoding_automatically: true, hinting_mode: "auto" },
      },
      otf: {
        ttf: { hinting_mode: "auto", decompose_on_output: false,
               write_custom_tables: true },
        otf: { hinting_mode: "preserve", decompose_on_output: false,
               write_custom_tables: true, optimize_tables: true },
        type1: { write_pfm: true, write_afm: true, write_inf: true,
                 select_encoding_automatically: true, hinting_mode: "preserve",
                 decompose_on_output: false },
      },
      type1: {
        ttf: { hinting_mode: "auto", decompose_on_output: true },
        otf: { hinting_mode: "preserve", decompose_on_output: true },
        type1: { write_pfm: true, write_afm: true, write_inf: true,
                 select_encoding_automatically: true },
      },
    }.freeze

    # Recommended options from TypeTool 3 manual
    # Based on "Options for Converting Fonts" table (lines 6735-6803)
    RECOMMENDED_OPTIONS = {
      ttf: {
        ttf: {
          opening: { convert_curves: false, scale_to_1000: false,
                     decompose_composites: false, autohint: false,
                     store_custom_tables: true, store_native_hinting: true },
          generating: { hinting_mode: "full", write_custom_tables: true },
        },
        otf: {
          opening: { convert_curves: true, scale_to_1000: true,
                     autohint: true, decompose_composites: false,
                     store_custom_tables: true },
          generating: { hinting_mode: "auto", decompose_on_output: true },
        },
        type1: {
          opening: { convert_curves: true, scale_to_1000: true,
                     autohint: true, decompose_composites: false,
                     store_custom_tables: false },
          generating: { write_pfm: true, write_afm: true, write_inf: true,
                        select_encoding_automatically: true },
        },
      },
      otf: {
        ttf: {
          opening: { decompose_composites: false, read_all_records: true,
                     interpret_ot: true, store_custom_tables: true,
                     store_native_hinting: false },
          generating: { hinting_mode: "full", reencode_first_256: false },
        },
        otf: {
          opening: { decompose_composites: false, store_custom_tables: true },
          generating: { hinting_mode: "none", decompose_on_output: false,
                        write_custom_tables: true },
        },
        type1: {
          opening: { decompose_composites: false },
          generating: { write_pfm: true, write_afm: true, write_inf: true,
                        select_encoding_automatically: true,
                        hinting_mode: "none" },
        },
      },
      type1: {
        ttf: {
          opening: { decompose_composites: false, generate_unicode: true },
          generating: { hinting_mode: "full" },
        },
        otf: {
          opening: { decompose_composites: false, generate_unicode: true },
          generating: { hinting_mode: "none", decompose_on_output: true },
        },
        type1: {
          opening: { decompose_composites: false, generate_unicode: true },
          generating: { write_pfm: true, write_afm: true, write_inf: true,
                        select_encoding_automatically: true },
        },
      },
    }.freeze

    # Named presets for common conversion scenarios
    PRESETS = {
      type1_to_modern: {
        from: :type1,
        to: :otf,
        opening: { generate_unicode: true, decompose_composites: false },
        generating: { hinting_mode: "preserve", decompose_on_output: true },
      },
      modern_to_type1: {
        from: :otf,
        to: :type1,
        opening: { convert_curves: true, scale_to_1000: true,
                   autohint: true, decompose_composites: false,
                   store_custom_tables: false },
        generating: { write_pfm: true, write_afm: true, write_inf: true,
                      select_encoding_automatically: true, hinting_mode: "preserve" },
      },
      web_optimized: {
        from: :otf,
        to: :woff2,
        opening: {},
        generating: { compression: "brotli", transform_tables: true,
                      optimize_tables: true, preserve_metadata: true },
      },
      archive_to_modern: {
        from: :ttc,
        to: :otf,
        opening: { convert_curves: true, decompose_composites: false },
        generating: { target_format: "otf", hinting_mode: "preserve" },
      },
    }.freeze
  end
end
