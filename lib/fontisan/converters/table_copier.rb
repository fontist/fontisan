# frozen_string_literal: true

require_relative "conversion_strategy"

module Fontisan
  module Converters
    # Strategy for same-format font operations (copy/optimize)
    #
    # [`TableCopier`](lib/fontisan/converters/table_copier.rb) handles
    # conversions where the source and target formats are the same.
    # This is useful for:
    # - Creating a clean copy of a font
    # - Re-ordering tables
    # - Removing corruption
    # - Normalizing structure
    #
    # The strategy simply copies all tables from the source font
    # and reassembles them with proper checksums and offsets.
    #
    # @example Using TableCopier
    #   copier = Fontisan::Converters::TableCopier.new
    #   tables = copier.convert(font)
    #   binary = FontWriter.write_font(tables)
    class TableCopier
      include ConversionStrategy

      # Convert font by copying all tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Conversion options (currently unused)
      # @return [Hash<String, String>] Map of table tags to binary data
      def convert(font, _options = {})
        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:tables)
          raise ArgumentError, "Font must respond to :tables"
        end

        unless font.respond_to?(:table_data)
          raise ArgumentError, "Font must respond to :table_data"
        end

        target_format = detect_format(font)
        validate(font, target_format)

        tables = {}

        # Copy all tables from source font
        font.table_data.each do |tag, data|
          tables[tag] = data if data
        end

        tables
      end

      # Get supported conversions
      #
      # Supports same-format conversions for TTF and OTF
      #
      # @return [Array<Array<Symbol>>] Supported conversion pairs
      def supported_conversions
        [
          %i[ttf ttf],
          %i[otf otf],
        ]
      end

      # Validate font for copying
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param target_format [Symbol] Target format (same as source for copier)
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If font is invalid
      # @raise [Error] If formats don't match
      def validate(font, target_format)
        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:tables)
          raise ArgumentError, "Font must respond to :tables"
        end

        unless font.respond_to?(:table_data)
          raise ArgumentError, "Font must respond to :table_data"
        end

        # Detect source format and verify it matches target
        source_format = detect_format(font)
        unless source_format == target_format
          raise Fontisan::Error,
                "TableCopier requires source and target formats to match. " \
                "Got source: #{source_format}, target: #{target_format}"
        end

        true
      end

      private

      # Detect font format from tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to detect
      # @return [Symbol] Format (:ttf or :otf)
      def detect_format(font)
        # Check for CFF/CFF2 tables (OpenType/CFF)
        if font.has_table?("CFF ") || font.has_table?("CFF2")
          :otf
        # Check for glyf table (TrueType)
        elsif font.has_table?("glyf")
          :ttf
        else
          raise Fontisan::Error,
                "Cannot detect font format: missing both CFF and glyf tables"
        end
      end
    end
  end
end
