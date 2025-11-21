# frozen_string_literal: true

require_relative "conversion_strategy"
require_relative "../outline_extractor"

module Fontisan
  module Converters
    # Strategy for converting between TTF and OTF outline formats
    #
    # [`OutlineConverter`](lib/fontisan/converters/outline_converter.rb)
    # handles conversion between TrueType (glyf/loca) and CFF outline formats.
    # This involves:
    # - Extracting glyph outlines from source format
    # - Converting between quadratic (TrueType) and cubic (CFF) Bézier curves
    # - Building target format tables
    # - Copying and updating non-outline tables
    #
    # **Conversion Details:**
    #
    # TTF → OTF:
    # - Convert TrueType quadratic curves to CFF cubic curves
    # - Build CFF table with CharStrings INDEX
    # - Remove glyf/loca tables
    # - Update head table (glyphDataFormat, checksums)
    #
    # OTF → TTF:
    # - Convert CFF cubic curves to TrueType quadratic curves
    # - Build glyf and loca tables
    # - Remove CFF table
    # - Update head table
    #
    # **Note:** Full CFF table generation (with complete DICT structures,
    # CharStrings encoding, etc.) and glyf table generation requires
    # substantial additional implementation. This class provides the
    # architectural foundation and core conversion logic.
    #
    # @example Converting TTF to OTF
    #   converter = Fontisan::Converters::OutlineConverter.new
    #   tables = converter.convert(ttf_font, target_format: :otf)
    #   binary = FontWriter.write_font(tables, sfnt_version: 0x4F54544F)
    class OutlineConverter
      include ConversionStrategy

      # Convert font between TTF and OTF formats
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Conversion options
      # @option options [Symbol] :target_format Target format (:ttf or :otf)
      # @return [Hash<String, String>] Map of table tags to binary data
      # @raise [NotImplementedError] Full implementation requires additional work
      def convert(font, options = {})
        target_format = options[:target_format] ||
          detect_target_format(font)
        validate(font, target_format)

        source_format = detect_format(font)

        case [source_format, target_format]
        when %i[ttf otf]
          convert_ttf_to_otf(font)
        when %i[otf ttf]
          convert_otf_to_ttf(font)
        else
          raise Fontisan::Error,
                "Unsupported conversion: #{source_format} → #{target_format}"
        end
      end

      # Get supported conversions
      #
      # @return [Array<Array<Symbol>>] Supported conversion pairs
      def supported_conversions
        [
          %i[ttf otf],
          %i[otf ttf],
        ]
      end

      # Validate font for conversion
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param target_format [Symbol] Target format
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If font is invalid
      # @raise [Error] If conversion is not supported
      def validate(font, target_format)
        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:tables)
          raise ArgumentError, "Font must respond to :tables"
        end

        unless font.respond_to?(:table)
          raise ArgumentError, "Font must respond to :table"
        end

        source_format = detect_format(font)
        unless supports?(source_format, target_format)
          raise Fontisan::Error,
                "Conversion #{source_format} → #{target_format} not supported"
        end

        # Check that source font has required tables
        validate_source_tables(font, source_format)

        true
      end

      private

      # Convert TrueType font to OpenType/CFF
      #
      # @param font [TrueTypeFont] Source font
      # @return [Hash<String, String>] Target tables
      # @raise [NotImplementedError] Full CFF generation needs more work
      def convert_ttf_to_otf(font)
        # NOTE: Full CFF table generation requires substantial additional work.
        # This includes:
        # - Building complete CFF structure (Header, Name INDEX, Top DICT, etc.)
        # - Encoding CharStrings with Type 2 operators
        # - Creating Charset and Encoding structures
        # - Building Private DICT with proper metrics
        # - Handling subroutines for compression
        #
        # For Phase 1, this is marked as needing additional implementation.
        raise NotImplementedError,
              "TTF to OTF conversion requires full CFF table generation, " \
              "which needs additional implementation beyond Phase 1 scope. " \
              "This includes building CFF INDEX structures, encoding " \
              "CharStrings, and creating DICT entries."
      end

      # Convert OpenType/CFF font to TrueType
      #
      # @param font [OpenTypeFont] Source font
      # @return [Hash<String, String>] Target tables
      # @raise [NotImplementedError] Full glyf/loca generation needs more work
      def convert_otf_to_ttf(font)
        # NOTE: Full glyf/loca table generation requires substantial work.
        # This includes:
        # - Converting CFF cubic curves to TrueType quadratic curves
        # - Building glyf table with Simple/Compound glyph structures
        # - Building loca table with proper offset calculation
        # - Handling curve conversion algorithms
        # - Managing bounding boxes and metrics
        #
        # For Phase 1, this is marked as needing additional implementation.
        raise NotImplementedError,
              "OTF to TTF conversion requires full glyf/loca table generation, " \
              "which needs additional implementation beyond Phase 1 scope. " \
              "This includes cubic-to-quadratic curve conversion and proper " \
              "TrueType glyph structure encoding."
      end

      # Copy non-outline tables from source to target
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param exclude_tags [Array<String>] Tags to exclude
      # @return [Hash<String, String>] Copied tables
      def copy_tables(font, exclude_tags = [])
        tables = {}

        font.table_data.each do |tag, data|
          next if exclude_tags.include?(tag)

          tables[tag] = data if data
        end

        tables
      end

      # Update head table for target format
      #
      # @param head_data [String] Source head table data
      # @param target_format [Symbol] Target format
      # @return [String] Updated head table data
      def update_head_table(head_data, target_format)
        # Parse head table
        Tables::Head.read(head_data)

        # Update glyphDataFormat based on target
        # 0 for CFF (in OpenType fonts)
        # Short loca format uses 1, long uses 0
        case target_format
        when :otf
          # CFF fonts use glyphDataFormat = 0
          # But we need to reconstruct the entire head table
          # This is a simplified placeholder
        when :ttf
          # TrueType fonts may use 0 or 1 depending on loca format
        end
        head_data
      end

      # Detect font format from tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to detect
      # @return [Symbol] Format (:ttf or :otf)
      # @raise [Error] If format cannot be detected
      def detect_format(font)
        # Check for CFF/CFF2 tables (OpenType/CFF)
        if font.has_table?("CFF ") || font.has_table?("CFF2")
          :otf
        # Check for glyf table (TrueType)
        elsif font.has_table?("glyf")
          :ttf
        else
          raise Fontisan::Error,
                "Cannot detect font format: missing both CFF and glyf tables"
        end
      end

      # Detect target format as opposite of source
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @return [Symbol] Target format
      def detect_target_format(font)
        source = detect_format(font)
        source == :ttf ? :otf : :ttf
      end

      # Validate source font has required tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param format [Symbol] Font format
      # @raise [Error] If required tables are missing
      def validate_source_tables(font, format)
        case format
        when :ttf
          unless font.has_table?("glyf") && font.has_table?("loca") &&
              font.table("glyf") && font.table("loca")
            raise Fontisan::MissingTableError,
                  "TrueType font missing required glyf or loca table"
          end
        when :otf
          unless (font.has_table?("CFF ") && font.table("CFF ")) ||
              (font.has_table?("CFF2") && font.table("CFF2"))
            raise Fontisan::MissingTableError,
                  "OpenType font missing required CFF table"
          end
        end

        # Common required tables
        %w[head hhea maxp].each do |tag|
          unless font.table(tag)
            raise Fontisan::MissingTableError,
                  "Font missing required #{tag} table"
          end
        end
      end

      # Convert quadratic Bézier curve to cubic Bézier curve
      #
      # TrueType uses quadratic curves (one control point), CFF uses
      # cubic curves (two control points). The conversion preserves the curve.
      #
      # Quadratic: P(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂
      # Cubic: P(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃
      #
      # Conversion formula:
      # CP1 = P0 + 2/3 * (P1 - P0)
      # CP2 = P2 + 2/3 * (P1 - P2)
      #
      # @param p0 [Hash] Start point {x:, y:}
      # @param p1 [Hash] Quadratic control point {x:, y:}
      # @param p2 [Hash] End point {x:, y:}
      # @return [Array<Hash>] [cp1, cp2] Control points for cubic curve
      def quadratic_to_cubic(p0, p1, p2)
        # Calculate cubic control points
        cp1_x = p0[:x] + (2.0 / 3.0) * (p1[:x] - p0[:x])
        cp1_y = p0[:y] + (2.0 / 3.0) * (p1[:y] - p0[:y])

        cp2_x = p2[:x] + (2.0 / 3.0) * (p1[:x] - p2[:x])
        cp2_y = p2[:y] + (2.0 / 3.0) * (p1[:y] - p2[:y])

        [
          { x: cp1_x.round, y: cp1_y.round },
          { x: cp2_x.round, y: cp2_y.round },
        ]
      end

      # Convert cubic Bézier curve to quadratic Bézier curve
      #
      # This is an approximation since cubic curves have more degrees of
      # freedom. For best results, multiple quadratic curves may be needed.
      #
      # Simple approximation: Use midpoint of cubic control points
      # Better approach would use curve subdivision for accuracy
      #
      # @param p0 [Hash] Start point {x:, y:}
      # @param cp1 [Hash] First cubic control point {x:, y:}
      # @param cp2 [Hash] Second cubic control point {x:, y:}
      # @param p3 [Hash] End point {x:, y:}
      # @return [Hash] Quadratic control point {x:, y:}
      def cubic_to_quadratic(_p0, cp1, cp2, _p3)
        # Simple approximation: midpoint of cubic control points
        # This may not perfectly preserve the curve shape
        control_x = ((cp1[:x] + cp2[:x]) / 2.0).round
        control_y = ((cp1[:y] + cp2[:y]) / 2.0).round

        { x: control_x, y: control_y }
      end
    end
  end
end
