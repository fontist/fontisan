# frozen_string_literal: true

module Fontisan
  module Collection
    # Shared logic for font collection classes
    #
    # This module provides common functionality for all collection types
    # (TTC, OTC, dfont) to maintain DRY principles.
    module SharedLogic
      # Calculate table sharing statistics
      #
      # Analyzes which tables are shared between fonts and calculates
      # space savings from deduplication.
      #
      # @param fonts [Array<TrueTypeFont, OpenTypeFont>] Array of fonts
      # @return [Models::TableSharingInfo] Sharing statistics
      def calculate_table_sharing_for_fonts(fonts)
        require_relative "../models/table_sharing_info"

        # Build table hash map (checksum -> size)
        table_map = {}
        total_table_size = 0

        fonts.each do |font|
          font.tables.each do |entry|
            key = entry.checksum
            size = entry.table_length
            table_map[key] ||= size
            total_table_size += size
          end
        end

        # Count unique vs shared
        unique_tables = table_map.size
        total_tables = fonts.sum { |f| f.tables.length }
        shared_tables = total_tables - unique_tables

        # Calculate space saved
        unique_size = table_map.values.sum
        space_saved = total_table_size - unique_size

        # Calculate sharing percentage
        sharing_pct = total_tables.positive? ? (shared_tables.to_f / total_tables * 100).round(2) : 0.0

        Models::TableSharingInfo.new(
          shared_tables: shared_tables,
          unique_tables: unique_tables,
          sharing_percentage: sharing_pct,
          space_saved_bytes: space_saved,
        )
      end
    end
  end
end
