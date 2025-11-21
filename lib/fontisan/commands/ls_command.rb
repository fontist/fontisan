# frozen_string_literal: true

require_relative "../font_loader"
require_relative "../models/collection_list_info"
require_relative "../models/font_summary"
require_relative "../tables/name"
require_relative "../error"

module Fontisan
  module Commands
    # Command to list contents of font files (collections or individual fonts).
    #
    # This command provides a universal "ls" interface that auto-detects
    # whether the input is a collection (TTC/OTC) or individual font (TTF/OTF)
    # and returns the appropriate listing:
    # - For collections: Lists all fonts in the collection
    # - For individual fonts: Shows a quick summary
    #
    # @example List fonts in collection
    #   command = LsCommand.new("fonts.ttc")
    #   list = command.run
    #   puts "Contains #{list.num_fonts} fonts"
    #
    # @example Get font summary
    #   command = LsCommand.new("font.ttf")
    #   summary = command.run
    #   puts "#{summary.family_name} - #{summary.num_glyphs} glyphs"
    class LsCommand
      # Initialize ls command
      #
      # @param file_path [String] Path to font or collection file
      # @param options [Hash] Command options
      # @option options [Integer] :font_index Index for TTC/OTC (unused for ls)
      def initialize(file_path, options = {})
        @file_path = file_path
        @options = options
      end

      # Execute the ls command
      #
      # Auto-detects file type and returns appropriate model:
      # - CollectionListInfo for TTC/OTC files
      # - FontSummary for TTF/OTF files
      #
      # @return [CollectionListInfo, FontSummary] List or summary
      # @raise [Errno::ENOENT] if file does not exist
      # @raise [Error] for loading or processing failures
      def run
        if FontLoader.collection?(@file_path)
          list_collection
        else
          font_summary
        end
      rescue Errno::ENOENT
        raise
      rescue StandardError => e
        raise Error, "Failed to list file contents: #{e.message}"
      end

      private

      # List fonts in a collection
      #
      # @return [CollectionListInfo] List of fonts with metadata
      def list_collection
        collection = FontLoader.load_collection(@file_path)

        File.open(@file_path, "rb") do |io|
          list = collection.list_fonts(io)
          list.collection_path = @file_path
          list
        end
      end

      # Create summary for individual font
      #
      # @return [FontSummary] Quick font summary
      def font_summary
        font = FontLoader.load(@file_path)

        # Extract basic info
        name_table = font.table("name")
        post_table = font.table("post")

        family_name = name_table&.english_name(Tables::Name::FAMILY) || "Unknown"
        subfamily_name = name_table&.english_name(Tables::Name::SUBFAMILY) || "Regular"

        # Determine font format
        sfnt = font.header.sfnt_version
        font_format = case sfnt
                      when 0x00010000, 0x74727565 # 0x74727565 = 'true'
                        "TrueType"
                      when 0x4F54544F # 'OTTO'
                        "OpenType"
                      else
                        "Unknown"
                      end

        num_glyphs = post_table&.glyph_names&.length || 0
        num_tables = font.table_names.length

        Models::FontSummary.new(
          font_path: @file_path,
          family_name: family_name,
          subfamily_name: subfamily_name,
          font_format: font_format,
          num_glyphs: num_glyphs,
          num_tables: num_tables,
        )
      end
    end
  end
end
