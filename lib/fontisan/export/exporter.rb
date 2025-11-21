# frozen_string_literal: true

require_relative "../models/font_export"
require_relative "table_serializer"
require_relative "ttx_generator"
require_relative "transformers/font_to_ttx"
require_relative "../utilities/checksum_calculator"

module Fontisan
  module Export
    # Exporter orchestrates font export to YAML/JSON/TTX
    #
    # Main entry point for exporting fonts to debugging formats.
    # Handles table extraction, serialization, and metadata generation.
    #
    # @example Exporting a font to YAML
    #   exporter = Exporter.new(font, "font.ttf")
    #   export = exporter.export(format: :yaml)
    #   File.write("font.yaml", export.to_yaml)
    #
    # @example Exporting to TTX format
    #   exporter = Exporter.new(font, "font.ttf")
    #   ttx_xml = exporter.to_ttx
    #   File.write("font.ttx", ttx_xml)
    #
    # @example Selective table export
    #   export = exporter.export(tables: ["head", "name", "cmap"])
    class Exporter
      # Initialize exporter
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font to export
      # @param source_path [String] Path to source font file
      # @param options [Hash] Export options
      # @option options [Symbol] :binary_format Format for binary data (:hex or :base64)
      def initialize(font, source_path, options = {})
        @font = font
        @source_path = source_path
        @binary_format = options.fetch(:binary_format, :hex)
        @serializer = TableSerializer.new(binary_format: @binary_format)
      end

      # Export font to FontExport model
      #
      # @param options [Hash] Export options
      # @option options [Array<String>] :tables Specific tables to export (default: all)
      # @option options [Symbol] :format Output format (:yaml, :json, or :ttx)
      # @return [Models::FontExport, String] The export model or TTX XML string
      def export(options = {})
        format = options[:format] || :yaml

        if format == :ttx
          to_ttx(options)
        else
          export_to_model(options)
        end
      end

      # Export font and return as YAML string
      #
      # @param options [Hash] Export options
      # @return [String] YAML representation
      def to_yaml(options = {})
        export_model = export_to_model(options)
        export_model.to_yaml
      end

      # Export font and return as JSON string
      #
      # @param options [Hash] Export options
      # @return [String] JSON representation
      def to_json(options = {})
        export_model = export_to_model(options)
        export_model.to_json
      end

      # Export font and return as TTX XML string
      #
      # Uses model-based architecture with FontToTtx transformer
      # and lutaml-model serialization.
      #
      # @param options [Hash] Export options
      # @option options [Array<String>] :tables Specific tables to export
      # @option options [Boolean] :pretty Pretty-print XML (default: true)
      # @option options [Integer] :indent Indentation spaces (default: 2)
      # @return [String] TTX XML representation
      def to_ttx(options = {})
        # Use new model-based architecture
        transformer = Transformers::FontToTtx.new(@font)
        ttx_model = transformer.transform(options)

        # Let lutaml-model handle XML serialization
        ttx_model.to_xml(
          pretty: options.fetch(:pretty, true),
          indent: options.fetch(:indent, 2),
        )
      end

      private

      # Export to FontExport model
      #
      # @param options [Hash] Export options
      # @return [Models::FontExport] The export model
      def export_to_model(options = {})
        table_list = options[:tables] || :all

        export_model = Models::FontExport.new
        export_model.metadata = build_metadata
        export_model.header = build_header

        tables_to_export = select_tables(table_list)
        tables_to_export.each do |tag|
          export_table(export_model, tag)
        end

        export_model
      end

      # Build export metadata
      #
      # @return [Models::FontExport::Metadata]
      def build_metadata
        Models::FontExport::Metadata.new.tap do |meta|
          meta.source_file = @source_path
          meta.export_date = Time.now.utc.iso8601
          meta.exporter_version = Fontisan::VERSION
          meta.font_format = detect_font_format
        end
      end

      # Build font header information
      #
      # @return [Models::FontExport::Header]
      def build_header
        Models::FontExport::Header.new.tap do |header|
          header.sfnt_version = format_sfnt_version(@font.header.sfnt_version.to_i)
          header.num_tables = @font.tables.size
          header.search_range = @font.header.search_range.to_i
          header.entry_selector = @font.header.entry_selector.to_i
          header.range_shift = @font.header.range_shift.to_i
        end
      end

      # Select tables to export
      #
      # @param table_list [Symbol, Array<String>] :all or list of table tags
      # @return [Array<String>] Table tags to export
      def select_tables(table_list)
        if table_list == :all
          @font.table_names
        else
          available = @font.table_names
          requested = Array(table_list).map(&:to_s)
          requested.select { |tag| available.include?(tag) }
        end
      end

      # Export a single table
      #
      # @param export_model [Models::FontExport] The export model
      # @param tag [String] The table tag
      # @return [void]
      def export_table(export_model, tag)
        table = @font.table(tag)
        return unless table

        checksum = calculate_table_checksum(tag)
        serialized = @serializer.serialize(table, tag)

        export_model.add_table(
          tag: tag,
          checksum: format_checksum(checksum),
          parsed: serialized[:parsed],
          data: serialized[:data],
          fields: serialized[:fields],
        )
      rescue StandardError => e
        # If serialization fails, store as binary
        export_binary_fallback(export_model, tag, e)
      end

      # Export table as binary fallback on error
      #
      # @param export_model [Models::FontExport] The export model
      # @param tag [String] The table tag
      # @param error [StandardError] The error that occurred
      # @return [void]
      def export_binary_fallback(export_model, tag, error)
        table = @font.table(tag)
        binary_data = table.respond_to?(:to_binary_s) ? table.to_binary_s : ""
        checksum = calculate_table_checksum(tag)

        export_model.add_table(
          tag: tag,
          checksum: format_checksum(checksum),
          parsed: false,
          data: @serializer.send(:encode_binary, binary_data),
          fields: { error: error.message }.to_json,
        )
      end

      # Calculate table checksum
      #
      # @param tag [String] Table tag
      # @return [Integer] Checksum value
      def calculate_table_checksum(tag)
        table_entry = @font.tables.find { |entry| entry.tag == tag }
        return 0 unless table_entry

        if table_entry.respond_to?(:checksum)
          table_entry.checksum.to_i
        else
          # Calculate from binary data
          table = @font.table(tag)
          data = table.respond_to?(:to_binary_s) ? table.to_binary_s : ""
          Utilities::ChecksumCalculator.calculate(data)
        end
      end

      # Format checksum as hex string
      #
      # @param checksum [Integer] Checksum value
      # @return [String] Hex string (e.g., "0x12345678")
      def format_checksum(checksum)
        "0x#{checksum.to_s(16).upcase.rjust(8, '0')}"
      end

      # Format SFNT version
      #
      # @param version [Integer] SFNT version
      # @return [String] Formatted version
      def format_sfnt_version(version)
        case version
        when 0x00010000
          "0x00010000 (TrueType)"
        when 0x4F54544F # 'OTTO'
          "0x4F54544F (OpenType/CFF)"
        else
          "0x#{version.to_s(16).upcase}"
        end
      end

      # Detect font format
      #
      # @return [String] Font format name
      def detect_font_format
        case @font.class.name
        when /TrueType/
          "TrueType"
        when /OpenType/
          "OpenType"
        when /Woff2/
          "WOFF2"
        when /Woff/
          "WOFF"
        else
          "Unknown"
        end
      end
    end
  end
end
