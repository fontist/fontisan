# frozen_string_literal: true

module Fontisan
  # Marks a class as providing the SFNT font source interface.
  #
  # SfntFont, WoffFont, and Woff2Font all expose the same table-access
  # surface (#table, #tables, #table_data, #table_names, #has_table?)
  # but don't share a common base class (WOFF/WOFF2 wrap an SfntFont
  # but inherit from BinData::Record directly).
  #
  # Including this module lets callers type-check with `is_a?(SfntSource)`
  # instead of `respond_to?(:table)` duck-typing.
  module SfntSource
    # @param tag [String] table tag
    # @return [Object, nil] parsed table or nil
    def table(tag); end

    # @return [Hash<String, String>] raw table bytes by tag
    def table_data(tag = nil); end

    # @return [Array<String>] table tags present in this font
    def table_names; end

    # @param tag [String] table tag
    # @return [Boolean]
    def has_table?(tag); end
  end
end
