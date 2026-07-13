# frozen_string_literal: true

require "base64"
require "json"

module Fontisan
  module Export
    # Serializes individual font tables for export.
    #
    # Tables fall into three categories:
    # - Fully parsed: BinData records whose `snapshot` hash is exported
    #   as JSON fields.
    # - Binary-only: opaque blobs encoded as hex or base64.
    # - Mixed: tables with a small typed summary alongside the binary
    #   payload (glyf, loca, cmap, CFF).
    #
    # All table objects are BinData::Record subclasses; we trust that
    # interface rather than duck-typing each field.
    class TableSerializer
      # Tables whose BinData fields are exported as JSON.
      FULLY_PARSED_TABLES = %w[
        head hhea maxp post OS/2 name
        fvar HVAR VVAR MVAR cvar gvar
      ].freeze

      # Tables stored as opaque binary with no field extraction.
      BINARY_ONLY_TABLES = %w[
        cvt fpgm prep gasp DSIG GDEF GPOS GSUB
      ].freeze

      # Tables that ship a summary alongside the raw binary.
      MIXED_SUMMARIES = {
        "glyf" => GlyphSummary,
        "loca" => LocaSummary,
        "cmap" => CmapSummary,
        "CFF" => CffSummary,
      }.freeze

      # @param binary_format [Symbol] :hex or :base64
      def initialize(binary_format: :hex)
        @binary_format = binary_format
        validate_binary_format!
      end

      # @param table [BinData::Record] the table object
      # @param tag [String] table tag
      # @return [Hash] serialized payload
      def serialize(table, tag)
        if fully_parsed?(tag)
          serialize_parsed(table, tag)
        elsif binary_only?(tag)
          serialize_binary(table.to_binary_s, tag)
        else
          serialize_mixed(table, tag)
        end
      end

      # @param data [String] binary bytes
      # @param tag [String] table tag
      # @return [Hash]
      def serialize_binary(data, tag)
        { tag: tag, parsed: false, data: encode_binary(data), fields: nil }
      end

      private

      def fully_parsed?(tag)
        FULLY_PARSED_TABLES.include?(tag)
      end

      def binary_only?(tag)
        BINARY_ONLY_TABLES.include?(tag)
      end

      def serialize_parsed(table, tag)
        { tag: tag, parsed: true, fields: table.snapshot.to_json, data: nil }
      end

      def serialize_mixed(table, tag)
        summary = summary_for(table, tag)
        { tag: tag, parsed: true,
          fields: summary.to_json,
          data: encode_binary(table.to_binary_s) }
      end

      def summary_for(table, tag)
        builder = MIXED_SUMMARIES[tag]
        return { type: "binary", size: table.to_binary_s.bytesize } unless builder

        builder.call(table)
      end

      def encode_binary(data)
        case @binary_format
        when :hex
          data.unpack1("H*")
        when :base64
          Base64.strict_encode64(data)
        end
      end

      def validate_binary_format!
        valid = %i[hex base64]
        return if valid.include?(@binary_format)

        raise ArgumentError,
              "Invalid binary format: #{@binary_format}. " \
              "Must be one of: #{valid.join(', ')}"
      end

      # Summary builders for mixed-content tables. Each is a callable
      # that receives the typed table and returns a JSON-able Hash.

      module GlyphSummary
        def self.call(table)
          { type: "glyf", num_glyphs: table.glyphs.length,
            note: "Outline data stored as binary" }
        end
      end

      module LocaSummary
        def self.call(table)
          { type: "loca", num_offsets: table.offsets.length,
            format: table.format }
        end
      end

      module CmapSummary
        def self.call(table)
          { type: "cmap", version: table.version,
            note: "Character mappings stored as binary" }
        end
      end

      module CffSummary
        def self.call(_table)
          { type: "CFF", note: "CharString data stored as binary" }
        end
      end
    end
  end
end
