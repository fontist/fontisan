# frozen_string_literal: true

require "digest/sha2"

module Fontisan
  module Collection
    # TableDeduplicator deduplicates identical tables across fonts
    #
    # Single responsibility: Group identical tables and create a canonical mapping
    # for shared table references. Ensures that each unique table content is stored
    # only once in the collection.
    #
    # @example Deduplicate tables
    #   deduplicator = TableDeduplicator.new([font1, font2, font3])
    #   sharing_map = deduplicator.build_sharing_map
    #   canonical_tables = deduplicator.canonical_tables
    class TableDeduplicator
      # Canonical tables (unique table data)
      # @return [Hash<String, Hash>] Map of table tag to canonical versions
      attr_reader :canonical_tables

      # Sharing map (font -> table -> canonical reference)
      # @return [Hash<Integer, Hash<String, Hash>>] Sharing map
      attr_reader :sharing_map

      # Initialize deduplicator with fonts
      #
      # @param fonts [Array<TrueTypeFont, OpenTypeFont>] Fonts to process
      # @raise [ArgumentError] if fonts array is empty or invalid
      def initialize(fonts)
        if fonts.nil? || fonts.empty?
          raise ArgumentError,
                "fonts cannot be nil or empty"
        end
        raise ArgumentError, "fonts must be an array" unless fonts.is_a?(Array)

        @fonts = fonts
        @canonical_tables = {}
        @sharing_map = {}
        @checksum_to_canonical = {}
      end

      # Build sharing map for all fonts
      #
      # Creates a map structure that indicates which canonical table each font
      # should reference for each table tag. This enables efficient table sharing
      # in the final collection.
      #
      # @return [Hash<Integer, Hash<String, Hash>>] Sharing map with structure:
      #   {
      #     font_index => {
      #       table_tag => {
      #         canonical_id: unique_id,
      #         checksum: sha256_checksum,
      #         data: table_data,
      #         shared: true/false,
      #         shared_with: [font_indices]
      #       }
      #     }
      #   }
      def build_sharing_map
        # First pass: collect all unique tables
        collect_canonical_tables

        # Second pass: build sharing map for each font
        build_font_sharing_references

        @sharing_map
      end

      # Get canonical table data for a specific table
      #
      # @param tag [String] Table tag
      # @param canonical_id [String] Canonical table identifier
      # @return [String, nil] Binary table data
      def canonical_table_data(tag, canonical_id)
        @canonical_tables.dig(tag, canonical_id, :data)
      end

      # Get all canonical tables for a specific tag
      #
      # @param tag [String] Table tag
      # @return [Hash<String, Hash>, nil] Map of canonical_id to table info
      def canonical_tables_for_tag(tag)
        @canonical_tables[tag]
      end

      # Get sharing statistics
      #
      # @return [Hash] Statistics about table sharing
      def statistics
        total_tables = 0
        shared_tables = 0
        unique_tables = 0

        @sharing_map.each_value do |tables|
          tables.each_value do |info|
            total_tables += 1
            if info[:shared]
              shared_tables += 1
            else
              unique_tables += 1
            end
          end
        end

        {
          total_tables: total_tables,
          shared_tables: shared_tables,
          unique_tables: unique_tables,
          sharing_percentage: total_tables.positive? ? (shared_tables.to_f / total_tables * 100).round(2) : 0.0,
          canonical_count: @canonical_tables.values.sum(&:size),
        }
      end

      private

      # Collect all unique (canonical) tables across all fonts
      #
      # Identifies unique table content based on checksum and stores one
      # canonical version of each unique table.
      #
      # @return [void]
      def collect_canonical_tables
        @fonts.each_with_index do |font, font_index|
          font.table_names.each do |tag|
            table_data = font.table_data[tag]
            next unless table_data

            # Calculate checksum
            checksum = calculate_checksum(table_data)

            # Check if we've seen this exact table content before
            canonical_id = find_or_create_canonical(tag, checksum, table_data,
                                                    font_index)

            # Track which fonts use this canonical table
            @canonical_tables[tag][canonical_id][:font_indices] << font_index
          end
        end

        # Mark shared tables
        mark_shared_tables
      end

      # Find existing canonical table or create new one
      #
      # @param tag [String] Table tag
      # @param checksum [String] Table checksum
      # @param data [String] Table data
      # @param font_index [Integer] Font index
      # @return [String] Canonical table ID
      def find_or_create_canonical(tag, checksum, data, _font_index)
        # Initialize tag entry if needed
        @canonical_tables[tag] ||= {}
        @checksum_to_canonical[tag] ||= {}

        # Check if we already have this exact table content
        if @checksum_to_canonical[tag][checksum]
          # Reuse existing canonical table
          @checksum_to_canonical[tag][checksum]
        else
          # Create new canonical table
          canonical_id = generate_canonical_id(tag, checksum)
          @checksum_to_canonical[tag][checksum] = canonical_id

          @canonical_tables[tag][canonical_id] = {
            checksum: checksum,
            data: data,
            size: data.bytesize,
            font_indices: [],
            shared: false,
          }

          canonical_id
        end
      end

      # Generate unique canonical ID for a table
      #
      # @param tag [String] Table tag
      # @param checksum [String] Table checksum
      # @return [String] Canonical ID
      def generate_canonical_id(tag, checksum)
        # Use first 12 characters of checksum for brevity
        "#{tag}_#{checksum[0...12]}"
      end

      # Mark tables that are shared across multiple fonts
      #
      # @return [void]
      def mark_shared_tables
        @canonical_tables.each_value do |canonical_versions|
          canonical_versions.each_value do |info|
            info[:shared] = info[:font_indices].size > 1
            info[:shared_with] = info[:font_indices].dup if info[:shared]
          end
        end
      end

      # Build sharing references for each font
      #
      # Creates a map for each font indicating which canonical table it should
      # reference for each tag.
      #
      # @return [void]
      def build_font_sharing_references
        @fonts.each_with_index do |font, font_index|
          @sharing_map[font_index] = {}

          font.table_names.each do |tag|
            table_data = font.table_data[tag]
            next unless table_data

            checksum = calculate_checksum(table_data)
            canonical_id = @checksum_to_canonical[tag][checksum]

            # Reference canonical table
            canonical_info = @canonical_tables[tag][canonical_id]
            @sharing_map[font_index][tag] = {
              canonical_id: canonical_id,
              checksum: checksum,
              data: canonical_info[:data],
              size: canonical_info[:size],
              shared: canonical_info[:shared],
              shared_with: canonical_info[:shared_with] || [],
            }
          end
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
