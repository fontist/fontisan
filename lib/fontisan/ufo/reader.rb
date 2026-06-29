# frozen_string_literal: true

module Fontisan
  module Ufo
    # Reads a UFO source directory into a typed Fontisan::Ufo::Font.
    #
    # Reads, in order:
    #   - `metainfo.plist`        (UFO version stamp; informational)
    #   - `fontinfo.plist`         (Info)
    #   - `layercontents.plist`    (layer ordering; optional in UFO 3)
    #   - `glyphs/contents.plist`  (default-layer glyph order)
    #   - `glyphs/<layer>/<name>.glif`  (per-glyph XML)
    #   - `kerning.plist`          (Kerning)
    #   - `features.fea`           (Features)
    #   - `lib.plist`              (Lib)
    #
    # Phase 1 reads `fontinfo.plist` + `glyphs/contents.plist` +
    # minimal `.glif` (name, advance, unicodes). Full `.glif`
    # decoding (contours, components, anchors) lands when the
    # compiler layer is built.
    class Reader
      attr_reader :font

      def initialize(font)
        @font = font
      end

      # @return [Fontisan::Ufo::Font]
      def read
        read_metainfo
        read_fontinfo
        read_layercontents
        read_glyphs_contents
        read_kerning
        read_features
        read_lib
        @font
      end

      private

      def read_metainfo
        path = join(@font.path, "metainfo.plist")
        return unless File.exist?(path)

        data = Plist.parse(File.read(path))
        @font.ufo_version = data["formatVersion"]
      end

      def read_fontinfo
        path = join(@font.path, "fontinfo.plist")
        return unless File.exist?(path)

        data = Plist.parse(File.read(path))
        @font.info = Info.new(data)
      end

      def read_layercontents
        # layercontents.plist is optional in UFO 3; default layer is
        # always present via LayerSet#initialize.
        path = join(@font.path, "layercontents.plist")
        return unless File.exist?(path)

        order = Plist.parse(File.read(path))
        order.each do |layer_name|
          @font.layers.add(layer_name)
        end
      end

      def read_glyphs_contents
        # Each layer's glyphs may live under `glyphs/<layer_name>/` (UFO 3)
        # or directly under `glyphs/` (UFO 2, single-layer case).
        # The latter applies when `glyphs/<layer_name>/` does not exist
        # but `glyphs/contents.plist` does.
        @font.layers.each do |layer|
          subdir = join(@font.path, "glyphs", layer.name)
          contents_path = if Dir.exist?(subdir)
                            join(subdir, "contents.plist")
                          else
                            join(@font.path, "glyphs", "contents.plist")
                          end
          next unless File.exist?(contents_path)

          order = Plist.parse(File.read(contents_path))

          # UFO 2 contents.plist is Hash<glyph_name, glif_filename>.
          # UFO 3 contents.plist can be Array<glif_filename> or
          # Array<Hash<glif_filename, glyph_name>>. Normalize to
          # Array<[glyph_name, glif_filename]>.
          entries =
            case order
            when Hash then order.to_a
            when Array
              if order.first.is_a?(Hash)
                order.flat_map(&:to_a)
              else
                order.map { |filename| [File.basename(filename, ".glif"), filename] }
              end
            else
              raise "unsupported contents.plist format: #{order.class}"
            end

          entries.each_value do |glif_filename|
            glif_path = if Dir.exist?(subdir)
                          join(subdir, glif_filename)
                        else
                          join(@font.path, "glyphs", glif_filename)
                        end
            next unless File.exist?(glif_path)

            layer.add(Glyph.from_glif(File.read(glif_path)))
          end
        end
      end

      def read_kerning
        path = join(@font.path, "kerning.plist")
        return unless File.exist?(path)

        data = Plist.parse(File.read(path))
        @font.kerning = Kerning.new(data)
      end

      def read_features
        path = join(@font.path, "features.fea")
        return unless File.exist?(path)

        @font.features = Features.new(text: File.read(path))
      end

      def read_lib
        path = join(@font.path, "lib.plist")
        return unless File.exist?(path)

        data = Plist.parse(File.read(path))
        @font.lib = Lib.new(data)
      end

      def join(*parts)
        File.join(*parts)
      end
    end
  end
end
