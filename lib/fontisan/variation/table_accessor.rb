# frozen_string_literal: true

module Fontisan
  module Variation
    # Provides unified table access for variation classes
    #
    # This module centralizes table loading logic with optional caching
    # and consistent error handling. It should be included in variation
    # classes that need to access font tables.
    #
    # @example Using TableAccessor in a variation class
    #   class MyVariationClass
    #     include TableAccessor
    #
    #     def initialize(font)
    #       @font = font
    #       @variation_tables = {}
    #     end
    #
    #     def process
    #       gvar = variation_table("gvar")
    #       fvar = require_variation_table("fvar")
    #     end
    #   end
    module TableAccessor
      # Get a variation table with optional caching
      #
      # Loads and optionally caches a font table. Returns nil if table
      # doesn't exist. Use when table presence is optional.
      #
      # @param tag [String] Table tag (e.g., "gvar", "fvar")
      # @param lazy [Boolean] Enable lazy loading (default: true)
      # @return [Object, nil] Parsed table object or nil
      #
      # @example Get optional table
      #   gvar = variation_table("gvar")
      #   return unless gvar
      def variation_table(tag, lazy: true)
        # Return cached table if available
        return @variation_tables[tag] if @variation_tables&.key?(tag)

        # Check table exists
        return nil unless @font.has_table?(tag)

        # Initialize cache if needed
        @variation_tables ||= {}

        # Load and cache table
        @variation_tables[tag] = @font.table(tag)
      end

      # Get a required variation table
      #
      # Loads a table that must exist. Raises error if table is missing.
      # Use when table presence is required for operation.
      #
      # @param tag [String] Table tag
      # @return [Object] Parsed table object
      # @raise [MissingVariationTableError] If table doesn't exist
      #
      # @example Require table
      #   fvar = require_variation_table("fvar")
      #   # Guaranteed to have fvar or error raised
      def require_variation_table(tag)
        table = variation_table(tag)
        return table if table

        raise MissingVariationTableError.new(
          table: tag,
          message: "Required variation table '#{tag}' not found in font",
        )
      end

      # Check if variation table exists
      #
      # @param tag [String] Table tag
      # @return [Boolean] True if table exists
      #
      # @example Check table presence
      #   if has_variation_table?("gvar")
      #     # Process gvar
      #   end
      def has_variation_table?(tag)
        @font.has_table?(tag)
      end

      # Clear variation table cache
      #
      # Useful when font tables are modified and need to be reloaded.
      #
      # @return [void]
      def clear_variation_cache
        @variation_tables&.clear
      end

      # Clear specific cached table
      #
      # @param tag [String] Table tag to clear
      # @return [void]
      def clear_variation_table(tag)
        @variation_tables&.delete(tag)
      end
    end
  end
end
