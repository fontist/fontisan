# frozen_string_literal: true

module Fontisan
  module Ufo
    # A background image anchored to a glyph (common in color fonts).
    #
    # In UFO 3, images live in `UFO/images/` as binary blobs (PNG in
    # practice). Each image is referenced from a glyph's GLIF via
    # `<image fileName="..."/>`. The image set stores the actual bytes
    # and deduplicates by sha256 content hash.
    class Image
      attr_reader :file_name, :transformation, :color, :sha, :bytes

      # @param file_name [String] filename within the UFO images/ directory
      # @param transformation [Hash, nil] UFO image transformation matrix
      # @param color [String, nil] optional color hint
      # @param sha [String, nil] content sha256 hex digest
      # @param bytes [String, nil] raw image bytes (set by ImageSet)
      def initialize(file_name:, transformation: nil, color: nil, sha: nil,
                     bytes: nil)
        @file_name = file_name.to_s
        @transformation = transformation
        @color = color
        @sha = sha
        @bytes = bytes
      end
    end
  end
end
