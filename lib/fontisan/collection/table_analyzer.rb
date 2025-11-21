# frozen_string_literal: true

require "digest/sha2"

module Fontisan
  module Collection
    # TableAnalyzer analyzes tables across multiple fonts to identify sharing opportunities
    #
    # Single responsibility: Analyze tables across fonts to identify identical tables
    # that can be shared in a font collection. Uses SHA256 checksums for reliable
    # content comparison.
    #
    # @example Analyze tables across fonts
    #   analyzer = TableAnalyzer.new([font1, font2, font3])
    #   report = analyzer.analyze
    #   puts "Potential savings: #{report[:space_savings]} bytes"
    #   puts "Shared tables: #{report[:shared_tables].keys.join(', ')}"
    class TableAnalyzer
      # Analysis report structure
      # @return [Hash] Analysis results
      attr_reader :report

      # Initialize analyzer with fonts
      #
      # @param fonts [Array<TrueTypeFont, OpenTypeFont>] Fonts to analyze
      # @raise [ArgumentError] if fonts array is empty or contains invalid fonts
      def initialize(fonts)
        if fonts.nil? || fonts.empty?
          raise ArgumentError,
                "fonts cannot be nil or empty"
        end
        raise ArgumentError, "fonts must be an array" unless fonts.is_a?(Array)

        @fonts = fonts
        @report = nil
      end

      # Analyze tables across all fonts
      #
      # Identifies tables that are identical across fonts based on content checksum.
      # Returns a comprehensive analysis report with sharing opportunities and
      # potential space savings.
      #
      # @return [Hash] Analysis report with:
      #   - :total_fonts [Integer] Number of fonts analyzed
      #   - :table_checksums [Hash<String, Hash>] Map of tag to checksum to font indices
      #   - :shared_tables [Hash<String, Array>] Map of tag to array of font indices sharing that table
      #   - :unique_tables [Hash<String, Array>] Map of tag to array of font indices with unique versions
      #   - :space_savings [Integer] Potential bytes saved by sharing
      #   - :sharing_percentage [Float] Percentage of tables that can be shared
      def analyze
        @report = {
          total_fonts: @fonts.size,
          table_checksums: {},
          shared_tables: {},
          unique_tables: {},
          space_savings: 0,
          sharing_percentage: 0.0,
        }

        # Collect checksums for all tables across all fonts
        collect_table_checksums

        # Identify which tables are shared
        identify_shared_tables

        # Calculate space savings
        calculate_space_savings

        @report
      end

      # Get tables that can be shared
      #
      # @return [Hash<String, Array<Integer>>] Map of table tag to font indices
      def shared_tables
        analyze unless @report
        @report[:shared_tables]
      end

      # Get potential space savings in bytes
      #
      # @return [Integer] Bytes that can be saved by sharing
      def space_savings
        analyze unless @report
        @report[:space_savings]
      end

      # Get sharing percentage
      #
      # @return [Float] Percentage of tables that can be shared (0.0-100.0)
      def sharing_percentage
        analyze unless @report
        @report[:sharing_percentage]
      end

      private

      # Collect checksums for all tables in all fonts
      #
      # Builds a map of: tag -> checksum -> array of font indices
      # This allows quick identification of which fonts share identical tables.
      #
      # @return [void]
      def collect_table_checksums
        @fonts.each_with_index do |font, font_index|
          font.table_names.each do |tag|
            # Get raw table data
            table_data = font.table_data[tag]
            next unless table_data

            # Calculate checksum
            checksum = calculate_checksum(table_data)

            # Store in report
            @report[:table_checksums][tag] ||= {}
            @report[:table_checksums][tag][checksum] ||= []
            @report[:table_checksums][tag][checksum] << font_index
          end
        end
      end

      # Identify which tables are shared across fonts
      #
      # A table is considered shared if 2 or more fonts have identical content
      # (same checksum) for that table.
      #
      # @return [void]
      def identify_shared_tables
        @report[:table_checksums].each do |tag, checksums|
          checksums.each do |checksum, font_indices|
            if font_indices.size > 1
              # This table is shared across multiple fonts
              @report[:shared_tables][tag] ||= []
              @report[:shared_tables][tag] << {
                checksum: checksum,
                font_indices: font_indices,
                count: font_indices.size,
              }
            else
              # This table is unique to one font
              @report[:unique_tables][tag] ||= []
              @report[:unique_tables][tag] << {
                checksum: checksum,
                font_index: font_indices.first,
              }
            end
          end
        end
      end

      # Calculate potential space savings from table sharing
      #
      # Space is saved when N fonts share a table - we only need to store it once
      # instead of N times. Savings = (N-1) * table_size
      #
      # @return [void]
      def calculate_space_savings
        total_savings = 0
        total_table_instances = 0
        shared_table_instances = 0

        @report[:shared_tables].each do |tag, sharing_groups|
          sharing_groups.each do |group|
            font_indices = group[:font_indices]
            count = font_indices.size

            # Get table size from first font in group
            table_data = @fonts[font_indices.first].table_data[tag]
            table_size = table_data.bytesize

            # Savings = (count - 1) * table_size
            # We only need to store the table once instead of count times
            savings = (count - 1) * table_size
            total_savings += savings

            shared_table_instances += count
          end
        end

        # Count total table instances
        @fonts.each do |font|
          total_table_instances += font.table_names.size
        end

        @report[:space_savings] = total_savings

        # Calculate sharing percentage
        if total_table_instances.positive?
          @report[:sharing_percentage] =
            (shared_table_instances.to_f / total_table_instances * 100).round(2)
        end
      end

      # Calculate SHA256 checksum for table data
      #
      # @param data [String] Binary table data
      # @return [String] Hexadecimal checksum
      def calculate_checksum(data)
        Digest::SHA256.hexdigest(data)
      end
    end
  end
end
