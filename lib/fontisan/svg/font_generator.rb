# frozen_string_literal: true

require_relative "font_face_generator"
require_relative "glyph_generator"
require_relative "view_box_calculator"

module Fontisan
  module Svg
    # Generates complete SVG font XML structure
    #
    # [`FontGenerator`](lib/fontisan/svg/font_generator.rb) orchestrates all
    # SVG font generation components to produce a complete SVG font document.
    # It coordinates FontFaceGenerator, GlyphGenerator, and ViewBoxCalculator
    # to build valid SVG font XML.
    #
    # Responsibilities:
    # - Generate complete SVG font XML structure
    # - Coordinate sub-generators (font-face, glyphs)
    # - Create proper XML namespaces and structure
    # - Handle font ID and default advance width
    # - Format XML with proper indentation
    #
    # This is the main orchestrator for SVG font generation, following the
    # single responsibility principle by delegating specific tasks to
    # specialized generators.
    #
    # @example Generate complete SVG font
    #   generator = FontGenerator.new(font, glyph_data)
    #   svg_xml = generator.generate
    #   File.write("font.svg", svg_xml)
    class FontGenerator
      # @return [TrueTypeFont, OpenTypeFont] Font instance
      attr_reader :font

      # @return [Hash] Glyph data map (glyph_id => {outline, unicode, name, advance})
      attr_reader :glyph_data

      # @return [Hash] Generation options
      attr_reader :options

      # Initialize generator
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to generate SVG for
      # @param glyph_data [Hash] Glyph data map
      # @param options [Hash] Generation options
      # @option options [Boolean] :pretty_print Pretty print XML (default: true)
      # @option options [String] :font_id Font ID for SVG (default: from font name)
      # @option options [Integer] :default_advance Default advance width (default: 500)
      # @raise [ArgumentError] If font or glyph_data is invalid
      def initialize(font, glyph_data, options = {})
        validate_parameters!(font, glyph_data)

        @font = font
        @glyph_data = glyph_data
        @options = default_options.merge(options)
      end

      # Generate complete SVG font XML
      #
      # Creates a complete SVG document with embedded font definition.
      # The structure follows SVG 1.1 font specification.
      #
      # @return [String] Complete SVG font XML
      def generate
        parts = []
        parts << xml_declaration
        parts << svg_opening_tag
        parts << "  <defs>"
        parts << generate_font_element
        parts << "  </defs>"
        parts << svg_closing_tag

        parts.join("\n")
      end

      private

      # Validate initialization parameters
      #
      # @param font [Object] Font to validate
      # @param glyph_data [Object] Glyph data to validate
      # @raise [ArgumentError] If validation fails
      def validate_parameters!(font, glyph_data)
        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:table)
          raise ArgumentError, "Font must respond to :table method"
        end

        unless glyph_data.is_a?(Hash)
          raise ArgumentError,
                "glyph_data must be a Hash, got: #{glyph_data.class}"
        end
      end

      # Get default options
      #
      # @return [Hash] Default options
      def default_options
        {
          pretty_print: true,
          font_id: nil,
          default_advance: 500,
        }
      end

      # Generate XML declaration
      #
      # @return [String] XML declaration
      def xml_declaration
        '<?xml version="1.0" encoding="UTF-8"?>'
      end

      # Generate SVG opening tag
      #
      # @return [String] SVG opening tag with namespaces
      def svg_opening_tag
        '<svg xmlns="http://www.w3.org/2000/svg">'
      end

      # Generate SVG closing tag
      #
      # @return [String] SVG closing tag
      def svg_closing_tag
        "</svg>"
      end

      # Generate font element with all glyphs
      #
      # @return [String] Complete font element
      def generate_font_element
        parts = []

        # Font opening tag
        font_id = options[:font_id] || extract_font_id
        default_advance = options[:default_advance]
        parts << "    <font id=\"#{escape_xml(font_id)}\" horiz-adv-x=\"#{default_advance}\">"

        # Font-face element
        parts << generate_font_face

        # Missing glyph
        parts << generate_missing_glyph

        # All glyphs
        parts << generate_glyphs

        # Font closing tag
        parts << "    </font>"

        parts.join("\n")
      end

      # Generate font-face element
      #
      # @return [String] Font-face XML
      def generate_font_face
        face_generator = FontFaceGenerator.new(font)
        face_generator.generate_xml(indent: "      ")
      end

      # Generate missing-glyph element
      #
      # @return [String] Missing-glyph XML
      def generate_missing_glyph
        calculator = create_calculator
        glyph_generator = GlyphGenerator.new(calculator)
        glyph_generator.generate_missing_glyph(
          advance_width: options[:default_advance],
          indent: "      ",
        )
      end

      # Generate all glyph elements
      #
      # @return [String] All glyph XML elements
      def generate_glyphs
        calculator = create_calculator
        glyph_generator = GlyphGenerator.new(calculator)

        glyph_xmls = glyph_data.map do |_glyph_id, data|
          next unless data[:outline]

          glyph_generator.generate_glyph_xml(
            data[:outline],
            unicode: data[:unicode],
            glyph_name: data[:name],
            advance_width: data[:advance],
            indent: "      ",
          )
        end

        glyph_xmls.compact.join("\n")
      end

      # Create ViewBoxCalculator
      #
      # @return [ViewBoxCalculator] Calculator instance
      def create_calculator
        head = font.table("head")
        hhea = font.table("hhea")

        units_per_em = head&.units_per_em&.to_i || 1000
        ascent = hhea&.ascent&.to_i || 800
        descent = hhea&.descent&.to_i || -200

        ViewBoxCalculator.new(
          units_per_em: units_per_em,
          ascent: ascent,
          descent: descent,
        )
      end

      # Extract font ID from font name
      #
      # @return [String] Font ID
      def extract_font_id
        name_table = font.table("name")
        return "Font" unless name_table

        # Try PostScript name first (name ID 6)
        ps_name = name_table.postscript_name.first
        return sanitize_font_id(ps_name) if ps_name && !ps_name.empty?

        # Fallback to font family (name ID 1)
        family_name = name_table.font_family.first
        return sanitize_font_id(family_name) if family_name && !family_name.empty?

        "Font"
      rescue StandardError
        "Font"
      end

      # Sanitize font ID for XML
      #
      # @param name [String] Font name
      # @return [String] Sanitized ID
      def sanitize_font_id(name)
        # Remove invalid XML ID characters
        # XML IDs must start with letter or underscore
        # Can contain letters, digits, hyphens, underscores, periods
        sanitized = name.gsub(/[^a-zA-Z0-9\-_.]/, "_")

        # Ensure starts with letter or underscore
        sanitized = "_#{sanitized}" if /\A[^a-zA-Z_]/.match?(sanitized)

        sanitized
      end

      # Escape XML special characters
      #
      # @param text [String] Text to escape
      # @return [String] Escaped text
      def escape_xml(text)
        text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\"", "&quot;")
          .gsub("'", "&apos;")
      end
    end
  end
end
