# frozen_string_literal: true

require_relative "table_analyzer"
require_relative "table_deduplicator"
require_relative "offset_calculator"
require_relative "writer"
require "yaml"

module Fontisan
  module Collection
    # CollectionBuilder orchestrates TTC/OTC creation
    #
    # Main responsibility: Coordinate the entire collection creation process
    # including analysis, deduplication, offset calculation, and writing.
    # Implements builder pattern for flexible configuration.
    #
    # @example Create TTC with default options
    #   builder = CollectionBuilder.new([font1, font2, font3])
    #   builder.build_to_file("family.ttc")
    #
    # @example Create OTC with optimization
    #   builder = CollectionBuilder.new([font1, font2, font3])
    #   builder.format = :otc
    #   builder.optimize = true
    #   result = builder.build
    #   puts "Saved #{result[:space_savings]} bytes"
    class Builder
      # Source fonts
      # @return [Array<TrueTypeFont, OpenTypeFont>]
      attr_reader :fonts

      # Collection format (:ttc or :otc)
      # @return [Symbol]
      attr_accessor :format

      # Enable table sharing optimization
      # @return [Boolean]
      attr_accessor :optimize

      # Configuration settings
      # @return [Hash]
      attr_accessor :config

      # Build result (populated after build)
      # @return [Hash, nil]
      attr_reader :result

      # Initialize builder with fonts
      #
      # @param fonts [Array<TrueTypeFont, OpenTypeFont>] Fonts to pack
      # @param options [Hash] Builder options
      # @option options [Symbol] :format Format type (:ttc or :otc, default: :ttc)
      # @option options [Boolean] :optimize Enable optimization (default: true)
      # @option options [Hash] :config Configuration overrides
      # @raise [ArgumentError] if fonts array is invalid
      def initialize(fonts, options = {})
        if fonts.nil? || fonts.empty?
          raise ArgumentError,
                "fonts cannot be nil or empty"
        end
        raise ArgumentError, "fonts must be an array" unless fonts.is_a?(Array)

        unless fonts.all? do |f|
          f.respond_to?(:table_data)
        end
          raise ArgumentError,
                "all fonts must respond to table_data"
        end

        @fonts = fonts
        @format = options[:format] || :ttc
        @optimize = options.fetch(:optimize, true)
        @config = load_config.merge(options[:config] || {})
        @result = nil

        validate_format!
      end

      # Build collection and return binary
      #
      # Executes the complete collection creation process:
      # 1. Analyze tables across fonts
      # 2. Deduplicate identical tables
      # 3. Calculate file offsets
      # 4. Write binary structure
      #
      # @return [Hash] Build result with:
      #   - :binary [String] - Complete collection binary
      #   - :space_savings [Integer] - Bytes saved by sharing
      #   - :analysis [Hash] - Analysis report
      #   - :statistics [Hash] - Deduplication statistics
      def build
        # Step 1: Analyze tables
        analyzer = TableAnalyzer.new(@fonts)
        analysis_report = analyzer.analyze

        # Step 2: Deduplicate tables
        deduplicator = TableDeduplicator.new(@fonts)
        sharing_map = deduplicator.build_sharing_map
        statistics = deduplicator.statistics

        # Step 3: Calculate offsets
        calculator = OffsetCalculator.new(sharing_map, @fonts)
        offsets = calculator.calculate

        # Step 4: Write collection
        writer = Writer.new(@fonts, sharing_map, offsets, format: @format)
        binary = writer.write_collection

        # Store result
        @result = {
          binary: binary,
          space_savings: analysis_report[:space_savings],
          analysis: analysis_report,
          statistics: statistics,
          format: @format,
          num_fonts: @fonts.size,
        }

        @result
      end

      # Build collection and write to file
      #
      # @param path [String] Output file path
      # @return [Hash] Build result (same as build method)
      def build_to_file(path)
        result = build
        File.binwrite(path, result[:binary])
        result[:output_path] = path
        result[:output_size] = result[:binary].bytesize
        result
      end

      # Get analysis report
      #
      # Runs analysis without building the full collection.
      # Useful for previewing space savings before committing to build.
      #
      # @return [Hash] Analysis report
      def analyze
        analyzer = TableAnalyzer.new(@fonts)
        analyzer.analyze
      end

      # Get potential space savings without building
      #
      # @return [Integer] Bytes that can be saved
      def potential_savings
        analyze[:space_savings]
      end

      # Validate collection can be built
      #
      # @return [Boolean] true if valid, raises error otherwise
      # @raise [Error] if validation fails
      def validate!
        # Check minimum fonts
        raise Error, "Collection requires at least 2 fonts" if @fonts.size < 2

        # Check format compatibility
        incompatible = check_format_compatibility
        if incompatible.any?
          raise Error, "Format mismatch: #{incompatible.join(', ')}"
        end

        # Check variable font compatibility
        validate_variation_compatibility! if variable_fonts_in_collection?

        # Check all fonts have required tables
        @fonts.each_with_index do |font, index|
          required_tables = %w[head hhea maxp]
          missing = required_tables.reject { |tag| font.has_table?(tag) }
          unless missing.empty?
            raise Error,
                  "Font #{index} missing required tables: #{missing.join(', ')}"
          end
        end

        true
      end

      # Check if collection contains variable fonts
      #
      # @return [Boolean] true if any font has fvar table
      def variable_fonts_in_collection?
        @fonts.any? { |font| font.has_table?("fvar") }
      end

      # Validate variable font compatibility
      #
      # Ensures all variable fonts in the collection are compatible:
      # - All must be same variation type (TrueType or CFF2)
      # - All must have the same axes
      #
      # @return [void]
      # @raise [Error] if variable fonts are incompatible
      def validate_variation_compatibility!
        validate_all_same_variation_type!
        validate_same_axes!
      end

      private

      # Load configuration from file
      #
      # @return [Hash] Configuration hash
      def load_config
        config_path = File.join(__dir__, "..", "config",
                                "collection_settings.yml")
        if File.exist?(config_path)
          YAML.load_file(config_path)
        else
          default_config
        end
      rescue StandardError => e
        warn "Failed to load config: #{e.message}, using defaults"
        default_config
      end

      # Default configuration
      #
      # @return [Hash] Default settings
      def default_config
        {
          "table_sharing_strategy" => "conservative",
          "alignment" => 4,
          "optimize_table_order" => true,
          "verify_checksums" => true,
        }
      end

      # Validate format is supported
      #
      # @return [void]
      # @raise [ArgumentError] if format is invalid
      def validate_format!
        valid_formats = %i[ttc otc]
        return if valid_formats.include?(@format)

        raise ArgumentError,
              "Invalid format: #{@format}. Must be one of: #{valid_formats.join(', ')}"
      end

      # Check if all fonts are compatible with selected format
      #
      # @return [Array<String>] Array of incompatibility messages
      def check_format_compatibility
        incompatible = []

        if @format == :ttc
          # TTC requires TrueType fonts (sfnt version 0x00010000 or 'true')
          @fonts.each_with_index do |font, index|
            sfnt = font.header.sfnt_version
            unless [0x00010000, 0x74727565].include?(sfnt) # 0x74727565 = 'true'
              incompatible << "Font #{index} is not TrueType (sfnt: 0x#{sfnt.to_s(16)})"
            end
          end
        elsif @format == :otc
          # OTC can contain both TrueType and OpenType/CFF fonts
          # No strict validation needed, but warn about mixing
          has_truetype = false
          has_opentype = false

          @fonts.each do |font|
            sfnt = font.header.sfnt_version
            if [0x00010000, 0x74727565].include?(sfnt)
              has_truetype = true
            elsif sfnt == 0x4F54544F # 'OTTO'
              has_opentype = true
            end
          end

          if has_truetype && has_opentype
            warn "Warning: Mixing TrueType and OpenType/CFF fonts in OTC"
          end
        end

        incompatible
      end

      # Validate all variable fonts use same variation type
      #
      # @return [void]
      # @raise [Error] if mixing TrueType and CFF2 variable fonts
      def validate_all_same_variation_type!
        variable_fonts = @fonts.select { |f| f.has_table?("fvar") }
        return if variable_fonts.empty?

        ttf_count = variable_fonts.count { |f| f.has_table?("glyf") }
        otf_count = variable_fonts.count { |f| f.has_table?("CFF2") }

        if ttf_count.positive? && otf_count.positive?
          raise Error, "Cannot mix TrueType and CFF2 variable fonts in collection"
        end
      end

      # Validate all variable fonts have same axes
      #
      # @return [void]
      # @raise [Error] if variable fonts have different axes
      def validate_same_axes!
        variable_fonts = @fonts.select { |f| f.has_table?("fvar") }
        return if variable_fonts.size < 2

        first_axes = extract_axes(variable_fonts.first)
        variable_fonts.each_with_index do |font, index|
          font_axes = extract_axes(font)
          unless axes_match?(font_axes, first_axes)
            raise Error,
                  "Variable font #{index} has different axes. " \
                  "Expected: #{first_axes.join(', ')}, " \
                  "Got: #{font_axes.join(', ')}"
          end
        end
      end

      # Extract axis tags from a font's fvar table
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to extract axes from
      # @return [Array<String>] Sorted array of axis tags
      def extract_axes(font)
        return [] unless font.has_table?("fvar")

        fvar_table = font.table("fvar")
        return [] unless fvar_table.respond_to?(:axes)

        fvar_table.axes.map(&:axis_tag).sort
      end

      # Check if two axis arrays match
      #
      # @param axes1 [Array<String>] First axis array
      # @param axes2 [Array<String>] Second axis array
      # @return [Boolean] true if axes match
      def axes_match?(axes1, axes2)
        axes1 == axes2
      end
    end
  end
end
