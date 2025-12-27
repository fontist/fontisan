# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # FontExport represents complete font structure for export to YAML/JSON
    #
    # This model encapsulates the entire font structure including header
    # information, all tables (parsed and binary), and metadata. It supports
    # round-trip conversion: font → export → import → font.
    #
    # @example Exporting a font
    #   export = FontExport.new(source_file: "font.ttf")
    #   export.extract_from_font(font)
    #   yaml_output = export.to_yaml
    #
    # @example Importing from YAML
    #   export = FontExport.from_yaml(yaml_string)
    #   font = export.rebuild_font
    class FontExport < Lutaml::Model::Serializable
      # Metadata about the export
      class Metadata < Lutaml::Model::Serializable
        attribute :source_file, :string
        attribute :export_date, :string
        attribute :exporter_version, :string
        attribute :font_format, :string

        yaml do
          map "source_file", to: :source_file
          map "export_date", to: :export_date
          map "exporter_version", to: :exporter_version
          map "font_format", to: :font_format
        end

        json do
          map "source_file", to: :source_file
          map "export_date", to: :export_date
          map "exporter_version", to: :exporter_version
          map "font_format", to: :font_format
        end
      end

      # Font header information
      class Header < Lutaml::Model::Serializable
        attribute :sfnt_version, :string
        attribute :num_tables, :integer
        attribute :search_range, :integer
        attribute :entry_selector, :integer
        attribute :range_shift, :integer

        yaml do
          map "sfnt_version", to: :sfnt_version
          map "num_tables", to: :num_tables
          map "search_range", to: :search_range
          map "entry_selector", to: :entry_selector
          map "range_shift", to: :range_shift
        end

        json do
          map "sfnt_version", to: :sfnt_version
          map "num_tables", to: :num_tables
          map "search_range", to: :search_range
          map "entry_selector", to: :entry_selector
          map "range_shift", to: :range_shift
        end
      end

      # Individual table export
      class TableExport < Lutaml::Model::Serializable
        attribute :tag, :string
        attribute :checksum, :string
        attribute :parsed, :boolean, default: -> { false }
        attribute :data, :string, default: -> { nil }
        attribute :fields, :string, default: -> { nil }

        yaml do
          map "tag", to: :tag
          map "checksum", to: :checksum
          map "parsed", to: :parsed
          map "data", to: :data
          map "fields", to: :fields
        end

        json do
          map "tag", to: :tag
          map "checksum", to: :checksum
          map "parsed", to: :parsed
          map "data", to: :data
          map "fields", to: :fields
        end
      end

      attribute :metadata, Metadata
      attribute :header, Header
      attribute :tables, TableExport, collection: true, default: -> { [] }

      yaml do
        map "metadata", to: :metadata
        map "header", to: :header
        map "tables", to: :tables
      end

      json do
        map "metadata", to: :metadata
        map "header", to: :header
        map "tables", to: :tables
      end

      # Find a table by tag
      #
      # @param tag [String] The table tag (e.g., "head", "name")
      # @return [TableExport, nil] The table or nil if not found
      def find_table(tag)
        tables.find { |t| t.tag == tag }
      end

      # Get all parsed tables
      #
      # @return [Array<TableExport>] Array of parsed tables
      def parsed_tables
        tables.select(&:parsed)
      end

      # Get all binary-only tables
      #
      # @return [Array<TableExport>] Array of binary tables
      def binary_tables
        tables.reject(&:parsed)
      end

      # Add a table to the export
      #
      # @param tag [String] Table tag
      # @param checksum [String] Table checksum
      # @param parsed [Boolean] Whether table is parsed
      # @param data [String, nil] Binary data (hex/base64)
      # @param fields [Hash, nil] Parsed fields as Hash/JSON
      # @return [void]
      def add_table(tag:, checksum:, parsed: false, data: nil, fields: nil)
        tables << TableExport.new(
          tag: tag,
          checksum: checksum,
          parsed: parsed,
          data: data,
          fields: fields,
        )
      end

      # Validate export structure
      #
      # @return [Boolean] True if export is valid
      def valid?
        !metadata.nil? && !header.nil? && !tables.empty?
      end
    end
  end
end
