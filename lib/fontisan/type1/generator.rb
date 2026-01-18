# frozen_string_literal: true

require "fileutils"
require_relative "upm_scaler"
require_relative "encodings"
require_relative "conversion_options"
require_relative "afm_generator"
require_relative "pfm_generator"
require_relative "pfa_generator"
require_relative "pfb_generator"
require_relative "inf_generator"

module Fontisan
  module Type1
    # Unified Type 1 font generator
    #
    # [`Generator`](lib/fontisan/type1/generator.rb) provides a unified interface
    # for generating all Type 1 font formats from TrueType/OpenType fonts.
    #
    # This generator creates:
    # - AFM (Adobe Font Metrics) - Text-based font metrics
    # - PFM (Printer Font Metrics) - Windows font metrics
    # - PFA (Printer Font ASCII) - Unix Type 1 font (ASCII-hex encoded)
    # - PFB (Printer Font Binary) - Windows Type 1 font (binary)
    # - INF (Font Information) - Windows installation metadata
    #
    # @example Generate all Type 1 formats with default options (1000 UPM)
    #   font = Fontisan::FontLoader.load("font.ttf")
    #   result = Fontisan::Type1::Generator.generate(font)
    #   result[:afm]   # => AFM file content
    #   result[:pfm]   # => PFM file content
    #   result[:pfb]   # => PFB file content
    #   result[:inf]   # => INF file content
    #
    # @example Generate Unix Type 1 (PFA) with custom options
    #   result = Fontisan::Type1::Generator.generate(font,
    #     format: :pfa,
    #     upm_scale: 1000,
    #     encoding: Fontisan::Type1::Encodings::AdobeStandard
    #   )
    #
    # @example Generate with ConversionOptions preset
    #   options = Fontisan::Type1::ConversionOptions.windows_type1
    #   result = Fontisan::Type1::Generator.generate(font, options)
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5178.Type1.pdf
    class Generator
      # Default generation options
      DEFAULT_OPTIONS = {
        upm_scale: 1000,
        encoding: Encodings::AdobeStandard,
        decompose_composites: false,
        convert_curves: true,
        autohint: false,
        preserve_hinting: false,
        format: :pfb,
      }.freeze

      # Generate all Type 1 formats from a font
      #
      # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] Source font
      # @param options [ConversionOptions, Hash] Generation options
      # @return [Hash] Generated file contents
      def self.generate(font, options = {})
        options = normalize_options(options)
        new(font, options).generate
      end

      # Generate Type 1 files and write to disk
      #
      # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] Source font
      # @param output_dir [String] Directory to write files
      # @param options [ConversionOptions, Hash] Generation options
      # @return [Array<String>] Paths to generated files
      def self.generate_to_files(font, output_dir, options = {})
        options = normalize_options(options)
        result = generate(font, options)

        # Ensure output directory exists
        FileUtils.mkdir_p(output_dir)

        # Get base filename from font
        base_name = extract_base_name(font)

        # Write files
        written_files = []

        # Write AFM
        if result[:afm]
          afm_path = File.join(output_dir, "#{base_name}.afm")
          File.write(afm_path, result[:afm], encoding: "ISO-8859-1")
          written_files << afm_path
        end

        # Write PFM
        if result[:pfm]
          pfm_path = File.join(output_dir, "#{base_name}.pfm")
          File.binwrite(pfm_path, result[:pfm])
          written_files << pfm_path
        end

        # Write PFB or PFA
        if result[:pfb]
          pfb_path = File.join(output_dir, "#{base_name}.pfb")
          File.binwrite(pfb_path, result[:pfb])
          written_files << pfb_path
        elsif result[:pfa]
          pfa_path = File.join(output_dir, "#{base_name}.pfa")
          File.write(pfa_path, result[:pfa])
          written_files << pfa_path
        end

        # Write INF
        if result[:inf]
          inf_path = File.join(output_dir, "#{base_name}.inf")
          File.write(inf_path, result[:inf], encoding: "ISO-8859-1")
          written_files << inf_path
        end

        written_files
      end

      # Initialize a new Generator
      #
      # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] Source font
      # @param options [ConversionOptions, Hash] Generation options
      def initialize(font, options = {})
        @font = font
        @options = normalize_options_value(options)
        @metrics = MetricsCalculator.new(font)

        # Set up scaler
        upm_scale = @options.upm_scale || 1000
        @scaler = if upm_scale == :native
                    UPMScaler.native(font)
                  else
                    UPMScaler.new(font, target_upm: upm_scale)
                  end

        # Set up encoding
        @encoding = @options.encoding || Encodings::AdobeStandard
      end

      # Generate all Type 1 formats
      #
      # @return [Hash] Generated file contents
      def generate
        result = {}

        # Always generate AFM
        result[:afm] = AFMGenerator.generate(@font, to_hash)

        # Always generate PFM (for Windows compatibility)
        result[:pfm] = PFMGenerator.generate(@font, to_hash)

        # Generate PFB or PFA based on format option
        format = @options.format || :pfb
        if format == :pfa
          result[:pfa] = PFAGenerator.generate(@font, to_hash)
        else
          result[:pfb] = PFBGenerator.generate(@font, to_hash)
        end

        # Generate INF for Windows installation
        result[:inf] = INFGenerator.generate(@font, to_hash)

        result
      end

      private

      # Convert options to hash
      #
      # @return [Hash] Options as hash
      def to_hash
        {
          upm_scale: @options.upm_scale || 1000,
          encoding: @options.encoding || Encodings::AdobeStandard,
          decompose_composites: @options.decompose_composites || false,
          convert_curves: @options.convert_curves || true,
          autohint: @options.autohint || false,
          preserve_hinting: @options.preserve_hinting || false,
          format: @options.format || :pfb,
        }
      end

      # Normalize options to ConversionOptions
      #
      # @param options [ConversionOptions, Hash] Options to normalize
      # @return [ConversionOptions] Normalized options
      def self.normalize_options(options)
        return options if options.is_a?(ConversionOptions)

        ConversionOptions.new(options)
      end

      # Instance method version of normalize_options
      #
      # @param options [ConversionOptions, Hash] Options to normalize
      # @return [ConversionOptions] Normalized options
      def normalize_options_value(options)
        self.class.normalize_options(options)
      end

      # Extract base filename from font
      #
      # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] Source font
      # @return [String] Base filename
      def self.extract_base_name(font)
        name_table = font.table(Constants::NAME_TAG)
        if name_table.respond_to?(:postscript_name)
          name = name_table.postscript_name(1) || name_table.postscript_name(3)
          return name if name
        end

        font.post_script_name || "font"
      end
    end
  end
end
