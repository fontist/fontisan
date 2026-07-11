# frozen_string_literal: true

require "digest"

module Fontisan
  module Ufo
    # UFO 3 background image set. Lives at `UFO/images/` in a UFO
    # source directory. Each image is a PNG file referenced by glyph
    # GLIF `<image fileName="..."/>` elements.
    #
    # Per the UFO 3 spec, image files are arbitrary binary blobs (in
    # practice always PNG). The image set deduplicates by content hash
    # (sha256) so the same image referenced from multiple glyphs takes
    # one slot.
    #
    # @example Read images from a UFO directory
    #   imageset = ImageSet.load_from_dir("MyFont.ufo/images")
    #   imageset.each { |img| puts img.file_name }
    class ImageSet
      include Enumerable

      # @return [Hash{String=>Image}] filename → Image
      attr_reader :images

      def initialize
        @images = {}
      end

      # Load all PNG files from a UFO `images/` directory.
      #
      # @param dir [String] path to the `images` directory
      # @return [ImageSet]
      def self.load_from_dir(dir)
        is = new
        return is unless File.directory?(dir)

        Dir.each_child(dir).sort.each do |name|
          path = File.join(dir, name)
          next unless File.file?(path)

          is.register_file(name, File.binread(path))
        end
        is
      end

      # Register an image from its filename and raw bytes. Computes the
      # sha256 content hash automatically.
      #
      # @param file_name [String]
      # @param bytes [String] binary image data
      # @return [Image]
      def register_file(file_name, bytes)
        image = Image.new(
          file_name: file_name,
          sha: Digest::SHA256.hexdigest(bytes),
          bytes: bytes,
        )
        @images[file_name.to_s] = image
        image
      end

      # Look up an image by its filename.
      #
      # @param file_name [String]
      # @return [Image, nil]
      def find(file_name)
        @images[file_name.to_s]
      end
      alias [] find

      # Iterate over images in filename order.
      def each(&)
        return enum_for(:each) unless block_given?

        @images.each_value(&)
      end

      # Number of registered images.
      def count
        @images.size
      end

      def empty?
        @images.empty?
      end

      # Write all images to a target `images/` directory. Useful for
      # UFO round-trip serialization.
      #
      # @param dir [String] target `images` directory path
      def write_to_dir(dir)
        FileUtils.mkpath(dir) unless File.directory?(dir)
        @images.each do |name, img|
          File.binwrite(File.join(dir, name), img.bytes)
        end
      end
    end
  end
end
