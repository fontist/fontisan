# frozen_string_literal: true

require_relative "../font_loader"
require_relative "../error"

module Fontisan
  module Commands
    # Command to dump raw table data from fonts
    #
    # This command extracts the binary data of a specific OpenType table
    # and outputs it directly. This is useful for examining table contents
    # or extracting tables for external processing.
    class DumpTableCommand
      # Initialize a new dump table command
      #
      # @param font_path [String] Path to the font file
      # @param table_tag [String] Four-character table tag (e.g., 'name', 'head')
      # @param options [Hash] Optional command options
      # @option options [Integer] :font_index Index of font in TTC/OTC collection (default: 0)
      def initialize(font_path, table_tag, options = {})
        @font_path = font_path
        @table_tag = table_tag
        @options = options
        @font = load_font
      end

      # Execute the dump table command
      #
      # @return [String] Raw binary table data
      # @raise [Error] if table does not exist or data is not available
      def run
        unless @font.has_table?(@table_tag)
          raise Error,
                "Font does not have '#{@table_tag}' table"
        end

        # Get raw table data
        table_data = @font.instance_variable_get(:@table_data)
        raw_data = table_data[@table_tag]

        unless raw_data
          raise Error,
                "Table data not available for '#{@table_tag}'"
        end

        raw_data
      end

      private

      attr_reader :font

      # Load the font using FontLoader
      #
      # @return [TrueTypeFont, OpenTypeFont] The loaded font
      # @raise [Errno::ENOENT] if file does not exist
      # @raise [UnsupportedFormatError] for WOFF/WOFF2 or other unsupported formats
      # @raise [InvalidFontError] for corrupted or unknown formats
      # @raise [Error] for other loading failures
      def load_font
        FontLoader.load(@font_path, font_index: @options[:font_index] || 0)
      rescue Errno::ENOENT
        raise
      rescue UnsupportedFormatError, InvalidFontError
        raise
      rescue StandardError => e
        raise Error, "Failed to load font: #{e.message}"
      end
    end
  end
end
