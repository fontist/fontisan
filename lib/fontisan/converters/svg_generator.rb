# frozen_string_literal: true

require_relative "conversion_strategy"
require_relative "../outline_extractor"
require_relative "../svg/font_generator"

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

      # Extract glyph data from font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Extraction options
      # @return [Hash] Glyph data map (glyph_id => {outline, unicode, name, advance})
      def extract_glyph_data(font, options = {})
        extractor = OutlineExtractor.new(font)
        cmap = font.table("cmap")
        hmtx = font.table("hmtx")
        post = font.table("post")
        maxp = font.table("maxp")

        glyph_data = {}
        num_glyphs = maxp&.num_glyphs || 0
        max_glyphs = options[:max_glyphs] || num_glyphs

        # Get unicode mappings
        unicode_map = build_unicode_map(cmap)

        # Extract specified or all glyphs
        glyph_ids = options[:glyph_ids] || (0...num_glyphs).to_a
        glyph_ids = glyph_ids.take(max_glyphs) if max_glyphs

        glyph_ids.each do |glyph_id|
          next if glyph_id >= num_glyphs

          # Extract outline
          outline = extractor.extract(glyph_id)

          # Get advance width
          advance = extract_advance_width(hmtx, glyph_id)

          # Get unicode character
          unicode = unicode_map[glyph_id]

          # Get glyph name
          glyph_name = extract_glyph_name(post, glyph_id)

          glyph_data[glyph_id] = {
            outline: outline,
            unicode: unicode,
            name: glyph_name,
            advance: advance,
          }
        rescue StandardError => e
          warn "Failed to extract glyph #{glyph_id}: #{e.message}"
          next
        end

        glyph_data
      end

      # Build unicode to glyph ID map from cmap table
      #
      # @param cmap [Tables::Cmap, nil] Cmap table
      # @return [Hash<Integer, String>] Map of glyph_id to unicode character
      def build_unicode_map(cmap)
        return {} unless cmap

        unicode_map = {}

        # Get best cmap subtable (prefer Unicode BMP or full)
        subtable = find_best_cmap_subtable(cmap)
        return {} unless subtable

        # Build reverse map: glyph_id => unicode
        subtable.each do |code_point, glyph_id|
          # Store first unicode for each glyph
          next if unicode_map[glyph_id]

          unicode_map[glyph_id] = [code_point].pack("U")
        rescue StandardError
          # Skip invalid code points
          next
        end

        unicode_map
      rescue StandardError => e
        warn "Failed to build unicode map: #{e.message}"
        {}
      end

      # Find best cmap subtable for unicode mapping
      #
      # @param cmap [Tables::Cmap] Cmap table
      # @return [Hash, nil] Subtable or nil
      def find_best_cmap_subtable(cmap)
        # Try Unicode BMP (platform 3, encoding 1) - Windows Unicode BMP
        subtable = cmap.subtable(3, 1)
        return subtable if subtable

        # Try Unicode full (platform 3, encoding 10) - Windows Unicode full
        subtable = cmap.subtable(3, 10)
        return subtable if subtable

        # Try Unicode (platform 0, encoding 3) - Unicode 2.0+ BMP
        subtable = cmap.subtable(0, 3)
        return subtable if subtable

        # Try Unicode (platform 0, encoding 4) - Unicode 2.0+ full
        subtable = cmap.subtable(0, 4)
        return subtable if subtable

        # Fallback to any available subtable
        cmap.subtables.first
      rescue StandardError
        nil
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

      # Extract glyph name from post table
      #
      # @param post [Tables::Post, nil] Post table
      # @param glyph_id [Integer] Glyph ID
      # @return [String, nil] Glyph name or nil
      def extract_glyph_name(post, glyph_id)
        return nil unless post

        name = post.glyph_name_for(glyph_id)
        return nil if name.nil? || name.empty?

        name
      rescue StandardError
        nil
      end
    end
  end
end
