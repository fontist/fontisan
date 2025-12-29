# frozen_string_literal: true

require_relative "variation_context"
require_relative "../error"

module Fontisan
  module Variation
    # Preserves variation data when converting between compatible font formats
    #
    # [`VariationPreserver`](lib/fontisan/variation/variation_preserver.rb)
    # copies variation tables from source to target font during format
    # conversion. It handles:
    # - Common variation tables (fvar, avar, STAT) - shared by all variable fonts
    # - Format-specific tables (gvar for TTF, CFF2 for OTF)
    # - Metrics variation tables (HVAR, VVAR, MVAR)
    # - Table checksum updates
    # - Validation of table consistency
    #
    # **Use Cases:**
    #
    # 1. **Variable TTF → Variable WOFF**: Preserve all gvar-based variation
    # 2. **Variable OTF → Variable WOFF**: Preserve all CFF2-based variation
    # 3. **Variable TTF → Variable OTF**: Copy common tables (fvar, avar, STAT)
    #    but variation data conversion handled by Converter
    # 4. **Variable OTF → Variable TTF**: Copy common tables (fvar, avar, STAT)
    #    but variation data conversion handled by Converter
    #
    # **Preserved Tables:**
    #
    # Common (all variable fonts):
    # - fvar (Font Variations)
    # - avar (Axis Variations, optional)
    # - STAT (Style Attributes)
    #
    # TrueType-specific:
    # - gvar (Glyph Variations)
    # - cvar (CVT Variations, optional)
    #
    # CFF2-specific:
    # - CFF2 (with blend operators)
    #
    # Metrics (optional):
    # - HVAR (Horizontal Metrics Variations)
    # - VVAR (Vertical Metrics Variations)
    # - MVAR (Metrics Variations)
    #
    # @example Preserve variation when converting TTF to WOFF
    #   preserver = VariationPreserver.new(ttf_font, woff_tables)
    #   preserved_tables = preserver.preserve
    #
    # @example Preserve only common tables for outline conversion
    #   preserver = VariationPreserver.new(ttf_font, otf_tables,
    #                                      preserve_format_specific: false)
    #   preserved_tables = preserver.preserve
    class VariationPreserver
      # Common variation tables present in all variable fonts
      COMMON_TABLES = %w[fvar avar STAT].freeze

      # TrueType-specific variation tables
      TRUETYPE_TABLES = %w[gvar cvar].freeze

      # CFF2-specific variation tables
      CFF2_TABLES = %w[CFF2].freeze

      # Metrics variation tables
      METRICS_TABLES = %w[HVAR VVAR MVAR].freeze

      # All variation-related tables
      ALL_VARIATION_TABLES = (COMMON_TABLES + TRUETYPE_TABLES +
                              CFF2_TABLES + METRICS_TABLES).freeze

      # Preserve variation data from source to target
      #
      # @param source_font [TrueTypeFont, OpenTypeFont] Variable font
      # @param target_tables [Hash<String, String>] Target font tables
      # @param options [Hash] Preservation options
      # @return [Hash<String, String>] Tables with variation data preserved
      def self.preserve(source_font, target_tables, options = {})
        new(source_font, target_tables, options).preserve
      end

      # @return [Object] Source font
      attr_reader :source_font

      # @return [Hash<String, String>] Target tables
      attr_reader :target_tables

      # @return [Hash] Preservation options
      attr_reader :options

      # Initialize preserver
      #
      # @param source_font [TrueTypeFont, OpenTypeFont] Variable font
      # @param target_tables [Hash<String, String>] Target font tables
      # @param options [Hash] Preservation options
      # @option options [Boolean] :preserve_format_specific Preserve format-
      #   specific variation tables (default: true)
      # @option options [Boolean] :preserve_metrics Preserve metrics variation
      #   tables (default: true)
      # @option options [Boolean] :validate Validate table consistency
      #   (default: true)
      def initialize(source_font, target_tables, options = {})
        @source_font = source_font
        @target_tables = target_tables.dup
        @options = options

        validate_source!
        @context = VariationContext.new(source_font)
      end

      # Preserve variation tables
      #
      # @return [Hash<String, String>] Target tables with variation preserved
      def preserve
        # Copy common variation tables (fvar, avar, STAT)
        copy_common_tables

        # Copy format-specific variation tables if requested
        if preserve_format_specific?
          copy_format_specific_tables
        end

        # Copy metrics variation tables if requested
        copy_metrics_tables if preserve_metrics?

        # Validate consistency if requested
        validate_consistency if validate?

        @target_tables
      end

      # Check if source font is a variable font
      #
      # @return [Boolean] True if source has fvar table
      def variable_font?
        @context.variable_font?
      end

      # Get variation type of source font
      #
      # @return [Symbol, nil] :truetype, :cff2, or nil
      def variation_type
        @context.variation_type
      end

      private

      # Validate source font
      #
      # @raise [ArgumentError] If source is invalid
      def validate_source!
        raise ArgumentError, "Source font cannot be nil" if @source_font.nil?

        unless @source_font.respond_to?(:has_table?) &&
            @source_font.respond_to?(:table_data)
          raise ArgumentError,
                "Source font must respond to :has_table? and :table_data"
        end

        if @target_tables.nil?
          raise ArgumentError,
                "Target tables cannot be nil"
        end

        unless @target_tables.is_a?(Hash)
          raise ArgumentError,
                "Target tables must be a Hash, got: #{@target_tables.class}"
        end
      end

      # Copy common variation tables (fvar, avar, STAT)
      #
      # These tables are independent of outline format and can always be copied
      def copy_common_tables
        COMMON_TABLES.each do |tag|
          copy_table(tag) if @source_font.has_table?(tag)
        end
      end

      # Copy format-specific variation tables
      #
      # For TrueType: gvar, cvar
      # For CFF2: CFF2 table
      def copy_format_specific_tables
        case variation_type
        when :truetype
          copy_truetype_variation_tables
        when :postscript
          copy_cff2_variation_tables
        end
      end

      # Copy TrueType variation tables
      def copy_truetype_variation_tables
        TRUETYPE_TABLES.each do |tag|
          copy_table(tag) if @source_font.has_table?(tag)
        end
      end

      # Copy CFF2 variation tables
      def copy_cff2_variation_tables
        # CFF2 table contains both outlines and variation data
        # Only copy if target doesn't already have CFF2 and source has it
        return unless @source_font.has_table?("CFF2")
        return if @target_tables.key?("CFF2")

        copy_table("CFF2")
      end

      # Copy metrics variation tables (HVAR, VVAR, MVAR)
      def copy_metrics_tables
        METRICS_TABLES.each do |tag|
          copy_table(tag) if @source_font.has_table?(tag)
        end
      end

      # Copy a single table from source to target
      #
      # @param tag [String] Table tag
      def copy_table(tag)
        return unless @source_font.has_table?(tag)

        table_data = @source_font.table_data[tag]
        return unless table_data

        @target_tables[tag] = table_data.dup
      end

      # Validate table consistency
      #
      # Ensures that copied variation tables are consistent with target font
      # @raise [Error] If validation fails
      def validate_consistency
        # Must have fvar if we're preserving variations
        unless @target_tables.key?("fvar")
          raise Fontisan::Error,
                "Cannot preserve variations: fvar table missing"
        end

        # If we have gvar, we must have glyf (TrueType outlines)
        if @target_tables.key?("gvar") && !@target_tables.key?("glyf")
          raise Fontisan::Error,
                "Invalid variation preservation: gvar present without glyf"
        end

        # If we have CFF2, we shouldn't have glyf (CFF2 has CFF outlines)
        # Check both source and target to catch conflicts
        has_cff2 = @target_tables.key?("CFF2") ||
          (@source_font.has_table?("CFF2") && preserve_format_specific?)
        if has_cff2 && @target_tables.key?("glyf")
          raise Fontisan::Error,
                "Invalid variation preservation: CFF2 and glyf both present"
        end

        # Metrics variation tables require fvar
        if metrics_tables_present? && !@target_tables.key?("fvar")
          raise Fontisan::Error,
                "Metrics variation tables require fvar table"
        end
      end

      # Check if any metrics variation tables are present
      #
      # @return [Boolean] True if HVAR, VVAR, or MVAR present
      def metrics_tables_present?
        METRICS_TABLES.any? { |tag| @target_tables.key?(tag) }
      end

      # Get preserve_format_specific option
      #
      # @return [Boolean] True if format-specific tables should be preserved
      def preserve_format_specific?
        @options.fetch(:preserve_format_specific, true)
      end

      # Get preserve_metrics option
      #
      # @return [Boolean] True if metrics tables should be preserved
      def preserve_metrics?
        @options.fetch(:preserve_metrics, true)
      end

      # Get validate option
      #
      # @return [Boolean] True if consistency should be validated
      def validate?
        @options.fetch(:validate, true)
      end
    end
  end
end
