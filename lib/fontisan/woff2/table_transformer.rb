# frozen_string_literal: true

module Fontisan
  module Woff2
    # Table transformer for WOFF2 encoding
    #
    # [`Woff2::TableTransformer`](lib/fontisan/woff2/table_transformer.rb)
    # handles table transformations that improve compression in WOFF2.
    # The WOFF2 spec defines transformations for glyf/loca and hmtx tables.
    #
    # For Phase 2 Milestone 2.1:
    # - Architecture is in place for transformations
    # - Actual transformation implementations are marked as TODO
    # - Tables are copied as-is without transformation
    # - This allows valid WOFF2 generation while leaving room for optimization
    #
    # Future milestones will implement:
    # - glyf/loca transformation (combined stream, delta encoding)
    # - hmtx transformation (compact representation)
    #
    # Reference: https://www.w3.org/TR/WOFF2/#table_tranforms
    #
    # @example Transform tables for WOFF2
    #   transformer = TableTransformer.new(font)
    #   glyf_data = transformer.transform_table("glyf")
    class TableTransformer
      # @return [Object] Font object with table access
      attr_reader :font

      # Initialize transformer with font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      def initialize(font)
        @font = font
      end

      # Transform a table for WOFF2 encoding
      #
      # For Milestone 2.1, this returns the original table data
      # without transformation. The architecture supports future
      # implementation of actual transformations.
      #
      # @param tag [String] Table tag
      # @return [String, nil] Transformed (or original) table data
      def transform_table(tag)
        case tag
        when "glyf"
          transform_glyf
        when "loca"
          transform_loca
        when "hmtx"
          transform_hmtx
        else
          # No transformation, return original data
          get_table_data(tag)
        end
      end

      # Check if a table can be transformed
      #
      # @param tag [String] Table tag
      # @return [Boolean] True if table supports transformation
      def transformable?(tag)
        %w[glyf loca hmtx].include?(tag)
      end

      # Determine transformation version for a table
      #
      # For Milestone 2.1, always returns TRANSFORM_NONE since
      # we don't implement transformations yet.
      #
      # @param tag [String] Table tag
      # @return [Integer] Transformation version (0 = none)
      def transformation_version(_tag)
        # For this milestone, no transformations are applied
        Directory::TRANSFORM_NONE
      end

      private

      # Transform glyf table
      #
      # The WOFF2 glyf transformation combines glyf and loca into a
      # single stream with delta-encoded coordinates and flags.
      #
      # TODO: Implement full glyf transformation for better compression.
      # For now, returns original table data.
      #
      # @return [String, nil] Transformed glyf data
      def transform_glyf
        # TODO: Implement glyf transformation
        # This would involve:
        # 1. Parse all glyphs from glyf table
        # 2. Combine with loca offsets
        # 3. Create transformed stream with:
        #    - nContour values
        #    - nPoints values
        #    - Flag bytes (with run-length encoding)
        #    - x-coordinates (delta-encoded)
        #    - y-coordinates (delta-encoded)
        #    - Instruction bytes
        # 4. Use 255UInt16 encoding for variable-length integers
        #
        # Reference: https://www.w3.org/TR/WOFF2/#glyf_table_format

        get_table_data("glyf")
      end

      # Transform loca table
      #
      # In WOFF2, loca is combined with glyf during transformation.
      # When glyf is transformed, loca table is omitted from output.
      #
      # TODO: Implement loca transformation (combined with glyf).
      # For now, returns original table data.
      #
      # @return [String, nil] Transformed loca data
      def transform_loca
        # TODO: Implement loca transformation
        # When glyf transformation is implemented, loca will be:
        # 1. Combined into the transformed glyf stream
        # 2. Reconstructed during decompression
        # 3. Not present as separate table in WOFF2

        get_table_data("loca")
      end

      # Transform hmtx table
      #
      # The WOFF2 hmtx transformation stores advance widths more efficiently
      # by exploiting redundancy (many glyphs have same advance width).
      #
      # TODO: Implement hmtx transformation for better compression.
      # For now, returns original table data.
      #
      # @return [String, nil] Transformed hmtx data
      def transform_hmtx
        # TODO: Implement hmtx transformation
        # This would involve:
        # 1. Parse hmtx table
        # 2. Extract common advance widths
        # 3. Identify proportional vs monospace sections
        # 4. Use flags to indicate structure
        # 5. Store only unique advance widths
        # 6. Store LSB array separately
        #
        # Reference: https://www.w3.org/TR/WOFF2/#hmtx_table_format

        get_table_data("hmtx")
      end

      # Get raw table data from font
      #
      # @param tag [String] Table tag
      # @return [String, nil] Table data or nil if not found
      def get_table_data(tag)
        return nil unless font.respond_to?(:table_data)

        font.table_data(tag)
      end
    end
  end
end
