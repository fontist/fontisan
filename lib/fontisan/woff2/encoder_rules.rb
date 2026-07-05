# frozen_string_literal: true

module Fontisan
  module Woff2
    # Applies WOFF2 spec "encoder MUST" rules to a table collection before
    # the table directory is built and brotli compression is applied.
    #
    # Each spec-mandated transform lives here so the encoder stays a thin
    # orchestrator and new rules are MECE/discoverable instead of sprinkled
    # as inline conditionals across Woff2Encoder.
    #
    # Reference: W3C WOFF2 spec, section 5 ("Recommended table directory").
    class EncoderRules
      # Tables that MUST NOT appear in WOFF2 output.
      #
      # Per spec section 5: "The compliant WOFF2 encoder MUST remove the
      # DSIG table from an input font data, prior to applying
      # transformations and entropy coding steps." Chrome's OpenType
      # Sanitizer (OTS) rejects WOFF2 files that still contain DSIG.
      EXCLUDED_TABLES = %w[DSIG].freeze

      # Apply all WOFF2 encoder rules to `table_data` in place.
      #
      # @param table_data [Hash{String => String}] Map of tag → binary
      #   table data. Mutated.
      # @return [Hash{String => String}] The same hash, for chaining.
      def self.apply!(table_data)
        exclude_tables!(table_data)
        mark_lossless_modifying!(table_data)
        table_data
      end

      # Whether `tag` is dropped by WOFF2 spec rules.
      def self.excluded?(tag)
        EXCLUDED_TABLES.include?(tag)
      end

      # Drop spec-excluded tables from the collection.
      def self.exclude_tables!(table_data)
        EXCLUDED_TABLES.each { |tag| table_data.delete(tag) }
      end

      # Set head.flags bit 11 to indicate the font was losslessly modified.
      #
      # Per spec section 5: "The WOFF 2.0 encoders MUST also set bit 11 of
      # the 'flags' field of the head table ... to indicate that a recreated
      # font file was subjected to lossless modifying transform."
      #
      # Uses the model-driven Head BinData record so the bit is set via a
      # named attribute on a typed object, not via raw byte slicing.
      def self.mark_lossless_modifying!(table_data)
        return unless table_data.key?("head")

        head = Tables::Head.read(table_data["head"])
        head.flags |= Tables::Head::FLAG_LOSSLESS_MODIFYING
        table_data["head"] = head.to_binary_s
      end
    end
  end
end
