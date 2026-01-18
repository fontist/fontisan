# frozen_string_literal: true

module Fontisan
  module Type1
    # AFM (Adobe Font Metrics) file parser
    #
    # [`AFMParser`](lib/fontisan/type1/afm_parser.rb) parses Adobe Font Metrics
    # files which contain font metric information for Type 1 fonts.
    #
    # AFM files include:
    # - Character widths
    # - Kerning pairs
    # - Character bounding boxes
    # - Font metadata (name, version, copyright, etc.)
    #
    # @example Parse an AFM file
    #   afm = Fontisan::Type1::AFMParser.parse_file("font.afm")
    #   puts afm.font_name
    #   puts afm.character_widths['A']
    #   puts afm.kerning_pairs[['A', 'V']]
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5004.AFM_Spec.pdf
    class AFMParser
      # @return [String] Font name
      attr_reader :font_name

      # @return [String] Full name
      attr_reader :full_name

      # @return [String] Family name
      attr_reader :family_name

      # @return [String] Weight
      attr_reader :weight

      # @return [String] Version
      attr_reader :version

      # @return [String] Copyright notice
      attr_reader :copyright

      # @return [Hash<String, Integer>] Character widths (glyph name => width)
      attr_reader :character_widths

      # @return [Hash<Array(String>, Integer>] Kerning pairs ([left, right] => adjustment)
      attr_reader :kerning_pairs

      # @return [Hash] Character bounding boxes (glyph name => {llx, lly, urx, ury})
      attr_reader :character_bboxes

      # @return [Integer] Font bounding box [llx, lly, urx, ury]
      attr_reader :font_bbox

      # @return [Hash] Raw AFM data
      attr_reader :raw_data

      # Parse AFM file
      #
      # @param path [String] Path to AFM file
      # @return [AFMParser] Parsed AFM data
      # @raise [ArgumentError] If path is nil
      # @raise [Fontisan::Error] If file cannot be read or parsed
      def self.parse_file(path)
        raise ArgumentError, "Path cannot be nil" if path.nil?

        unless File.exist?(path)
          raise Fontisan::Error, "AFM file not found: #{path}"
        end

        content = File.read(path, encoding: "ISO-8859-1")
        parse(content)
      end

      # Parse AFM content
      #
      # @param content [String] AFM file content
      # @return [AFMParser] Parsed AFM data
      def self.parse(content)
        new.parse(content)
      end

      # Alias for parse method
      def self.parse_string(content)
        parse(content)
      end

      # Initialize a new AFMParser
      def initialize
        @character_widths = {}
        @kerning_pairs = {}
        @character_bboxes = {}
        @raw_data = {}
        @font_bbox = nil
      end

      # Parse AFM content
      #
      # @param content [String] AFM file content
      # @return [AFMParser] Self for method chaining
      def parse(content)
        parse_global_metrics(content)
        parse_character_metrics(content)
        parse_kerning_data(content)
        self
      end

      # Get character width for glyph
      #
      # @param glyph_name [String] Glyph name
      # @return [Integer, nil] Character width or nil if not found
      def width(glyph_name)
        @character_widths[glyph_name]
      end

      # Get kerning adjustment for character pair
      #
      # @param left [String] Left glyph name
      # @param right [String] Right glyph name
      # @return [Integer, nil] Kerning adjustment or nil if not found
      def kerning(left, right)
        @kerning_pairs[[left, right]]
      end

      # Check if character exists
      #
      # @param glyph_name [String] Glyph name
      # @return [Boolean] True if character exists
      def has_character?(glyph_name)
        @character_widths.key?(glyph_name)
      end

      private

      # Parse global font metrics
      #
      # @param content [String] AFM content
      def parse_global_metrics(content)
        # FontName
        if (match = content.match(/^FontName\s+(.+)$/i))
          @font_name = match[1].strip
        end

        # FullName
        if (match = content.match(/^FullName\s+(.+)$/i))
          @full_name = match[1].strip
        end

        # FamilyName
        if (match = content.match(/^FamilyName\s+(.+)$/i))
          @family_name = match[1].strip
        end

        # Weight
        if (match = content.match(/^Weight\s+(.+)$/i))
          @weight = match[1].strip
        end

        # Version
        if (match = content.match(/^Version\s+(.+)$/i))
          @version = match[1].strip
        end

        # Notice
        if (match = content.match(/^Notice\s+(.+)$/i))
          @copyright = match[1].strip
        end

        # FontBBox
        if (match = content.match(/^FontBBox\s+(.+)$/i))
          bbox = match[1].strip.split.map(&:to_i)
          @font_bbox = bbox if bbox.length >= 4
        end
      end

      # Parse character metrics
      #
      # @param content [String] AFM content
      def parse_character_metrics(content)
        # Find StartCharMetrics section
        char_metrics_section = content.match(/^StartCharMetrics\s+(.+?)$/i)
        return unless char_metrics_section

        char_metrics_section[1].to_i

        # Parse character metrics until EndCharMetrics
        in_char_metrics = false
        content.each_line do |line|
          if /^StartCharMetrics/i.match?(line)
            in_char_metrics = true
            next
          end

          break if /^EndCharMetrics/i.match?(line)
          next unless in_char_metrics

          # Parse character metric line
          # Format: C name ; WX width ; B llx lly urx ury ...
          parse_char_metric_line(line)
        end
      end

      # Parse a single character metric line
      #
      # @param line [String] Character metric line
      def parse_char_metric_line(line)
        return if line.strip.empty?

        glyph_name = nil
        char_width = nil
        char_bbox = nil

        # Parse character metric line
        # Format: C code ; WX width ; N name ; B llx lly urx ury ...
        # Or: C code ; WX width ; B llx lly urx ury ... (no N field)

        # Extract glyph name from N field if present
        # Format: N name ; or N;name;
        if (name_match = line.match(/;\s+N\s+([^\s;]+)/))
          glyph_name = name_match[1]
          # Remove quotes if present
          glyph_name = glyph_name.gsub(/['"]/, "")
        end

        # Extract width (WX)
        if (width_match = line.match(/WX\s+(\d+)/))
          char_width = width_match[1].to_i
        end

        # Extract bounding box (B)
        if (bbox_match = line.match(/B\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)/))
          char_bbox = {
            llx: bbox_match[1].to_i,
            lly: bbox_match[2].to_i,
            urx: bbox_match[3].to_i,
            ury: bbox_match[4].to_i,
          }
        end

        # Store if we have a name and width
        if glyph_name && char_width
          @character_widths[glyph_name] = char_width
        end

        # Store bounding box if we have a name and bbox
        if glyph_name && char_bbox
          @character_bboxes[glyph_name] = char_bbox
        end
      end

      # Parse kerning data
      #
      # @param content [String] AFM content
      def parse_kerning_data(content)
        # Find StartKernData section
        in_kern_data = false
        in_kern_pairs = false

        content.each_line do |line|
          if /^StartKernData/i.match?(line)
            in_kern_data = true
            next
          end

          if /^EndKernData/i.match?(line)
            in_kern_data = false
            next
          end

          if /^StartKernPairs\s+/i.match?(line)
            in_kern_pairs = true
            next
          end

          if /^EndKernPairs/i.match?(line)
            in_kern_pairs = false
            next
          end

          next unless in_kern_data && in_kern_pairs

          # Parse kerning pair line
          # Format: KPX left right adjustment
          parse_kern_pair_line(line)
        end
      end

      # Parse a kerning pair line
      #
      # @param line [String] Kerning pair line
      def parse_kern_pair_line(line)
        return if line.strip.empty?

        # KPX format: KPX left right adjustment
        if (match = line.match(/^KPX\s+(\S+)\s+(\S+)\s+(-?\d+)/i))
          left = match[1]
          right = match[2]
          adjustment = match[3].to_i

          # Remove quotes if present
          left = left.gsub(/['"]/, "")
          right = right.gsub(/['"]/, "")

          @kerning_pairs[[left, right]] = adjustment
        end
      end
    end
  end
end
