# frozen_string_literal: true

module Fontisan
  module SpecHelpers
    # FakeTableDictionary is a typed SfntSource conformant that wraps a
    # hash of pre-built table objects. Use it in specs that need to
    # exercise code which calls `font.table(tag)` and expects to get
    # back a parsed BinData record.
    class FakeTableDictionary
      include Fontisan::SfntSource

      attr_reader :tables_hash, :sfnt_version_value

      def initialize(tables = {}, sfnt_version: 0x00010000)
        @tables_hash = tables
        @sfnt_version_value = sfnt_version
      end

      def table(tag)
        tables_hash[tag]
      end

      def table_data(tag = nil)
        return tables_hash.transform_values(&:to_binary_s) if tag.nil?

        entry = tables_hash[tag]
        entry&.to_binary_s
      end

      def table_names
        tables_hash.keys
      end

      def has_table?(tag)
        tables_hash.key?(tag)
      end

      def sfnt_version
        sfnt_version_value
      end

      def header
        Struct.new(:sfnt_version).new(sfnt_version_value)
      end

      def cff?
        tables_hash.key?("CFF ")
      end

      def truetype?
        tables_hash.key?("glyf")
      end

      def tables
        tables_hash
      end

      def read_table_data(_tag)
        nil
      end
    end
  end
end
