# frozen_string_literal: true

require_relative "table_updater"
require_relative "../font_writer"

module Fontisan
  module Variable
    # Builds static font instances from variable font data
    #
    # This class takes a variable font and applied variation data,
    # then constructs a complete static font by:
    # 1. Copying all non-variation tables unchanged
    # 2. Removing variation-specific tables (fvar, gvar, HVAR, etc.)
    # 3. Updating metric tables (hmtx, hhea) with varied values
    # 4. Updating head table's modified timestamp
    # 5. Writing the complete static font binary
    #
    # The result is a valid static font at the specified instance point.
    #
    # @example Build static font
    #   builder = StaticFontBuilder.new(font)
    #   static_binary = builder.build(varied_metrics, font_metrics)
    class StaticFontBuilder
      # Tables to remove from static font (variation-specific)
      VARIATION_TABLES = %w[fvar avar gvar cvar HVAR VVAR MVAR STAT].freeze

      # @return [TableUpdater] Table updater instance
      attr_reader :table_updater

      # Initialize the builder
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font object
      def initialize(font)
        @font = font
        @table_updater = TableUpdater.new
      end

      # Build static font from varied data
      #
      # @param varied_metrics [Hash<Integer, Hash>] Varied metrics by glyph ID
      #   { glyph_id => { advance_width: 500, lsb: 50 } }
      # @param font_metrics [Hash] Varied font-level metrics
      #   { ascent: 2048, descent: -512, line_gap: 0 }
      # @param options [Hash] Build options
      # @option options [Boolean] :update_modified Update head modified timestamp
      # @return [String] Complete static font binary
      def build(varied_metrics = {}, font_metrics = {}, options = {})
        # Collect tables for static font
        tables = collect_tables(varied_metrics, font_metrics, options)

        # Detect sfnt version
        sfnt_version = detect_sfnt_version(tables)

        # Write font using FontWriter
        FontWriter.write_font(tables, sfnt_version: sfnt_version)
      end

      # Build static font and write to file
      #
      # @param output_path [String] Output file path
      # @param varied_metrics [Hash<Integer, Hash>] Varied metrics by glyph ID
      # @param font_metrics [Hash] Varied font-level metrics
      # @param options [Hash] Build options
      # @return [Integer] Number of bytes written
      def build_to_file(output_path, varied_metrics = {}, font_metrics = {},
options = {})
        binary = build(varied_metrics, font_metrics, options)
        File.binwrite(output_path, binary)
      end

      private

      # Collect all tables for static font
      #
      # @param varied_metrics [Hash] Varied glyph metrics
      # @param font_metrics [Hash] Varied font metrics
      # @param options [Hash] Build options
      # @return [Hash<String, String>] Map of table tag to binary data
      def collect_tables(varied_metrics, font_metrics, options)
        tables = {}

        # Get all table tags from font
        table_tags = @font.respond_to?(:tables) ? @font.tables.keys : []

        table_tags.each do |tag|
          # Skip variation tables
          next if VARIATION_TABLES.include?(tag)

          # Get original table data
          original_data = @font.table_data(tag)
          next if original_data.nil? || original_data.empty?

          # Update specific tables with varied data
          tables[tag] = case tag
                        when "hmtx"
                          update_hmtx_table(original_data, varied_metrics)
                        when "hhea"
                          update_hhea_table(original_data, font_metrics)
                        when "OS/2"
                          update_os2_table(original_data, font_metrics)
                        when "head"
                          update_head_table(original_data, options)
                        else
                          # Copy unchanged
                          original_data
                        end
        end

        tables
      end

      # Update hmtx table with varied metrics
      #
      # @param original_data [String] Original table data
      # @param varied_metrics [Hash] Varied glyph metrics
      # @return [String] Updated table data
      def update_hmtx_table(original_data, varied_metrics)
        return original_data if varied_metrics.empty?

        # Get required context from other tables
        hhea = load_table("hhea")
        maxp = load_table("maxp")

        return original_data unless hhea && maxp

        num_h_metrics = hhea.number_of_h_metrics
        num_glyphs = maxp.num_glyphs

        @table_updater.update_hmtx(
          original_data,
          varied_metrics,
          num_h_metrics,
          num_glyphs,
        )
      end

      # Update hhea table with varied metrics
      #
      # @param original_data [String] Original table data
      # @param font_metrics [Hash] Varied font metrics
      # @return [String] Updated table data
      def update_hhea_table(original_data, font_metrics)
        return original_data if font_metrics.empty?

        # Extract hhea-specific metrics
        hhea_metrics = {}
        hhea_metrics[:ascent] = font_metrics["hasc"] if font_metrics["hasc"]
        hhea_metrics[:descent] = font_metrics["hdsc"] if font_metrics["hdsc"]
        hhea_metrics[:line_gap] = font_metrics["hlgp"] if font_metrics["hlgp"]

        return original_data if hhea_metrics.empty?

        @table_updater.update_hhea(original_data, hhea_metrics)
      end

      # Update OS/2 table with varied metrics
      #
      # @param original_data [String] Original table data
      # @param font_metrics [Hash] Varied font metrics
      # @return [String] Updated table data
      def update_os2_table(original_data, font_metrics)
        return original_data if font_metrics.empty?

        @table_updater.update_os2(original_data, font_metrics)
      end

      # Update head table
      #
      # @param original_data [String] Original table data
      # @param options [Hash] Build options
      # @return [String] Updated table data
      def update_head_table(original_data, options)
        if options[:update_modified] == false
          original_data
        else
          @table_updater.update_head_modified(original_data)
        end
      end

      # Load a table from the font
      #
      # @param tag [String] Table tag
      # @return [Object, nil] Parsed table or nil
      def load_table(tag)
        data = @font.table_data(tag)
        return nil if data.nil? || data.empty?

        table_class = case tag
                      when "hhea" then Tables::Hhea
                      when "maxp" then Tables::Maxp
                      when "head" then Tables::Head
                      else return nil
                      end

        table_class.read(data)
      rescue StandardError
        nil
      end

      # Detect sfnt version from tables
      #
      # @param tables [Hash] Map of table tag to data
      # @return [Integer] sfnt version
      def detect_sfnt_version(tables)
        if tables.key?("CFF ") || tables.key?("CFF2")
          0x4F54544F # 'OTTO' for OpenType/CFF
        else
          0x00010000 # 1.0 for TrueType
        end
      end
    end
  end
end
