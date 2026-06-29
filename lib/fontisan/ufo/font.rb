# frozen_string_literal: true

module Fontisan
  module Ufo
    # Top-level container for a UFO source directory.
    #
    # A Fontisan::Ufo::Font corresponds to one `.ufo` directory. It
    # exposes typed access to the font's metadata, layers, kerning,
    # features, and any custom data.
    #
    # The class is the read/write API; serialization is handled by
    # Fontisan::Ufo::Reader and Fontisan::Ufo::Writer.
    class Font
      attr_accessor :path, :info, :features, :kerning, :lib, :ufo_version
      attr_reader :layers, :data, :images

      def initialize
        @path = nil
        @ufo_version = nil
        @info = Info.new
        @layers = LayerSet.new
        @features = Features.new
        @kerning = Kerning.new
        @lib = Lib.new
        @data = nil # DataSet needs the Font ref, set by Reader
        @images = ImageSet.new
      end

      # Convenience accessor for the default layer's glyphs.
      def glyphs
        @layers.default_layer.glyphs
      end

      # Convenience: lookup a glyph in the default layer by name.
      def glyph(name)
        @layers.default_layer[name]
      end

      # Convenience: read family name through the Info model.
      def family_name
        @info.family_name
      end

      # Convenience: iterate every glyph in every layer.
      def each_glyph(&)
        @layers.each do |layer|
          layer.each(&)
        end
      end

      # @param path [String, Pathname] directory containing the UFO
      # @return [Fontisan::Ufo::Font] the parsed font
      def self.open(path)
        font = new
        font.path = path.to_s
        Reader.new(font).read
        font
      end
    end
  end
end
