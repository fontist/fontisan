# frozen_string_literal: true

require_relative "upm_scaler"
require_relative "encodings"
require_relative "agl"

module Fontisan
  module Type1
    # AFM (Adobe Font Metrics) file generator
    #
    # [`AFMGenerator`](lib/fontisan/type1/afm_generator.rb) generates Adobe Font Metrics
    # files from TTF/OTF fonts.
    #
    # AFM files include:
    # - Character widths
    # - Kerning pairs
    # - Character bounding boxes
    # - Font metadata (name, version, copyright, etc.)
    #
    # @example Generate AFM from TTF
    #   font = Fontisan::FontLoader.load("font.ttf")
    #   afm = Fontisan::Type1::AFMGenerator.generate(font)
    #   File.write("font.afm", afm)
    #
    # @example Generate AFM with 1000 UPM scaling
    #   afm = Fontisan::Type1::AFMGenerator.generate(font, upm_scale: 1000)
    #
    # @example Generate AFM with Unicode encoding
    #   afm = Fontisan::Type1::AFMGenerator.generate(font, encoding: Fontisan::Type1::Encodings::Unicode)
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5004.AFM_Spec.pdf
    class AFMGenerator
      class << self
        # Generate AFM content from a font
        #
        # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] The font to generate AFM from
        # @param options [Hash] Generation options
        # @option options [Integer, :native] :upm_scale Target UPM (1000 for Type 1, :native for no scaling)
        # @option options [Class] :encoding Encoding class (default: AdobeStandard)
        # @return [String] AFM file content
        def generate(font, options = {})
          new(font, options).generate_afm
        end

        # Generate AFM file from a font and write to file
        #
        # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] The font to generate AFM from
        # @param path [String] Path to write AFM file
        # @param options [Hash] Generation options
        # @return [void
        def generate_to_file(font, path, options = {})
          afm_content = generate(font, options)
          File.write(path, afm_content, encoding: "ISO-8859-1")
        end

        # Get Adobe glyph name from Unicode codepoint
        #
        # @param codepoint [Integer] Unicode codepoint
        # @param encoding [Class] Encoding class to use (default: nil for direct AGL lookup)
        # @return [String] Adobe glyph name
        def adobe_glyph_name(codepoint, encoding: nil)
          if encoding
            encoding.glyph_name_for_code(codepoint)
          else
            AGL.glyph_name_for_unicode(codepoint)
          end
        end
      end

      # Initialize a new AFMGenerator
      #
      # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] The font to generate AFM from
      # @param options [Hash] Generation options
      def initialize(font, options = {})
        @font = font
        @metrics = MetricsCalculator.new(font)

        # Set up scaler
        upm_scale = options[:upm_scale] || 1000
        @scaler = if upm_scale == :native
                    UPMScaler.native(font)
                  else
                    UPMScaler.new(font, target_upm: upm_scale)
                  end

        # Set up encoding
        @encoding = options[:encoding] || Encodings::AdobeStandard
      end

      # Generate AFM content
      #
      # @return [String] AFM file content
      def generate_afm
        afm_lines = []

        # Header
        afm_lines << "StartFontMetrics 4.1"

        # Font metadata
        add_font_metadata(afm_lines)

        # Font bounding box
        add_font_bounding_box(afm_lines)

        # Character metrics
        add_character_metrics(afm_lines)

        # Kerning data
        add_kerning_data(afm_lines)

        # Footer
        afm_lines << "EndFontMetrics"

        afm_lines.join("\n")
      end

      private

      # Add font metadata to AFM
      #
      # @param afm_lines [Array<String>] AFM lines array
      def add_font_metadata(afm_lines)
        # Font name
        font_name = @font.post_script_name
        afm_lines << "FontName #{font_name}" if font_name

        # Full name
        full_name = @font.full_name
        afm_lines << "FullName #{full_name}" if full_name

        # Family name
        family_name = @font.family_name
        afm_lines << "FamilyName #{family_name}" if family_name

        # Weight
        weight = extract_weight
        afm_lines << "Weight #{weight}" if weight

        # Italic angle
        italic_angle = extract_italic_angle
        afm_lines << "ItalicAngle #{italic_angle}" if italic_angle

        # IsFixedPitch
        is_fixed_pitch = is_monospace? ? "true" : "false"
        afm_lines << "IsFixedPitch #{is_fixed_pitch}"

        # Character direction
        afm_lines << "CharacterDirection 0"

        # Version
        version = extract_version
        afm_lines << "Version #{version}" if version

        # Notice (copyright)
        notice = extract_copyright
        afm_lines << "Notice #{notice}" if notice

        # Encoding scheme
        afm_lines << "EncodingScheme AdobeStandardEncoding"

        # Mapping scheme
        afm_lines << "MappingScheme 0"

        # Ascender
        ascender = @metrics.ascent
        afm_lines << "Ascender #{ascender}" if ascender

        # Descender
        descender = @metrics.descent
        afm_lines << "Descender #{descender}" if descender

        # Underline properties
        post = @font.table(Constants::POST_TAG)
        underline_position = post&.underline_position if post.respond_to?(:underline_position)
        afm_lines << "UnderlinePosition #{underline_position}" if underline_position

        underline_thickness = post&.underline_thickness if post.respond_to?(:underline_thickness)
        afm_lines << "UnderlineThickness #{underline_thickness}" if underline_thickness
      end

      # Add font bounding box to AFM
      #
      # @param afm_lines [Array<String>] AFM lines array
      def add_font_bounding_box(afm_lines)
        bbox = extract_font_bounding_box
        return unless bbox && bbox.length == 4

        # Scale bounding box
        scaled_bbox = @scaler.scale_bbox(bbox)
        afm_lines << "FontBBox #{scaled_bbox[0]} #{scaled_bbox[1]} #{scaled_bbox[2]} #{scaled_bbox[3]}"
      end

      # Add character metrics to AFM
      #
      # @param afm_lines [Array<String>] AFM lines array
      def add_character_metrics(afm_lines)
        # Get character mappings from cmap
        char_mappings = extract_character_mappings
        return if char_mappings.empty?

        afm_lines << "StartCharMetrics #{char_mappings.length}"

        char_mappings.each do |unicode, glyph_id|
          next unless unicode && unicode >= 32 && unicode <= 255

          # Get glyph name from encoding
          glyph_name = @encoding.glyph_name_for_code(unicode)
          glyph_name ||= AGL.glyph_name_for_unicode(unicode)
          next unless glyph_name

          # Get and scale width
          width = @metrics.glyph_width(glyph_id)
          next unless width

          scaled_width = @scaler.scale_width(width)

          # Get and scale bounding box if available
          bbox = extract_glyph_bounding_box(glyph_id)
          scaled_bbox = bbox ? @scaler.scale_bbox(bbox) : nil

          # Format: C code ; WX width ; N name ; B llx lly urx ury ;
          metric_line = "C #{unicode} ; WX #{scaled_width} ; N #{glyph_name}"
          if scaled_bbox && scaled_bbox.length == 4
            metric_line += " ; B #{scaled_bbox[0]} #{scaled_bbox[1]} #{scaled_bbox[2]} #{scaled_bbox[3]}"
          end
          afm_lines << metric_line
        end

        afm_lines << "EndCharMetrics"
      end

      # Add kerning data to AFM
      #
      # @param afm_lines [Array<String>] AFM lines array
      def add_kerning_data(afm_lines)
        kerning_pairs = extract_kerning_pairs
        return if kerning_pairs.empty?

        afm_lines << "StartKernData"
        afm_lines << "StartKernPairs #{kerning_pairs.length}"

        kerning_pairs.each do |left, right, adjustment|
          left_name = self.class.adobe_glyph_name(left)
          right_name = self.class.adobe_glyph_name(right)
          afm_lines << "KPX #{left_name} #{right_name} #{adjustment}"
        end

        afm_lines << "EndKernPairs"
        afm_lines << "EndKernData"
      end

      # Extract weight from OS/2 table
      #
      # @return [String] Weight
      def extract_weight
        os2 = @font.table(Constants::OS2_TAG)
        return "Regular" unless os2

        weight_class = if os2.respond_to?(:us_weight_class)
                         os2.us_weight_class
                       elsif os2.respond_to?(:weight_class)
                         os2.weight_class
                       end
        return "Regular" unless weight_class

        case weight_class
        when 100..200 then "Thin"
        when 200..300 then "ExtraLight"
        when 300..400 then "Light"
        when 400..500 then "Regular"
        when 500..600 then "Medium"
        when 600..700 then "SemiBold"
        when 700..800 then "Bold"
        when 800..900 then "ExtraBold"
        when 900..1000 then "Black"
        else "Regular"
        end
      end

      # Extract italic angle from post table
      #
      # @return [Float] Italic angle
      def extract_italic_angle
        post = @font.table(Constants::POST_TAG)
        return 0.0 unless post

        if post.respond_to?(:italic_angle)
          post.italic_angle
        else
          0.0
        end
      end

      # Check if font is monospace
      #
      # @return [Boolean] True if monospace
      def is_monospace?
        post = @font.table(Constants::POST_TAG)
        return false unless post

        if post.respond_to?(:is_fixed_pitch)
          post.is_fixed_pitch
        else
          false
        end
      end

      # Extract version from name table
      #
      # @return [String, nil] Version string
      def extract_version
        name_table = @font.table(Constants::NAME_TAG)
        return nil unless name_table

        if name_table.respond_to?(:version_string)
          name_table.version_string(1) || name_table.version_string(3)
        end
      end

      # Extract copyright from name table
      #
      # @return [String, nil] Copyright notice
      def extract_copyright
        name_table = @font.table(Constants::NAME_TAG)
        return nil unless name_table

        if name_table.respond_to?(:copyright)
          name_table.copyright(1) || name_table.copyright(3)
        end
      end

      # Extract character mappings from cmap table
      #
      # @return [Hash<Integer, Integer>] Unicode to glyph ID mappings
      def extract_character_mappings
        cmap = @font.table(Constants::CMAP_TAG)
        return {} unless cmap

        @extract_character_mappings ||= begin
          mappings = {}

          # Try to get Unicode mappings (most reliable method)
          if cmap.respond_to?(:unicode_mappings)
            mappings = cmap.unicode_mappings || {}
          elsif cmap.respond_to?(:unicode_bmp_mapping)
            mappings = cmap.unicode_bmp_mapping || {}
          elsif cmap.respond_to?(:subtables)
            # Look for Unicode BMP subtable
            unicode_subtable = cmap.subtables.find do |subtable|
              subtable.respond_to?(:platform_id) &&
                subtable.platform_id == 3 &&
                subtable.respond_to?(:encoding_id) &&
                subtable.encoding_id == 1
            end

            if unicode_subtable.respond_to?(:glyph_index_map)
              mappings = unicode_subtable.glyph_index_map
            end
          end

          mappings
        end
      end

      # Extract font bounding box
      #
      # @return [Array<Integer>, nil] Bounding box [llx, lly, urx, ury]
      def extract_font_bounding_box
        head = @font.table(Constants::HEAD_TAG)
        return nil unless head

        if head.respond_to?(:font_bounding_box)
          head.font_bounding_box
        elsif head.respond_to?(:x_min) && head.respond_to?(:y_min) &&
            head.respond_to?(:x_max) && head.respond_to?(:y_max)
          [head.x_min, head.y_min, head.x_max, head.y_max]
        end
      end

      # Extract glyph bounding box
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<Integer>, nil] Bounding box [llx, lly, urx, ury]
      def extract_glyph_bounding_box(glyph_id)
        return nil unless @font.truetype?

        glyf_table = @font.table(Constants::GLYF_TAG)
        return nil unless glyf_table

        loca_table = @font.table(Constants::LOCA_TAG)
        return nil unless loca_table

        head_table = @font.table(Constants::HEAD_TAG)
        return nil unless head_table

        # Ensure loca is parsed with context
        if loca_table.respond_to?(:parse_with_context) && !loca_table.parsed?
          maxp = @font.table(Constants::MAXP_TAG)
          if maxp
            loca_table.parse_with_context(head_table.index_to_loc_format,
                                          maxp.num_glyphs)
          end
        end

        if glyf_table.respond_to?(:glyph_for)
          glyph = glyf_table.glyph_for(glyph_id, loca_table, head_table)
          return nil unless glyph

          if glyph.respond_to?(:bounding_box)
            glyph.bounding_box
          elsif glyph.respond_to?(:x_min) && glyph.respond_to?(:y_min) &&
              glyph.respond_to?(:x_max) && glyph.respond_to?(:y_max)
            [glyph.x_min, glyph.y_min, glyph.x_max, glyph.y_max]
          end
        end
      end

      # Extract kerning pairs from GPOS table
      #
      # @return [Array<Array>] Array of [left_unicode, right_unicode, adjustment]
      def extract_kerning_pairs
        gpos = @font.table(Constants::GPOS_TAG)
        return [] unless gpos

        @extract_kerning_pairs ||= begin
          pairs = []

          # This is a simplified implementation
          # Full implementation would parse GPOS lookup type 2 (Pair positioning)
          # For now, return empty array
          pairs
        end
      end
    end
  end
end
