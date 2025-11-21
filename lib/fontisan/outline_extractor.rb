# frozen_string_literal: true

require_relative "models/glyph_outline"

module Fontisan
  # Extracts glyph outlines from font tables
  #
  # [`OutlineExtractor`](lib/fontisan/outline_extractor.rb) provides a unified
  # interface for extracting glyph outline data from both TrueType (glyf table)
  # and CFF (Compact Font Format) fonts. It uses a strategy pattern to handle
  # the different outline formats transparently.
  #
  # The extractor:
  # - Automatically detects font format (TrueType vs CFF)
  # - Handles simple glyphs (direct outline data)
  # - Handles compound glyphs (recursively resolves components)
  # - Returns standardized [`GlyphOutline`](lib/fontisan/models/glyph_outline.rb) objects
  #
  # This class is responsible for extraction only, not business logic or
  # presentation. It's designed to be composed with
  # [`GlyphAccessor`](lib/fontisan/glyph_accessor.rb) for higher-level operations.
  #
  # @example Extracting a glyph outline
  #   extractor = Fontisan::OutlineExtractor.new(font)
  #   outline = extractor.extract(65)  # 'A' character
  #
  #   puts outline.contour_count
  #   puts outline.to_svg_path
  #
  # @example Using with GlyphAccessor
  #   accessor = Fontisan::GlyphAccessor.new(font)
  #   outline = accessor.outline_for_char('A')
  #
  # Reference: [`docs/GETTING_STARTED.md:125-172`](docs/GETTING_STARTED.md:125)
  class OutlineExtractor
    # @return [TrueTypeFont, OpenTypeFont] Font instance
    attr_reader :font

    # Initialize a new outline extractor
    #
    # @param font [TrueTypeFont, OpenTypeFont] Font to extract outlines from
    # @raise [ArgumentError] If font is nil or doesn't have required tables
    def initialize(font)
      raise ArgumentError, "Font cannot be nil" if font.nil?

      unless font.respond_to?(:table)
        raise ArgumentError, "Font must respond to :table method"
      end

      @font = font
    end

    # Extract outline for a specific glyph
    #
    # This method automatically detects the font format and delegates to
    # the appropriate extraction strategy. For compound glyphs (TrueType only),
    # it recursively resolves component outlines and combines them with
    # proper transformations.
    #
    # @param glyph_id [Integer] The glyph index (0-based, 0 is .notdef)
    # @return [Models::GlyphOutline, nil] The outline or nil if glyph not
    #   found or empty
    # @raise [ArgumentError] If glyph_id is invalid
    # @raise [Fontisan::MissingTableError] If required tables are missing
    #
    # @example Extract a simple glyph
    #   outline = extractor.extract(65)
    #   puts "Glyph has #{outline.contour_count} contours"
    #
    # @example Handle empty glyphs (like space)
    #   outline = extractor.extract(space_glyph_id)
    #   # => nil (empty glyphs return nil)
    def extract(glyph_id)
      validate_glyph_id!(glyph_id)

      if cff_font?
        extract_cff_outline(glyph_id)
      elsif truetype_font?
        extract_truetype_outline(glyph_id)
      else
        raise Fontisan::MissingTableError,
              "Font has neither glyf nor CFF table"
      end
    end

    private

    # Check if this is a CFF font
    #
    # @return [Boolean] True if font has CFF table
    def cff_font?
      font.table(Constants::CFF_TAG) != nil
    end

    # Check if this is a TrueType font
    #
    # @return [Boolean] True if font has glyf table
    def truetype_font?
      font.has_table?("glyf")
    end

    # Validate glyph ID
    #
    # @param glyph_id [Integer] Glyph ID to validate
    # @raise [ArgumentError] If glyph ID is invalid
    def validate_glyph_id!(glyph_id)
      if glyph_id.nil?
        raise ArgumentError, "glyph_id cannot be nil"
      end

      if glyph_id.negative?
        raise ArgumentError, "glyph_id must be >= 0, got: #{glyph_id}"
      end

      maxp = font.table("maxp")
      if maxp && glyph_id >= maxp.num_glyphs
        raise ArgumentError,
              "glyph_id #{glyph_id} exceeds number of glyphs (#{maxp.num_glyphs})"
      end
    end

    # Extract outline from TrueType glyph
    #
    # Handles both simple and compound glyphs. For compound glyphs,
    # recursively resolves component outlines and applies transformations.
    #
    # @param glyph_id [Integer] Glyph ID
    # @return [Models::GlyphOutline, nil] Outline or nil if empty
    # @raise [Fontisan::MissingTableError] If required tables are missing
    def extract_truetype_outline(glyph_id)
      glyph = get_truetype_glyph(glyph_id)
      return nil unless glyph

      # Handle empty glyphs (space, etc.)
      return nil if glyph.respond_to?(:empty?) && glyph.empty?

      if glyph.simple?
        extract_simple_outline(glyph)
      elsif glyph.compound?
        extract_compound_outline(glyph)
      else
        raise Fontisan::Error, "Unknown glyph type: #{glyph.class}"
      end
    end

    # Extract outline from CFF glyph
    #
    # CFF glyphs don't have compound structures, so extraction is
    # straightforward from the CharString.
    #
    # @param glyph_id [Integer] Glyph ID
    # @return [Models::GlyphOutline, nil] Outline or nil if empty
    # @raise [Fontisan::MissingTableError] If CFF table is missing
    def extract_cff_outline(glyph_id)
      cff = font.table(Constants::CFF_TAG)
      raise_missing_table!(Constants::CFF_TAG) unless cff

      # Get CharString for glyph
      charstring = cff.charstring_for_glyph(glyph_id)
      return nil unless charstring

      # CharString has path data
      path = charstring.path
      return nil if path.empty?

      # Convert CharString path to contours
      contours = convert_cff_path_to_contours(path)
      return nil if contours.empty?

      # Get bounding box from CharString
      bbox_array = charstring.bounding_box
      return nil unless bbox_array

      bbox = {
        x_min: bbox_array[0],
        y_min: bbox_array[1],
        x_max: bbox_array[2],
        y_max: bbox_array[3],
      }

      Models::GlyphOutline.new(
        glyph_id: glyph_id,
        contours: contours,
        bbox: bbox,
      )
    rescue StandardError => e
      warn "Failed to extract CFF outline for glyph #{glyph_id}: #{e.message}"
      nil
    end

    # Get TrueType glyph from glyf table
    #
    # @param glyph_id [Integer] Glyph ID
    # @return [SimpleGlyph, CompoundGlyph, nil] Glyph object
    # @raise [Fontisan::MissingTableError] If required tables are missing
    def get_truetype_glyph(glyph_id)
      glyf = font.table("glyf")
      raise_missing_table!("glyf") unless glyf

      loca = font.table("loca")
      raise_missing_table!("loca") unless loca

      head = font.table("head")
      raise_missing_table!("head") unless head

      # Ensure loca is parsed
      unless loca.parsed?
        maxp = font.table("maxp")
        raise_missing_table!("maxp") unless maxp
        loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)
      end

      glyf.glyph_for(glyph_id, loca, head)
    end

    # Extract outline from a simple TrueType glyph
    #
    # @param glyph [SimpleGlyph] Simple glyph object
    # @return [Models::GlyphOutline] Outline object
    def extract_simple_outline(glyph)
      contours = []

      # Process each contour
      glyph.num_contours.times do |contour_index|
        points = glyph.points_for_contour(contour_index)
        contours << points if points && !points.empty?
      end

      bbox = {
        x_min: glyph.x_min,
        y_min: glyph.y_min,
        x_max: glyph.x_max,
        y_max: glyph.y_max,
      }

      Models::GlyphOutline.new(
        glyph_id: glyph.glyph_id,
        contours: contours,
        bbox: bbox,
      )
    end

    # Extract outline from a compound TrueType glyph
    #
    # Recursively resolves component glyphs and applies transformations
    # to combine them into a single outline.
    #
    # @param glyph [CompoundGlyph] Compound glyph object
    # @return [Models::GlyphOutline] Combined outline object
    def extract_compound_outline(glyph)
      all_contours = []
      combined_bbox = nil

      # Process each component
      glyph.components.each do |component|
        component_outline = extract(component.glyph_index)
        next unless component_outline

        # Get transformation matrix
        matrix = component.transformation_matrix

        # Transform component contours
        transformed_contours = transform_contours(
          component_outline.contours,
          matrix,
        )
        all_contours.concat(transformed_contours)

        # Update combined bounding box
        component_bbox = component_outline.bbox
        combined_bbox = merge_bboxes(combined_bbox, component_bbox, matrix)
      end

      # Use original bbox if we couldn't compute one
      combined_bbox ||= {
        x_min: glyph.x_min,
        y_min: glyph.y_min,
        x_max: glyph.x_max,
        y_max: glyph.y_max,
      }

      Models::GlyphOutline.new(
        glyph_id: glyph.glyph_id,
        contours: all_contours,
        bbox: combined_bbox,
      )
    end

    # Transform contours using an affine transformation matrix
    #
    # @param contours [Array<Array<Hash>>] Original contours
    # @param matrix [Array<Float>] Transformation matrix [a, b, c, d, e, f]
    # @return [Array<Array<Hash>>] Transformed contours
    def transform_contours(contours, matrix)
      a, b, c, d, e, f = matrix

      contours.map do |contour|
        contour.map do |point|
          x = point[:x]
          y = point[:y]

          # Apply affine transformation: x' = a*x + c*y + e, y' = b*x + d*y + f
          new_x = (a * x + c * y + e).round
          new_y = (b * x + d * y + f).round

          {
            x: new_x,
            y: new_y,
            on_curve: point[:on_curve],
          }
        end
      end
    end

    # Merge two bounding boxes
    #
    # @param bbox1 [Hash, nil] First bounding box
    # @param bbox2 [Hash] Second bounding box
    # @param matrix [Array<Float>] Transformation matrix for bbox2
    # @return [Hash] Merged bounding box
    def merge_bboxes(bbox1, bbox2, matrix)
      # Transform bbox2 corners
      a, b, c, d, e, f = matrix

      corners = [
        [bbox2[:x_min], bbox2[:y_min]],
        [bbox2[:x_max], bbox2[:y_min]],
        [bbox2[:x_min], bbox2[:y_max]],
        [bbox2[:x_max], bbox2[:y_max]],
      ]

      transformed_corners = corners.map do |x, y|
        [
          (a * x + c * y + e).round,
          (b * x + d * y + f).round,
        ]
      end

      transformed_bbox = {
        x_min: transformed_corners.map(&:first).min,
        y_min: transformed_corners.map(&:last).min,
        x_max: transformed_corners.map(&:first).max,
        y_max: transformed_corners.map(&:last).max,
      }

      return transformed_bbox unless bbox1

      # Merge with existing bbox
      {
        x_min: [bbox1[:x_min], transformed_bbox[:x_min]].min,
        y_min: [bbox1[:y_min], transformed_bbox[:y_min]].min,
        x_max: [bbox1[:x_max], transformed_bbox[:x_max]].max,
        y_max: [bbox1[:y_max], transformed_bbox[:y_max]].max,
      }
    end

    # Convert CFF CharString path to contours
    #
    # CFF paths are stored as arrays of command hashes. We need to
    # convert them to the contour format used by GlyphOutline.
    #
    # @param path [Array<Hash>] CharString path data
    # @return [Array<Array<Hash>>] Contours array
    def convert_cff_path_to_contours(path)
      contours = []
      current_contour = []

      path.each do |cmd|
        case cmd[:type]
        when :move_to
          # Start new contour
          contours << current_contour unless current_contour.empty?
          current_contour = []
          current_contour << {
            x: cmd[:x].round,
            y: cmd[:y].round,
            on_curve: true,
          }
        when :line_to
          current_contour << {
            x: cmd[:x].round,
            y: cmd[:y].round,
            on_curve: true,
          }
        when :curve_to
          # CFF uses cubic Bézier curves
          # For now, we'll add control points and end point
          # This is a simplification - proper handling would require
          # converting cubic to quadratic or keeping cubic format
          current_contour << {
            x: cmd[:x1].round,
            y: cmd[:y1].round,
            on_curve: false,
          }
          current_contour << {
            x: cmd[:x2].round,
            y: cmd[:y2].round,
            on_curve: false,
          }
          current_contour << {
            x: cmd[:x].round,
            y: cmd[:y].round,
            on_curve: true,
          }
        end
      end

      # Add final contour
      contours << current_contour unless current_contour.empty?

      contours
    end

    # Raise MissingTableError
    #
    # @param table_tag [String] Table tag
    # @raise [Fontisan::MissingTableError]
    def raise_missing_table!(table_tag)
      raise Fontisan::MissingTableError,
            "Required table '#{table_tag}' not found in font"
    end
  end
end
