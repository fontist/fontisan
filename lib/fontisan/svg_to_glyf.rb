# frozen_string_literal: true

# Autoload hub for the Fontisan::SvgToGlyf namespace.
#
# SvgToGlyf converts SVG path data (as produced by ucode's code-chart
# extraction) into Ufo::Glyph objects that feed directly into the
# existing UFO → TTF compile pipeline.
#
# The cubic-to-quadratic conversion and contour winding correction
# are handled automatically by Ufo::Compile::Filters::CubicToQuadratic
# and ReverseContourDirection when the glyph is compiled to TTF.
# SvgToGlyf only needs to parse the SVG and emit cubic contours.
module Fontisan
  module SvgToGlyf
    autoload :Geometry, "fontisan/svg_to_glyf/geometry"
    autoload :Path, "fontisan/svg_to_glyf/path"
    autoload :Document, "fontisan/svg_to_glyf/document"
    autoload :Assembler, "fontisan/svg_to_glyf/assembler"

    DEFAULT_UPM = 1000

    # Convert an SVG path `d` string into a Ufo::Glyph.
    #
    # @param path_data [String] SVG path commands (e.g., "M 0 0 L 100 100 Z")
    # @param upm [Integer] target font units-per-em
    # @param codepoint [Integer, nil] Unicode codepoint to assign
    # @param name [String, nil] glyph name (defaults to uni{codepoint.hex})
    # @param viewbox [Hash{Symbol=>Float}, nil] SVG viewbox with :width, :height
    # @param transform [Fontisan::SvgToGlyf::Geometry::AffineTransform, nil]
    #   accumulated group transform
    # @return [Fontisan::Ufo::Glyph]
    def self.convert(path_data, upm: DEFAULT_UPM, codepoint: nil, name: nil,
                     viewbox: nil, transform: nil)
      Assembler.new(upm: upm).build_from_path_data(
        path_data, codepoint: codepoint, name: name,
                   viewbox: viewbox, transform: transform
      )
    end

    # Convert an SVG file into a Ufo::Glyph.
    #
    # @param file_path [String] path to an .svg file
    # @param upm [Integer] target font units-per-em
    # @param codepoint [Integer, nil] override the codepoint (otherwise
    #   derived from the filename if it matches U+XXXX.svg)
    # @return [Fontisan::Ufo::Glyph]
    def self.from_svg_file(file_path, upm: DEFAULT_UPM, codepoint: nil)
      Assembler.new(upm: upm).build_from_file(file_path, codepoint: codepoint)
    end

    # Convert a directory of SVG files into a Ufo::Font, one glyph per file.
    #
    # Filenames must encode a codepoint: U+XXXX.svg or hexcode.svg.
    #
    # @param dir [String] directory containing .svg files
    # @param upm [Integer] target font units-per-em
    # @return [Fontisan::Ufo::Font]
    def self.from_directory(dir, upm: DEFAULT_UPM)
      Assembler.new(upm: upm).build_from_directory(dir)
    end
  end
end
