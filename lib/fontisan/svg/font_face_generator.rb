# frozen_string_literal: true

module Fontisan
  module Svg
    # Generates SVG font-face element with font metadata
    #
    # [`FontFaceGenerator`](lib/fontisan/svg/font_face_generator.rb) extracts
    # font metadata from font tables and formats it as SVG font-face attributes.
    # This includes font family, style, weight, units-per-em, ascent, descent,
    # and other font-level metrics.
    #
    # Responsibilities:
    # - Extract font metadata from name, head, hhea, OS/2 tables
    # - Format metadata as SVG font-face attributes
    # - Handle missing or invalid metadata gracefully
    # - Provide sensible defaults
    #
    # This class separates metadata extraction from XML generation, following
    # separation of concerns principle.
    #
    # @example Generate font-face attributes
    #   generator = FontFaceGenerator.new(font)
    #   attributes = generator.generate_attributes
    #   # => { font_family: "Arial", units_per_em: 1000, ... }
    class FontFaceGenerator
      # @return [TrueTypeFont, OpenTypeFont] Font instance
      attr_reader :font

      # Initialize generator with font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to extract metadata from
      # @raise [ArgumentError] If font is nil or invalid
      def initialize(font)
        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:table)
          raise ArgumentError, "Font must respond to :table method"
        end

        @font = font
      end

      # Generate font-face attributes
      #
      # Returns a hash of font-face attributes suitable for SVG rendering.
      # All values are properly formatted for SVG.
      #
      # @return [Hash<Symbol, Object>] Font-face attributes
      def generate_attributes
        {
          font_family: extract_font_family,
          font_weight: extract_font_weight,
          font_style: extract_font_style,
          units_per_em: extract_units_per_em,
          ascent: extract_ascent,
          descent: extract_descent,
          x_height: extract_x_height,
          cap_height: extract_cap_height,
          bbox: extract_bbox,
          underline_position: extract_underline_position,
          underline_thickness: extract_underline_thickness,
        }
      end

      # Generate font-face element as XML string
      #
      # @param indent [String] Indentation string (default: "    ")
      # @return [String] XML font-face element
      def generate_xml(indent: "    ")
        attrs = generate_attributes

        # Build attribute string
        attr_parts = []
        attr_parts << "font-family=\"#{escape_xml(attrs[:font_family])}\""
        attr_parts << "units-per-em=\"#{attrs[:units_per_em]}\""
        attr_parts << "ascent=\"#{attrs[:ascent]}\""
        attr_parts << "descent=\"#{attrs[:descent]}\""

        # Optional attributes
        attr_parts << "font-weight=\"#{attrs[:font_weight]}\"" if attrs[:font_weight]
        attr_parts << "font-style=\"#{attrs[:font_style]}\"" if attrs[:font_style]
        attr_parts << "x-height=\"#{attrs[:x_height]}\"" if attrs[:x_height]
        attr_parts << "cap-height=\"#{attrs[:cap_height]}\"" if attrs[:cap_height]
        attr_parts << "bbox=\"#{attrs[:bbox]}\"" if attrs[:bbox]
        attr_parts << "underline-position=\"#{attrs[:underline_position]}\"" if attrs[:underline_position]
        attr_parts << "underline-thickness=\"#{attrs[:underline_thickness]}\"" if attrs[:underline_thickness]

        "#{indent}<font-face #{attr_parts.join(' ')}/>"
      end

      private

      # Extract font family name from name table
      #
      # @return [String] Font family name
      def extract_font_family
        name_table = font.table("name")
        return "Unknown" unless name_table

        # Try to get font family name (name ID 1)
        family_name = name_table.font_family.first
        return family_name if family_name && !family_name.empty?

        # Fallback to full font name (name ID 4)
        full_name = name_table.font_name.first
        return full_name if full_name && !full_name.empty?

        "Unknown"
      rescue StandardError
        "Unknown"
      end

      # Extract font weight from OS/2 table
      #
      # @return [Integer, nil] Font weight (100-900) or nil
      def extract_font_weight
        os2 = font.table("OS/2")
        return nil unless os2

        weight = os2.weight_class
        return nil unless weight&.positive?

        weight
      rescue StandardError
        nil
      end

      # Extract font style from OS/2 or name table
      #
      # @return [String, nil] Font style ("normal", "italic", "oblique") or nil
      def extract_font_style
        os2 = font.table("OS/2")
        if os2
          # Check italic bit in fsSelection
          fs_selection = os2.fs_selection
          return "italic" if fs_selection && (fs_selection & 0x01) != 0
        end

        # Check name table for style
        name_table = font.table("name")
        if name_table
          subfamily = name_table.font_subfamily.first
          return "italic" if subfamily&.match?(/italic/i)
          return "oblique" if subfamily&.match?(/oblique/i)
        end

        "normal"
      rescue StandardError
        "normal"
      end

      # Extract units per em from head table
      #
      # @return [Integer] Units per em (default: 1000)
      def extract_units_per_em
        head = font.table("head")
        return 1000 unless head

        units = head.units_per_em
        return 1000 unless units

        units.to_i
      end

      # Extract ascent from hhea table
      #
      # @return [Integer] Font ascent
      def extract_ascent
        hhea = font.table("hhea")
        return 800 unless hhea

        ascent = hhea.ascent
        return 800 unless ascent

        ascent.to_i
      end

      # Extract descent from hhea table
      #
      # @return [Integer] Font descent (typically negative)
      def extract_descent
        hhea = font.table("hhea")
        return -200 unless hhea

        descent = hhea.descent
        return -200 unless descent

        descent.to_i
      end

      # Extract x-height from OS/2 table
      #
      # @return [Integer, nil] X-height or nil
      def extract_x_height
        os2 = font.table("OS/2")
        return nil unless os2

        x_height = os2.x_height
        return nil unless x_height&.positive?

        x_height
      rescue StandardError
        nil
      end

      # Extract cap-height from OS/2 table
      #
      # @return [Integer, nil] Cap height or nil
      def extract_cap_height
        os2 = font.table("OS/2")
        return nil unless os2

        cap_height = os2.cap_height
        return nil unless cap_height&.positive?

        cap_height
      rescue StandardError
        nil
      end

      # Extract bounding box from head table
      #
      # @return [String, nil] Bounding box "xMin yMin xMax yMax" or nil
      def extract_bbox
        head = font.table("head")
        return nil unless head

        # SVG font bbox format: "xMin yMin xMax yMax"
        "#{head.x_min} #{head.y_min} #{head.x_max} #{head.y_max}"
      rescue StandardError
        nil
      end

      # Extract underline position from post table
      #
      # @return [Integer, nil] Underline position or nil
      def extract_underline_position
        post = font.table("post")
        return nil unless post

        position = post.underline_position
        return nil unless position

        position
      rescue StandardError
        nil
      end

      # Extract underline thickness from post table
      #
      # @return [Integer, nil] Underline thickness or nil
      def extract_underline_thickness
        post = font.table("post")
        return nil unless post

        thickness = post.underline_thickness
        return nil unless thickness&.positive?

        thickness
      rescue StandardError
        nil
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
