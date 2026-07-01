# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    # Orchestrates the full SVG → Ufo::Glyph pipeline:
    #
    #   path data + transforms
    #     → Path::Parser.parse → [Command]
    #     → Path::ContourBuilder.build → [Ufo::Contour]
    #     → apply final transform (normalization · group transform)
    #     → round to Integer
    #     → Ufo::Glyph
    #
    # For SVG files and directories, the Document class extracts the
    # viewBox, accumulated transforms, and path data; the Assembler
    # composes the normalizer with the group transform and runs the
    # pipeline once per path.
    class Assembler
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
      # @param viewbox [Hash{Symbol=>Float}, nil] :width, :height
      # @param transform [Geometry::AffineTransform, nil] group transform
      # @return [Fontisan::Ufo::Glyph]
      def build_from_path_data(path_data, codepoint: nil, name: nil,
                               viewbox: nil, transform: nil)
        viewbox ||= { width: @upm, height: @upm }
        final = normalizer_for(**viewbox).final_transform(transform || Geometry::AffineTransform.identity)
        contours = build_contours(path_data, final)
        assemble_glyph(name || glyph_name_for(codepoint), contours, codepoint)
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
          return build_from_doc_path(data, transform, doc, codepoint)
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

      def build_from_doc_path(data, group_transform, doc, codepoint)
        final = normalizer_for(width: doc.viewbox_width, height: doc.viewbox_height)
          .final_transform(group_transform)
        contours = build_contours(data, final)
        assemble_glyph(glyph_name_for(codepoint), contours, codepoint)
      end

      def build_contours(path_data, final_transform)
        commands = Path::Parser.parse(path_data)
        contours = Path::ContourBuilder.new.build(commands)
        contours.map { |c| transform_contour(c, final_transform) }
      end

      def transform_contour(contour, transform)
        points = contour.points.map do |pt|
          x, y = transform.apply(pt.x, pt.y)
          Fontisan::Ufo::Point.new(x: x.round, y: y.round, type: pt.type, smooth: pt.smooth)
        end
        Fontisan::Ufo::Contour.new(points)
      end

      def normalizer_for(width:, height:)
        Geometry::Normalizer.new(viewbox_width: width, viewbox_height: height, upm: @upm)
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
