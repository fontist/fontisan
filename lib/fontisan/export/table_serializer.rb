# frozen_string_literal: true

require "base64"
require "json"

module Fontisan
  module Export
    # TableSerializer handles serialization of individual font tables
    #
    # Uses strategy pattern to serialize different table types:
    # - Fully parsed tables: Use Lutaml::Model serialization
    # - Binary tables: Encode as hex or base64
    # - Special tables: Custom serialization logic
    #
    # @example Serializing a parsed table
    #   serializer = TableSerializer.new(binary_format: :hex)
    #   data = serializer.serialize(head_table, "head")
    #
    # @example Serializing binary table
    #   data = serializer.serialize_binary(raw_data, "DSIG")
    class TableSerializer
      # Tables that have full Lutaml::Model parsing support
      FULLY_PARSED_TABLES = %w[
        head hhea maxp post OS/2 name
        fvar HVAR VVAR MVAR cvar gvar
      ].freeze

      # Tables that should be stored as binary
      BINARY_ONLY_TABLES = %w[
        cvt fpgm prep gasp DSIG GDEF GPOS GSUB
      ].freeze

      # Initialize table serializer
      #
      # @param binary_format [Symbol] Format for binary data (:hex or :base64)
      def initialize(binary_format: :hex)
        @binary_format = binary_format
        validate_binary_format!
      end

      # Serialize a table to exportable format
      #
      # @param table [Object] The table object
      # @param tag [String] The table tag
      # @return [Hash] Serialized table data
      def serialize(table, tag)
        if fully_parsed?(tag)
          serialize_parsed(table, tag)
        elsif binary_only?(tag)
          serialize_binary(table.to_binary_s, tag)
        else
          serialize_mixed(table, tag)
        end
      end

      # Serialize a parsed table
      #
      # @param table [Object] The table object with Lutaml::Model
      # @param tag [String] The table tag
      # @return [Hash] Serialized data with parsed flag
      def serialize_parsed(table, tag)
        fields = extract_fields(table)
        {
          tag: tag,
          parsed: true,
          fields: fields.to_json,
          data: nil,
        }
      end

      # Serialize a binary-only table
      #
      # @param data [String] Binary data
      # @param tag [String] The table tag
      # @return [Hash] Serialized data with binary content
      def serialize_binary(data, tag)
        encoded = encode_binary(data)
        {
          tag: tag,
          parsed: false,
          data: encoded,
          fields: nil,
        }
      end

      # Serialize tables with mixed content (summary + binary)
      #
      # @param table [Object] The table object
      # @param tag [String] The table tag
      # @return [Hash] Serialized data with both fields and binary
      def serialize_mixed(table, tag)
        summary = create_summary(table, tag)
        binary = table.respond_to?(:to_binary_s) ? table.to_binary_s : ""

        {
          tag: tag,
          parsed: true,
          fields: summary.to_json,
          data: encode_binary(binary),
        }
      end

      private

      # Check if table is fully parsed
      #
      # @param tag [String] Table tag
      # @return [Boolean]
      def fully_parsed?(tag)
        FULLY_PARSED_TABLES.include?(tag)
      end

      # Check if table is binary-only
      #
      # @param tag [String] Table tag
      # @return [Boolean]
      def binary_only?(tag)
        BINARY_ONLY_TABLES.include?(tag)
      end

      # Extract fields from a parsed table
      #
      # @param table [Object] The table object
      # @return [Hash] Field names and values
      def extract_fields(table)
        fields = {}

        # Get all instance variables
        table.instance_variables.each do |var|
          name = var.to_s.delete("@")
          value = table.instance_variable_get(var)
          fields[name] = serialize_value(value)
        end

        fields
      end

      # Serialize individual field value
      #
      # @param value [Object] The value to serialize
      # @return [Object] Serialized value
      def serialize_value(value)
        case value
        when Integer, Float, String, TrueClass, FalseClass, NilClass
          value
        when Array
          value.map { |v| serialize_value(v) }
        when Hash
          value.transform_values { |v| serialize_value(v) }
        when Time
          value.iso8601
        else
          # For complex objects, try to extract fields
          if value.respond_to?(:instance_variables)
            extract_fields(value)
          else
            value.to_s
          end
        end
      end

      # Create summary for mixed-content tables
      #
      # @param table [Object] The table object
      # @param tag [String] Table tag
      # @return [Hash] Summary information
      def create_summary(table, tag)
        case tag
        when "glyf"
          create_glyf_summary(table)
        when "loca"
          create_loca_summary(table)
        when "cmap"
          create_cmap_summary(table)
        when "CFF"
          create_cff_summary(table)
        else
          { type: "binary", size: table.to_binary_s.bytesize }
        end
      end

      # Create glyf table summary
      #
      # @param table [Object] glyf table
      # @return [Hash] Summary
      def create_glyf_summary(table)
        {
          type: "glyf",
          num_glyphs: table.respond_to?(:glyphs) ? table.glyphs.length : 0,
          note: "Outline data stored as binary",
        }
      end

      # Create loca table summary
      #
      # @param table [Object] loca table
      # @return [Hash] Summary
      def create_loca_summary(table)
        {
          type: "loca",
          num_offsets: table.respond_to?(:offsets) ? table.offsets.length : 0,
          format: table.respond_to?(:format) ? table.format : nil,
        }
      end

      # Create cmap table summary
      #
      # @param table [Object] cmap table
      # @return [Hash] Summary
      def create_cmap_summary(table)
        {
          type: "cmap",
          version: table.respond_to?(:version) ? table.version : 0,
          note: "Character mappings stored as binary",
        }
      end

      # Create CFF table summary
      #
      # @param table [Object] CFF table
      # @return [Hash] Summary
      def create_cff_summary(_table)
        {
          type: "CFF",
          note: "CharString data stored as binary",
        }
      end

      # Encode binary data based on format
      #
      # @param data [String] Binary data
      # @return [String] Encoded data
      def encode_binary(data)
        case @binary_format
        when :hex
          data.unpack1("H*")
        when :base64
          Base64.strict_encode64(data)
        end
      end

      # Validate binary format option
      #
      # @raise [ArgumentError] if format is invalid
      def validate_binary_format!
        valid_formats = %i[hex base64]
        return if valid_formats.include?(@binary_format)

        raise ArgumentError,
              "Invalid binary format: #{@binary_format}. " \
              "Must be one of: #{valid_formats.join(', ')}"
      end
    end
  end
end
