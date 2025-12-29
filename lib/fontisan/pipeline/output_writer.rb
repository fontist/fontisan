# frozen_string_literal: true

require_relative "../font_writer"

module Fontisan
  module Pipeline
    # Handles writing font tables to various output formats
    #
    # This class abstracts the complexity of writing different font formats:
    # - SFNT formats (TTF, OTF) via FontWriter
    # - WOFF via WoffWriter
    # - WOFF2 via Woff2Encoder
    #
    # Single Responsibility: Coordinate output writing for different formats
    #
    # @example Write TTF font
    #   writer = OutputWriter.new("output.ttf", :ttf)
    #   writer.write(tables)
    #
    # @example Write OTF font
    #   writer = OutputWriter.new("output.otf", :otf)
    #   writer.write(tables)
    class OutputWriter
      # @return [String] Output file path
      attr_reader :output_path

      # @return [Symbol] Target format
      attr_reader :format

      # @return [Hash] Writing options
      attr_reader :options

      # Initialize output writer
      #
      # @param output_path [String] Path to write output
      # @param format [Symbol] Target format (:ttf, :otf, :woff, :woff2)
      # @param options [Hash] Writing options
      def initialize(output_path, format, options = {})
        @output_path = output_path
        @format = format
        @options = options
      end

      # Write font tables to output file
      #
      # @param tables [Hash<String, String>, Hash] Font tables (tag => binary data) or special format result
      # @return [Integer] Number of bytes written
      # @raise [ArgumentError] If format is unsupported
      def write(tables)
        case @format
        when :ttf, :otf
          write_sfnt(tables)
        when :woff
          write_woff(tables)
        when :woff2
          write_woff2(tables)
        when :svg
          write_svg(tables)
        else
          raise ArgumentError, "Unsupported output format: #{@format}"
        end
      end

      private

      # Write SVG format
      #
      # @param result [Hash] Result with :svg_xml key
      # @return [Integer] Number of bytes written
      def write_svg(result)
        svg_xml = result[:svg_xml] || result["svg_xml"]
        unless svg_xml
          raise ArgumentError,
                "SVG result must contain :svg_xml key"
        end

        File.write(@output_path, svg_xml)
      end

      # Write SFNT format (TTF or OTF)
      #
      # @param tables [Hash<String, String>] Font tables
      # @return [Integer] Number of bytes written
      def write_sfnt(tables)
        sfnt_version = determine_sfnt_version
        FontWriter.write_to_file(tables, @output_path,
                                 sfnt_version: sfnt_version)
      end

      # Write WOFF format
      #
      # @param tables [Hash<String, String>] Font tables
      # @return [Integer] Number of bytes written
      def write_woff(tables)
        require_relative "../converters/woff_writer"

        writer = Converters::WoffWriter.new
        font = build_font_from_tables(tables)
        result = writer.convert(font, @options)

        File.binwrite(@output_path, result[:woff_data])
      end

      # Write WOFF2 format
      #
      # @param tables [Hash<String, String>] Font tables
      # @return [Integer] Number of bytes written
      def write_woff2(tables)
        require_relative "../converters/woff2_encoder"

        encoder = Converters::Woff2Encoder.new
        font = build_font_from_tables(tables)
        result = encoder.convert(font, @options)

        File.binwrite(@output_path, result[:woff2_binary])
      end

      # Determine SFNT version based on format and tables
      #
      # @return [Integer] SFNT version (0x00010000 for TTF, 0x4F54544F for OTF)
      def determine_sfnt_version
        case @format
        when :ttf, :woff, :woff2 then 0x00010000
        when :otf then 0x4F54544F # 'OTTO'
        else raise ArgumentError, "Unsupported format: #{@format}"
        end
      end

      # Build font object from tables
      #
      # Helper to create font object from tables for converters that need it.
      #
      # @param tables [Hash<String, String>] Font tables
      # @return [Font] Font object
      def build_font_from_tables(tables)
        # Detect font type from tables
        has_cff = tables.key?("CFF ") || tables.key?("CFF2")
        has_glyf = tables.key?("glyf")

        if has_cff
          OpenTypeFont.from_tables(tables)
        elsif has_glyf
          TrueTypeFont.from_tables(tables)
        else
          # Default based on format
          case @format
          when :ttf, :woff, :woff2
            TrueTypeFont.from_tables(tables)
          when :otf
            OpenTypeFont.from_tables(tables)
          else
            raise ArgumentError,
                  "Cannot determine font type for format: #{@format}"
          end
        end
      end
    end
  end
end
