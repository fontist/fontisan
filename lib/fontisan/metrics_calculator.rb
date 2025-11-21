# frozen_string_literal: true

require_relative "constants"

module Fontisan
  # High-level utility class for accessing font metrics
  #
  # MetricsCalculator provides a convenient API for querying font metrics from
  # multiple OpenType tables without needing to work with the low-level table
  # structures directly. It wraps access to hhea, hmtx, head, maxp, and cmap
  # tables.
  #
  # The calculator handles missing tables gracefully and provides both
  # individual glyph metrics and string-level calculations.
  #
  # @example Basic usage
  #   font = FontLoader.from_file("path/to/font.ttf")
  #   calc = MetricsCalculator.new(font)
  #
  #   puts calc.ascent          # => 2048
  #   puts calc.descent         # => -512
  #   puts calc.line_height     # => 2650
  #   puts calc.units_per_em    # => 2048
  #
  # @example Glyph metrics
  #   width = calc.glyph_width(42)
  #   lsb = calc.glyph_left_side_bearing(42)
  #
  # @example String width calculation
  #   width = calc.string_width("Hello")
  #
  # @example Checking for metrics support
  #   if calc.has_metrics?
  #     puts "Font has complete horizontal metrics"
  #   end
  class MetricsCalculator
    # The font object this calculator operates on
    #
    # @return [OpenTypeFont, TrueTypeFont] The font instance
    attr_reader :font

    # Initialize a new MetricsCalculator
    #
    # @param font [OpenTypeFont, TrueTypeFont] Font instance to calculate metrics for
    # @raise [ArgumentError] if font is nil
    def initialize(font)
      raise ArgumentError, "Font cannot be nil" if font.nil?

      @font = font
      @hhea_table = nil
      @hmtx_table = nil
      @head_table = nil
      @maxp_table = nil
      @cmap_table = nil
      @hmtx_parsed = false
    end

    # Get typographic ascent from hhea table
    #
    # The ascent is the distance from the baseline to the highest ascender.
    # It is a positive value in font units (FUnits).
    #
    # @return [Integer, nil] Ascent value in FUnits, or nil if hhea table is missing
    #
    # @example
    #   calc.ascent # => 2048
    def ascent
      hhea&.ascent
    end

    # Get typographic descent from hhea table
    #
    # The descent is the distance from the baseline to the lowest descender.
    # It is typically a negative value in font units (FUnits).
    #
    # @return [Integer, nil] Descent value in FUnits, or nil if hhea table is missing
    #
    # @example
    #   calc.descent # => -512
    def descent
      hhea&.descent
    end

    # Get line gap from hhea table
    #
    # The line gap is additional vertical space between lines of text.
    # It is a non-negative value in font units (FUnits).
    #
    # @return [Integer, nil] Line gap value in FUnits, or nil if hhea table is missing
    #
    # @example
    #   calc.line_gap # => 90
    def line_gap
      hhea&.line_gap
    end

    # Get units per em from head table
    #
    # This value defines the font's coordinate system scale. Common values
    # are 1000 (PostScript fonts) or 2048 (TrueType fonts).
    #
    # @return [Integer, nil] Units per em value, or nil if head table is missing
    #
    # @example
    #   calc.units_per_em # => 2048
    def units_per_em
      head&.units_per_em
    end

    # Get advance width for a specific glyph
    #
    # The advance width is the horizontal distance to advance the pen position
    # after rendering this glyph. It is in font units (FUnits).
    #
    # @param glyph_id [Integer] The glyph ID (0-based)
    # @return [Integer, nil] Advance width in FUnits, or nil if not available
    #
    # @example
    #   calc.glyph_width(42) # => 1234
    def glyph_width(glyph_id)
      ensure_hmtx_parsed
      return nil unless hmtx

      metric = hmtx.metric_for(glyph_id)
      metric&.dig(:advance_width)
    end

    # Alias for {#glyph_width}
    #
    # @param glyph_id [Integer] The glyph ID (0-based)
    # @return [Integer, nil] Advance width in FUnits, or nil if not available
    alias glyph_advance_width glyph_width

    # Get left side bearing for a specific glyph
    #
    # The left side bearing (LSB) is the horizontal distance from the pen
    # position to the leftmost point of the glyph. It can be negative if
    # the glyph extends to the left of the pen position.
    #
    # @param glyph_id [Integer] The glyph ID (0-based)
    # @return [Integer, nil] Left side bearing in FUnits, or nil if not available
    #
    # @example
    #   calc.glyph_left_side_bearing(42) # => 50
    def glyph_left_side_bearing(glyph_id)
      ensure_hmtx_parsed
      return nil unless hmtx

      metric = hmtx.metric_for(glyph_id)
      metric&.dig(:lsb)
    end

    # Calculate total width for a string
    #
    # Calculates the sum of advance widths for all characters in the string.
    # This is a simplified calculation that does not account for kerning,
    # ligatures, or other advanced typography features.
    #
    # Characters not mapped in the font are skipped.
    #
    # @param string [String] The string to measure
    # @return [Integer, nil] Total width in FUnits, or nil if metrics unavailable
    #
    # @example
    #   calc.string_width("Hello") # => 5420
    def string_width(string)
      return nil unless has_metrics?
      return 0 if string.nil? || string.empty?

      total_width = 0
      string.each_codepoint do |codepoint|
        glyph_id = codepoint_to_glyph_id(codepoint)
        next unless glyph_id

        width = glyph_width(glyph_id)
        total_width += width if width
      end

      total_width
    end

    # Calculate line height
    #
    # Line height is calculated as: ascent - descent + line_gap
    # This represents the recommended spacing between consecutive baselines.
    #
    # @return [Integer, nil] Line height in FUnits, or nil if hhea table is missing
    #
    # @example
    #   calc.line_height # => 2650 (when ascent=2048, descent=-512, line_gap=90)
    def line_height
      return nil unless hhea

      ascent - descent + line_gap
    end

    # Alias for {#units_per_em}
    #
    # @return [Integer, nil] Units per em value, or nil if head table is missing
    alias em_height units_per_em

    # Check if font has complete horizontal metrics
    #
    # Returns true if the font has all required tables for horizontal metrics:
    # hhea, hmtx, head, and maxp tables.
    #
    # @return [Boolean] True if all metrics tables are present
    #
    # @example
    #   calc.has_metrics? # => true
    def has_metrics?
      !hhea.nil? && !hmtx.nil? && !head.nil? && !maxp.nil?
    end

    private

    # Get hhea table, caching the result
    #
    # @return [Tables::Hhea, nil] The hhea table or nil
    def hhea
      @hhea ||= font.table(Constants::HHEA_TAG)
    end

    # Get hmtx table, caching the result
    #
    # @return [Tables::Hmtx, nil] The hmtx table or nil
    def hmtx
      @hmtx ||= font.table(Constants::HMTX_TAG)
    end

    # Get head table, caching the result
    #
    # @return [Tables::Head, nil] The head table or nil
    def head
      @head ||= font.table(Constants::HEAD_TAG)
    end

    # Get maxp table, caching the result
    #
    # @return [Tables::Maxp, nil] The maxp table or nil
    def maxp
      @maxp ||= font.table(Constants::MAXP_TAG)
    end

    # Get cmap table, caching the result
    #
    # @return [Tables::Cmap, nil] The cmap table or nil
    def cmap
      @cmap ||= font.table(Constants::CMAP_TAG)
    end

    # Ensure hmtx table is parsed with context
    #
    # The hmtx table requires numberOfHMetrics from hhea and numGlyphs from maxp
    # to be parsed correctly. This method ensures parsing happens lazily on first use.
    #
    # @return [void]
    def ensure_hmtx_parsed
      return if @hmtx_parsed
      return unless hmtx && hhea && maxp

      hmtx.parse_with_context(hhea.number_of_h_metrics, maxp.num_glyphs)
      @hmtx_parsed = true
    end

    # Map Unicode codepoint to glyph ID using cmap table
    #
    # @param codepoint [Integer] Unicode codepoint
    # @return [Integer, nil] Glyph ID or nil if not mapped
    def codepoint_to_glyph_id(codepoint)
      return nil unless cmap

      mappings = cmap.unicode_mappings
      mappings[codepoint]
    end
  end
end
