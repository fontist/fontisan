# frozen_string_literal: true

module Fontisan
  module Converters
    # SVG font generator conversion strategy
    #
    # [`SvgGenerator`](lib/fontisan/converters/svg_generator.rb) implements
    # the ConversionStrategy interface to convert TTF or OTF fonts to SVG
    # font format for web use, inspection, or conversion purposes.
    #
    # SVG font generation process:
    # 1. Extract font metadata from tables
    # 2. Extract glyph outlines using OutlineExtractor
    # 3. Get unicode mappings from cmap table
    # 4. Get advance widths from hmtx table
    # 5. Build glyph data map
    # 6. Generate complete SVG XML using FontGenerator
    #
    # Note: SVG fonts are deprecated in favor of WOFF/WOFF2 but remain useful
    # for fallback, conversion workflows, and font inspection.
    #
    # @example Convert TTF to SVG
    #   generator = SvgGenerator.new
    #   svg_xml = generator.convert(font)
    #   File.write('font.svg', svg_xml[:svg_xml])
    class SvgGenerator
      include ConversionStrategy

      # Convert font to SVG format
      #
      # Returns a hash with :svg_xml key containing complete SVG font XML.
      # This follows the same pattern as Woff2Encoder.
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Conversion options
      # @option options [Boolean] :pretty_print Pretty print XML (default: true)
      # @option options [Array<Integer>] :glyph_ids Specific glyph IDs to include (default: all)
      # @option options [Integer] :max_glyphs Maximum glyphs to include (default: all)
      # @return [Hash] Hash with :svg_xml key containing SVG XML string
      # @raise [Error] If conversion fails
      def convert(font, options = {})
        validate(font, :svg)

        # Extract glyph data
        glyph_data = extract_glyph_data(font, options)

        # Generate SVG XML
        generator = Svg::FontGenerator.new(font, glyph_data, options)
        svg_xml = generator.generate

        # Return in special format for ConvertCommand to handle
        { svg_xml: svg_xml }
      end

      # Get list of supported conversions
      #
      # @return [Array<Array<Symbol>>] Supported conversion pairs
      def supported_conversions
        [
          %i[ttf svg],
          %i[otf svg],
        ]
      end

      # Validate that conversion is possible
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param target_format [Symbol] Target format
      # @return [Boolean] True if valid
      # @raise [Error] If conversion is not possible
      def validate(font, target_format)
        unless target_format == :svg
          raise Fontisan::Error,
                "SvgGenerator only supports conversion to svg, " \
                "got: #{target_format}"
        end

        # Verify font has required tables
        required_tables = %w[head hhea maxp cmap]
        required_tables.each do |tag|
          unless font.table(tag)
            raise Fontisan::Error,
                  "Font is missing required table: #{tag}"
          end
        end

        # Verify font has either glyf or CFF table
        unless font.has_table?("glyf") || font.has_table?("CFF ") || font.has_table?("CFF2")
          raise Fontisan::Error,
                "Font must have either glyf or CFF/CFF2 table"
        end

        true
      end

      private

      # Generate SVG for a color glyph from COLR/CPAL tables
      #
      # @param glyph_id [Integer] Glyph ID
      # @param colr_table [Tables::Colr] COLR table
      # @param cpal_table [Tables::Cpal] CPAL table
      # @param extractor [OutlineExtractor] Outline extractor for layer glyphs
      # @param palette_index [Integer] Palette index to use (default: 0)
      # @return [String, nil] SVG path data with color layers, or nil if not color glyph
      def generate_color_glyph(glyph_id, colr_table, cpal_table, extractor,
palette_index: 0)
        # Get layers for this glyph
        layers = colr_table.layers_for_glyph(glyph_id)
        return nil if layers.empty?

        # Get palette colors
        palette = cpal_table.palette(palette_index)
        return nil unless palette

        # Generate SVG for each layer
        svg_paths = []
        layers.each do |layer|
          # Get outline for layer glyph
          outline = extractor.extract(layer.glyph_id)
          next unless outline

          # Get color for this layer
          color = if layer.uses_foreground_color?
                    "currentColor" # Use CSS currentColor for foreground
                  else
                    palette[layer.palette_index] || "#000000FF"
                  end

          # Convert outline to SVG path
          path_data = outline.to_svg_path
          next if path_data.empty?

          # Create colored path element
          svg_paths << %(<path d="#{path_data}" fill="#{color}" />)
        end

        svg_paths.empty? ? nil : svg_paths.join("\n")
      rescue StandardError => e
        warn "Failed to generate color glyph #{glyph_id}: #{e.message}"
        nil
      end

      # Extract glyph data from font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Extraction options
      # @return [Hash] Glyph data map (glyph_id => {outline, codepoints, name, advance})
      def extract_glyph_data(font, options = {})
        extractor = OutlineExtractor.new(font)
        cmap = font.table("cmap")
        hmtx = font.table("hmtx")
        post = font.table("post")
        maxp = font.table("maxp")

        glyph_data = {}
        num_glyphs = maxp&.num_glyphs || 0
        max_glyphs = options[:max_glyphs] || num_glyphs

        gid_to_codepoints = build_glyph_to_codepoints(cmap)
        glyph_names = post&.glyph_names || []

        glyph_ids = options[:glyph_ids] || (0...num_glyphs).to_a
        glyph_ids = glyph_ids.take(max_glyphs) if max_glyphs

        glyph_ids.each do |glyph_id|
          next if glyph_id >= num_glyphs

          glyph_data[glyph_id] = {
            outline: extractor.extract(glyph_id),
            codepoints: gid_to_codepoints[glyph_id] || [],
            name: glyph_name_for(glyph_names, glyph_id),
            advance: extract_advance_width(hmtx, glyph_id),
          }
        rescue StandardError => e
          warn "Failed to extract glyph #{glyph_id}: #{e.message}"
          next
        end

        glyph_data
      end

      # Build reverse cmap: glyph_id => [codepoint, ...].
      #
      # A glyph can be referenced by multiple codepoints (e.g. space
      # and non-breaking space might share a glyph). Uses
      # +cmap.unicode_mappings+ directly — that is the canonical
      # {codepoint => gid} hash.
      #
      # @param cmap [Tables::Cmap, nil]
      # @return [Hash<Integer, Array<Integer>>]
      def build_glyph_to_codepoints(cmap)
        return {} unless cmap

        cmap.unicode_mappings.each_with_object(Hash.new do |h, k|
          h[k] = []
        end) do |(cp, gid), h|
          h[gid] << cp
        end
      rescue StandardError => e
        warn "Failed to build glyph to codepoints map: #{e.message}"
        {}
      end

      # Look up glyph name from the post table's per-gid name array.
      #
      # Falls back to +"gidN"+ when the post table has no name for the
      # given gid (post version 3.0 fonts omit per-glyph names, and
      # version 2.0 may have gaps). Always returns a non-nil string so
      # the SVG <glyph> element carries a useful glyph-name attribute.
      #
      # @param glyph_names [Array<String>] post.glyph_names
      # @param glyph_id [Integer]
      # @return [String]
      def glyph_name_for(glyph_names, glyph_id)
        glyph_names[glyph_id] || "gid#{glyph_id}"
      end

      # Extract advance width for glyph
      #
      # @param hmtx [Tables::Hmtx, nil] Hmtx table
      # @param glyph_id [Integer] Glyph ID
      # @return [Integer] Advance width
      def extract_advance_width(hmtx, glyph_id)
        return 0 unless hmtx

        advance = hmtx.advance_width_for(glyph_id)
        return 0 unless advance

        advance
      rescue StandardError
        0
      end
    end
  end
end
