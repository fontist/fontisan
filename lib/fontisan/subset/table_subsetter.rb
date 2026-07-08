# frozen_string_literal: true

module Fontisan
  module Subset
    # Table-specific subsetting dispatcher.
    #
    # Per-table subsetting logic lives in [TableStrategy] classes (one
    # per OpenType tag). This class:
    #
    #   1. Holds the inputs to a subsetting run (font, mapping, options)
    #      plus the cross-strategy [SharedState] (glyf/loca data, bbox,
    #      max advance, color bitmap subsetter cache).
    #   2. Dispatches `subset_table(tag, table)` to the right strategy
    #      via [TableStrategy.for(tag)].
    #   3. Keeps `subset_<tag>` wrappers for backward compatibility with
    #      specs that exercise a single strategy in isolation.
    #
    # Adding a new subsetting strategy does NOT require editing this
    # file — register it in `lib/fontisan/subset/table_strategy.rb`.
    #
    # @example Subset a single table
    #   subsetter = TableSubsetter.new(font, mapping, options)
    #   maxp_data = subsetter.subset_table("maxp", font.table("maxp"))
    class TableSubsetter
      # @return [SfntFont]
      attr_reader :font

      # @return [GlyphMapping]
      attr_reader :mapping

      # @return [Options]
      attr_reader :options

      # @return [SharedState]
      attr_reader :state

      def initialize(font, mapping, options)
        @font = font
        @mapping = mapping
        @options = options
        @state = SharedState.new
      end

      # Subset one table by dispatching to its strategy. Unknown tables
      # fall through to [TableStrategy::PassThrough] which preserves the
      # source bytes verbatim.
      #
      # @param tag [String] OpenType table tag (e.g. "glyf", "CBDT")
      # @param table [Object] parsed table object
      # @return [String] subset table binary bytes
      def subset_table(tag, table)
        TableStrategy.for(tag).call(
          context: subset_context, tag: tag, table: table,
        )
      end

      # --- Backward-compat wrappers --------------------------------------
      # Specs and external callers may invoke `subset_<tag>(table)`
      # directly. Each wrapper delegates to the corresponding strategy.

      def subset_maxp(table)
        subset_table("maxp", table)
      end

      def subset_hhea(table, hmtx = nil)
        _ = hmtx # ignored; the strategy recomputes from source hmtx
        subset_table("hhea", table)
      end

      def subset_hmtx(table)
        subset_table("hmtx", table)
      end

      def subset_glyf(table)
        subset_table("glyf", table)
      end

      def subset_loca(table)
        subset_table("loca", table)
      end

      def subset_cmap(table)
        subset_table("cmap", table)
      end

      def subset_post(table)
        subset_table("post", table)
      end

      def subset_name(table)
        subset_table("name", table)
      end

      def subset_head(table)
        subset_table("head", table)
      end

      def subset_os2(table)
        subset_table("OS/2", table)
      end

      private

      def subset_context
        SubsetContext.new(font: font, mapping: mapping, options: options,
                          state: state)
      end
    end
  end
end
