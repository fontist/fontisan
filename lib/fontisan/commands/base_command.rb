# frozen_string_literal: true

require_relative "../font_loader"
require_relative "../error"

module Fontisan
  module Commands
    # Abstract base class for all CLI commands.
    #
    # Provides common functionality for loading fonts using FontLoader for
    # automatic format detection. Works polymorphically with TrueTypeFont
    # and OpenTypeFont instances.
    #
    # Subclasses must implement the `run` method to define command-specific behavior.
    #
    # @example Creating a command subclass
    #   class MyCommand < BaseCommand
    #     def run
    #       info = Models::FontInfo.new
    #       info.family_name = font.table("name").english_name(Tables::Name::FAMILY)
    #       info
    #     end
    #   end
    class BaseCommand
      # Initialize a new command with a font file path and options.
      #
      # @param font_path [String] Path to the font file
      # @param options [Hash] Optional command options
      # @option options [Integer] :font_index Index of font in TTC/OTC collection (default: 0)
      def initialize(font_path, options = {})
        @font_path = font_path
        @options = options
        @font = load_font
      end

      # Execute the command.
      #
      # This method must be implemented by subclasses.
      #
      # @raise [NotImplementedError] if not implemented by subclass
      # @return [Models::*] Command-specific result as lutaml-model object
      def run
        raise NotImplementedError, "Subclasses must implement the run method"
      end

      protected

      # @!attribute [r] font_path
      #   @return [String] Path to the font file
      # @!attribute [r] font
      #   @return [TrueTypeFont, OpenTypeFont] Loaded font instance
      # @!attribute [r] options
      #   @return [Hash] Command options
      attr_reader :font_path, :font, :options

      private

      # Load the font using FontLoader.
      #
      # Uses FontLoader for automatic format detection and loading.
      # Returns either TrueTypeFont or OpenTypeFont depending on file format.
      #
      # @return [TrueTypeFont, OpenTypeFont] The loaded font
      # @raise [Errno::ENOENT] if file does not exist
      # @raise [UnsupportedFormatError] for WOFF/WOFF2 or other unsupported formats
      # @raise [InvalidFontError] for corrupted or unknown formats
      # @raise [Error] for other loading failures
      def load_font
        # BaseCommand is for inspection - reject compressed formats first
        # Check file signature before attempting to load
        File.open(@font_path, "rb") do |io|
          signature = io.read(4)

          if signature == "wOFF"
            raise UnsupportedFormatError,
                  "Unsupported font format: WOFF files must be decompressed first. " \
                  "Use ConvertCommand to convert WOFF to TTF/OTF."
          elsif signature == "wOF2"
            raise UnsupportedFormatError,
                  "Unsupported font format: WOFF2 files must be decompressed first. " \
                  "Use ConvertCommand to convert WOFF2 to TTF/OTF."
          end
        end

        # Brief mode uses metadata loading for 5x faster parsing
        mode = @options[:brief] ? LoadingModes::METADATA : (@options[:mode] || LoadingModes::FULL)

        # ConvertCommand and similar commands need all tables loaded upfront
        # Use mode and lazy from options, or sensible defaults
        FontLoader.load(
          @font_path,
          font_index: @options[:font_index] || 0,
          mode: mode,
          lazy: @options.key?(:lazy) ? @options[:lazy] : false,
        )
      rescue Errno::ENOENT
        # Re-raise file not found as-is
        raise
      rescue UnsupportedFormatError, InvalidFontError
        # Re-raise format errors as-is
        raise
      rescue StandardError => e
        # Wrap other errors
        raise Error, "Failed to load font: #{e.message}"
      end
    end
  end
end
