# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    # Orchestrates the full SVG → Ufo::Glyph pipeline:
    #
    #   path data + transforms
    #     → Path::Parser.parse → [Command]
    #     → Path::ContourBuilder.build → [Ufo::Contour]
    #     → measure content bounds (Ufo::Bounds)
    #     → union content bounds with the SVG viewBox bounds
    #     → Normalizer maps the unioned space into the em-square
    #     → compose with the accumulated group transform
    #     → round to Integer
    #     → Ufo::Glyph
    #
    # For SVG files and directories, the Document class extracts the
    # viewBox, accumulated transforms, and path data; the Assembler
    # composes the normalizer with the group transform and runs the
    # pipeline once per path.
    class Assembler
      DEFAULT_VIEWBOX = Ufo::Bounds.new(min_x: 0, min_y: 0, max_x: DEFAULT_UPM, max_y: DEFAULT_UPM)

      attr_reader :upm

      # @param upm [Integer] font units-per-em
      def initialize(upm: SvgToGlyf::DEFAULT_UPM)
        @upm = upm.to_i
      end

      # Build a glyph directly from a path data string.
      #
      # @param path_data [String] SVG path d= attribute
      # @param codepoint [Integer, nil] Unicode codepoint
      # @param name [String, nil] glyph name
      # @param viewbox [Ufo::Bounds, Hash{Symbol=>Float}, nil] SVG viewbox
      # @param transform [Geometry::AffineTransform, nil] group transform
      # @return [Fontisan::Ufo::Glyph]
      def build_from_path_data(path_data, codepoint: nil, name: nil,
                               viewbox: nil, transform: nil)
        assemble(path_data: path_data,
                 viewbox: resolve_viewbox(viewbox),
                 group_transform: transform || Geometry::AffineTransform.identity,
                 codepoint: codepoint,
                 name: name)
      end

      # Build a glyph from an SVG file.
      #
      # @param file_path [String]
      # @param codepoint [Integer, nil] override; otherwise derived from filename
      # @return [Fontisan::Ufo::Glyph]
      def build_from_file(file_path, codepoint: nil)
        doc = Document.from_file(file_path)
        codepoint ||= codepoint_from_filename(File.basename(file_path))

        doc.each_path.with_object(nil) do |(data, transform), _|
          return assemble(path_data: data,
                          viewbox: doc.viewbox || default_viewbox,
                          group_transform: transform,
                          codepoint: codepoint,
                          name: nil)
        end

        empty_glyph(codepoint)
      end

      # Build a font from a directory of SVG files.
      #
      # @param dir [String]
      # @return [Fontisan::Ufo::Font]
      def build_from_directory(dir)
        font = Fontisan::Ufo::Font.new
        font.info.units_per_em = @upm

        Dir.glob(File.join(dir, "*.svg")).each do |path|
          glyph = build_from_file(path)
          font.glyphs[glyph.name] = glyph
        end

        font
      end

      private

      # Shared pipeline used by every entry point. Parses the d-string,
      # builds contours, computes the normalization bounds as the union
      # of the actual content bounds and the declared viewBox bounds,
      # applies the normalizer composed with the group transform, and
      # assembles the result into a Ufo::Glyph.
      def assemble(path_data:, viewbox:, group_transform:, codepoint:, name:)
        commands = Path::Parser.parse(path_data)
        contours = Path::ContourBuilder.new.build(commands)
        norm_bounds = normalization_bounds(contours, viewbox)
        final = normalizer_for(norm_bounds).final_transform(group_transform)
        transformed = contours.map { |c| transform_contour(c, final) }
        assemble_glyph(name || glyph_name_for(codepoint), transformed, codepoint)
      end

      # Union the actual content bounds with the SVG viewBox bounds.
      # Content outside the viewBox is preserved (not clipped) by
      # expanding the normalization space to contain it; content inside
      # a larger viewBox keeps its relative scale.
      #
      # @param contours [Array<Ufo::Contour>]
      # @param viewbox [Ufo::Bounds]
      # @return [Ufo::Bounds]
      def normalization_bounds(contours, viewbox)
        content = Ufo::Bounds.measure(contours)
        return viewbox if content.empty?

        content.union(viewbox)
      end

      def transform_contour(contour, transform)
        points = contour.points.map do |pt|
          x, y = transform.apply(pt.x, pt.y)
          Fontisan::Ufo::Point.new(x: x.round, y: y.round, type: pt.type,
                                   smooth: pt.smooth)
        end
        Fontisan::Ufo::Contour.new(points)
      end

      def normalizer_for(bounds)
        Geometry::Normalizer.new(bounds: bounds, upm: @upm)
      end

      # Accept either a Ufo::Bounds (preferred) or a legacy hash with
      # :width, :height (treated as origin 0,0). Returns a Bounds.
      def resolve_viewbox(viewbox)
        return default_viewbox unless viewbox
        return viewbox if viewbox.is_a?(Ufo::Bounds)

        Ufo::Bounds.new(min_x: 0, min_y: 0,
                        max_x: viewbox[:width].to_f,
                        max_y: viewbox[:height].to_f)
      end

      def default_viewbox
        self.class.const_get(:DEFAULT_VIEWBOX)
      end

      def assemble_glyph(name, contours, codepoint)
        glyph = Fontisan::Ufo::Glyph.new(name: name)
        glyph.width = @upm
        contours.each { |c| glyph.add_contour(c) }
        glyph.add_unicode(codepoint) if codepoint
        glyph
      end

      def empty_glyph(codepoint)
        glyph = Fontisan::Ufo::Glyph.new(name: glyph_name_for(codepoint))
        glyph.width = @upm
        glyph.add_unicode(codepoint) if codepoint
        glyph
      end

      # UFO convention: uniXXXX for BMP, uXXXXX for supplementary planes.
      def glyph_name_for(codepoint)
        return "glyph" unless codepoint

        codepoint < 0x10000 ? "uni%04X" % codepoint : "u%05X" % codepoint
      end

      # Derive a codepoint from a filename like "U+10940.svg" or "10940.svg".
      def codepoint_from_filename(basename)
        match = basename.match(/(?:U\+)?([0-9A-Fa-f]{4,6})\.svg\z/)
        return nil unless match

        match[1].to_i(16)
      end
    end
  end
end
