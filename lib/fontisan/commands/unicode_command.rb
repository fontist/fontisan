# frozen_string_literal: true

require_relative "base_command"
require_relative "../models/unicode_mappings"

module Fontisan
  module Commands
    # Command to list Unicode to glyph index mappings from a font file
    #
    # Retrieves character code to glyph index mappings from the cmap table.
    # Optionally includes glyph names from the post table if available.
    #
    # @example List Unicode mappings from a font
    #   command = UnicodeCommand.new("font.ttf")
    #   result = command.run
    #   puts result.count
    class UnicodeCommand < BaseCommand
      # Execute the command to retrieve Unicode mappings
      #
      # @return [Models::UnicodeMappings] Unicode to glyph mappings
      def run
        result = Models::UnicodeMappings.new
        result.mappings = []
        result.count = 0

        return result unless font.has_table?(Constants::CMAP_TAG)

        cmap_table = font.table(Constants::CMAP_TAG)
        mappings_hash = cmap_table.unicode_mappings

        return result if mappings_hash.empty?

        # Optionally get glyph names if post table exists
        glyph_names = fetch_glyph_names if font.has_table?(Constants::POST_TAG)

        # Convert hash to array of mapping objects, sorted by codepoint
        result.mappings = mappings_hash.map do |codepoint, glyph_index|
          Models::UnicodeMapping.new(
            codepoint: format_codepoint(codepoint),
            glyph_index: glyph_index,
            glyph_name: glyph_names&.[](glyph_index),
          )
        end.sort_by(&:codepoint)

        result.count = result.mappings.length
        result
      end

      private

      # Format codepoint as U+XXXX or U+XXXXXX
      #
      # @param codepoint [Integer] Unicode codepoint value
      # @return [String] Formatted codepoint string
      def format_codepoint(codepoint)
        if codepoint < 0x10000
          format("U+%04X", codepoint)
        else
          format("U+%X", codepoint)
        end
      end

      # Fetch glyph names from post table
      #
      # @return [Array<String>, nil] Array of glyph names or nil
      def fetch_glyph_names
        post_table = font.table(Constants::POST_TAG)
        names = post_table.glyph_names
        names if names&.any?
      rescue StandardError
        # If post table parsing fails, continue without glyph names
        nil
      end
    end
  end
end
