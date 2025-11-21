# frozen_string_literal: true

require_relative "base_command"
require_relative "../export/exporter"
require_relative "../font_loader"

module Fontisan
  module Commands
    # ExportCommand provides CLI interface for font export to YAML/JSON
    #
    # This command exports fonts to TTX-like YAML/JSON formats for debugging
    # and font analysis. Supports selective table export and both formats.
    #
    # @example Exporting entire font
    #   command = ExportCommand.new(
    #     input: "font.ttf",
    #     output: "font.yaml"
    #   )
    #   command.run
    #
    # @example Exporting specific tables
    #   command = ExportCommand.new(
    #     input: "font.ttf",
    #     output: "meta.yaml",
    #     tables: ["head", "name", "cmap"]
    #   )
    #   command.run
    class ExportCommand < BaseCommand
      # Initialize export command
      #
      # @param input [String] Path to input font file
      # @param output [String, nil] Path to output file (default: stdout)
      # @param format [Symbol] Output format (:yaml or :json)
      # @param tables [Array<String>, nil] Specific tables to export
      # @param binary_format [Symbol] Binary encoding (:hex or :base64)
      # @param pretty [Boolean] Pretty-print output
      def initialize(input:, output: nil, format: :yaml, tables: nil,
                     binary_format: :hex, pretty: true)
        super()
        @input = input
        @output = output
        @format = format.to_sym
        @tables = tables
        @binary_format = binary_format.to_sym
        @pretty = pretty
      end

      # Run the export command
      #
      # @return [Integer] Exit code (0 = success, 1 = error)
      def run
        validate_params!

        # Load font
        font = load_font
        return 1 unless font

        # Create exporter
        exporter = Export::Exporter.new(
          font,
          @input,
          binary_format: @binary_format,
        )

        # Export to model
        export_model = exporter.export(
          tables: @tables || :all,
          format: @format,
        )

        # Output result
        output_export(export_model)

        0
      rescue StandardError => e
        puts "Error: #{e.message}"
        puts e.backtrace.join("\n") if ENV["DEBUG"]
        1
      end

      private

      # Validate command parameters
      #
      # @raise [ArgumentError] if parameters are invalid
      # @return [void]
      def validate_params!
        if @input.nil? || @input.empty?
          raise ArgumentError,
                "Input file is required"
        end
        unless File.exist?(@input)
          raise ArgumentError,
                "Input file does not exist: #{@input}"
        end

        valid_formats = %i[yaml json ttx]
        unless valid_formats.include?(@format)
          raise ArgumentError,
                "Invalid format: #{@format}. Must be one of: #{valid_formats.join(', ')}"
        end

        valid_binary_formats = %i[hex base64]
        unless valid_binary_formats.include?(@binary_format)
          raise ArgumentError,
                "Invalid binary format: #{@binary_format}. " \
                "Must be one of: #{valid_binary_formats.join(', ')}"
        end

        # Validate output directory exists
        if @output
          output_dir = File.dirname(@output)
          unless Dir.exist?(output_dir)
            raise ArgumentError,
                  "Output directory does not exist: #{output_dir}"
          end
        end
      end

      # Load the font file
      #
      # @return [TrueTypeFont, OpenTypeFont, nil] The loaded font or nil on error
      def load_font
        FontLoader.load(@input)
      rescue StandardError => e
        puts "Error loading font: #{e.message}"
        nil
      end

      # Output the export
      #
      # @param export_model [Models::FontExport, String] The export model or TTX XML
      # @return [void]
      def output_export(export_model)
        content = if export_model.is_a?(String)
                    # TTX XML string
                    export_model
                  else
                    # FontExport model
                    case @format
                    when :yaml
                      export_model.to_yaml
                    when :json
                      if @pretty
                        JSON.pretty_generate(JSON.parse(export_model.to_json))
                      else
                        export_model.to_json
                      end
                    end
                  end

        if @output
          File.write(@output, content)
          puts "Exported to #{@output}"
        else
          puts content
        end
      end
    end
  end
end
