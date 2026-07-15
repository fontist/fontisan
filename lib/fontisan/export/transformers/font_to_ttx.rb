# frozen_string_literal: true

module Fontisan
  module Export
    module Transformers
      # FontToTtx orchestrates font to TTX transformation
      #
      # Main transformer that coordinates conversion of a complete
      # font to TTX format using individual table transformers.
      # Follows model-to-model transformation principles with
      # clean separation of concerns.
      class FontToTtx
        # Initialize transformer
        #
        # @param font [TrueTypeFont, OpenTypeFont] Source font
        def initialize(font)
          @font = font
        end

        # Transform font to TTX model
        #
        # @param options [Hash] Transformation options
        # @option options [Array<String>] :tables Specific tables to include
        # @return [Models::Ttx::TtFont] Complete TTX model
        def transform(options = {})
          table_list = options[:tables] || :all

          Models::Ttx::TtFont.new.tap do |ttx|
            ttx.sfnt_version = format_sfnt_version(@font.header.sfnt_version.to_i)
            ttx.ttlib_version = "4.0"
            ttx.glyph_order = build_glyph_order

            # Transform specific tables
            tables_to_transform = select_tables(table_list)
            tables_to_transform.each do |tag|
              transform_table(ttx, tag)
            end
          end
        end

        private

        # Build glyph order model
        #
        # @return [Models::Ttx::GlyphOrder] Glyph order model
        def build_glyph_order
          Models::Ttx::GlyphOrder.new.tap do |glyph_order|
            glyph_order.glyph_ids = build_glyph_ids
          end
        end

        # Build glyph ID entries
        #
        # @return [Array<Models::Ttx::GlyphId>] Glyph ID models
        def build_glyph_ids
          Array.new(glyph_count) do |glyph_id|
            Models::Ttx::GlyphId.new.tap do |gid|
              gid.id = glyph_id
              gid.name = get_glyph_name(glyph_id)
            end
          end
        end

        # Transform individual table
        #
        public

        # Per-tag TTX model transformer dispatch.
        TABLE_TRANSFORMERS = {
          "head" => [HeadTransformer, :head_table=],
          "hhea" => [HheaTransformer, :hhea_table=],
          "maxp" => [MaxpTransformer, :maxp_table=],
          "name" => [NameTransformer, :name_table=],
          "OS/2" => [Os2Transformer, :os2_table=],
          "post" => [PostTransformer, :post_table=],
        }.freeze

        def transform_table(ttx, tag)
          table = @font.table(tag)
          return unless table

          entry = TABLE_TRANSFORMERS[tag]
          if entry
            transformer, setter = entry
            ttx.public_send(setter, transformer.transform(table))
          else
            # Fallback to binary table
            binary_table = transform_binary_table(tag, table)
            ttx.binary_tables ||= []
            ttx.binary_tables << binary_table if binary_table
          end
        rescue StandardError => e
          # On error, fall back to binary representation
          warn "Error transforming #{tag}: #{e.message}"
          binary_table = transform_binary_table(tag, table)
          ttx.binary_tables ||= []
          ttx.binary_tables << binary_table if binary_table
        end

        # Transform table to binary representation
        #
        # @param tag [String] Table tag
        # @param table [Object] Table object
        # @return [Models::Ttx::Tables::BinaryTable, nil] Binary table model
        def transform_binary_table(tag, table)
          binary_data = table ? table.to_binary_s : ""
          return nil if binary_data.empty?

          Models::Ttx::Tables::BinaryTable.new.tap do |bin_table|
            bin_table.tag = tag
            bin_table.hexdata = binary_data
          end
        end

        # Select tables to transform
        #
        # @param table_list [Symbol, Array<String>] :all or list of tags
        # @return [Array<String>] Table tags to transform
        def select_tables(table_list)
          if table_list == :all
            @font.table_names
          else
            available = @font.table_names
            requested = Array(table_list).map(&:to_s)
            requested.select { |tag| available.include?(tag) }
          end
        end

        # Get number of glyphs
        #
        # @return [Integer] Number of glyphs
        def glyph_count
          maxp = @font.table("maxp")
          maxp ? maxp.num_glyphs.to_i : 0
        end

        # Get glyph name by ID
        #
        # @param glyph_id [Integer] Glyph ID
        # @return [String] Glyph name
        def get_glyph_name(glyph_id)
          post = @font.table("post")
          if post.is_a?(Tables::Post) && post.glyph_names
            post.glyph_names[glyph_id] || ".notdef"
          elsif glyph_id.zero?
            ".notdef"
          else
            "glyph#{glyph_id.to_s.rjust(5, '0')}"
          end
        end

        # Format SFNT version
        #
        # @param version [Integer] SFNT version
        # @return [String] Formatted version as escaped bytes
        def format_sfnt_version(version)
          bytes = [version].pack("N").bytes
          "\\x#{bytes.map { |b| b.to_s(16).rjust(2, '0') }.join('\\x')}"
        end
      end
    end
  end
end
