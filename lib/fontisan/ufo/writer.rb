# frozen_string_literal: true

module Fontisan
  module Ufo
    # Writes a UFO source directory from a typed Fontisan::Ufo::Font.
    #
    # Mirror of Reader. Writes, in order:
    #   - `metainfo.plist`        (UFO version stamp)
    #   - `fontinfo.plist`         (Info)
    #   - `layercontents.plist`    (UFO 3 only; layer ordering)
    #   - `glyphs/contents.plist`  (default-layer glyph order)
    #   - `glyphs/<name>.glif`     (per-glyph XML)
    #   - `glyphs/<layer>/...`     (additional layers)
    #   - `kerning.plist`
    #   - `features.fea`
    #   - `lib.plist`
    class Writer
      UFO_VERSION_DEFAULT = 3

      attr_reader :font

      def initialize(font)
        @font = font
      end

      # @param path [String] directory to write into; created if missing
      # @param ufo_version [Integer] 2 or 3 (default 3)
      def write(path, ufo_version: nil)
        @ufo_version = ufo_version || @font.ufo_version || UFO_VERSION_DEFAULT

        FileUtils.mkpath(path)
        write_metainfo(path)
        write_fontinfo(path)
        write_layercontents(path)
        write_glyphs(path)
        write_kerning(path)
        write_features(path)
        write_lib(path)
        path
      end

      private

      def write_metainfo(path)
        data = {
          "creator" => "org.fontisan.ufo",
          "formatVersion" => @ufo_version.to_i,
        }
        File.write(File.join(path, "metainfo.plist"), Plist.emit(data))
      end

      def write_fontinfo(path)
        File.write(File.join(path, "fontinfo.plist"), Plist.emit(@font.info.to_plist))
      end

      def write_layercontents(path)
        return unless @ufo_version >= 3
        return if @font.layers.size <= 1

        order = @font.layers.layers.keys
        File.write(File.join(path, "layercontents.plist"), Plist.emit(order))
      end

      def write_glyphs(path)
        # Default layer writes glyphs/contents.plist + glyphs/*.glif.
        # Additional layers write glyphs/<layer>/contents.plist + .glif.
        @font.layers.each do |layer|
          layer_dir = if layer.name == Layer::DEFAULT_NAME && @ufo_version < 3
                        File.join(path, "glyphs")
                      elsif layer.name == Layer::DEFAULT_NAME
                        File.join(path, "glyphs")
                      else
                        File.join(path, "glyphs", layer.name)
                      end
          FileUtils.mkpath(layer_dir)

          contents =
            layer.glyphs.transform_values { |g| "#{safe_filename(g.name)}.glif" }
          File.write(File.join(layer_dir, "contents.plist"), Plist.emit(contents))

          layer.glyphs.each_value do |glyph|
            File.write(File.join(layer_dir, "#{safe_filename(glyph.name)}.glif"), glyph.to_glif)
          end
        end
      end

      # Map a glyph name to a filesystem-safe filename. UFO conventions
      # use a base-prefixed name for names starting with non-letter.
      def safe_filename(name)
        return "_#{name}" if name.start_with?(".")
        return "_#{name}" unless name.match?(/\A[A-Za-z_]/)

        name
      end

      def write_kerning(path)
        return if @font.kerning.empty?

        File.write(File.join(path, "kerning.plist"), Plist.emit(@font.kerning.to_plist))
      end

      def write_features(path)
        return if @font.features.text.nil? || @font.features.text.empty?

        File.write(File.join(path, "features.fea"), @font.features.text)
      end

      def write_lib(path)
        return if @font.lib.data.empty?

        File.write(File.join(path, "lib.plist"), Plist.emit(@font.lib.data))
      end
    end
  end
end
