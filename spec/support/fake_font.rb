# frozen_string_literal: true

module Fontisan
  module SpecHelpers
    # FakeFont is a lightweight SfntSource conformant object for specs
    # that need a font-shaped input without the cost of building a real
    # BinData SfntFont. It includes SfntSource so is_a?(SfntSource)
    # checks pass.
    class FakeFont
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
        return tables_hash if tag.nil?

        tables_hash[tag]
      end

      def table_names
        tables_hash.keys
      end

      def tables
        tables_hash
      end

      def read_table_data(_tag)
        nil
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
    end
  end
end
