# frozen_string_literal: true

module Fontisan
  module Collection
    # Read-only counterpart to {Builder}. Opens an existing TTC/OTC/dfont
    # and exposes per-face metadata (glyph count, codepoint count, sfnt
    # version) and the cmap union across all faces.
    #
    # Delegates header parsing to {FontLoader} — never hand-rolls the
    # TTC header bytes (that would duplicate BaseCollection.from_file
    # and only handle TTC/OTC, not dfont).
    #
    # @example Per-face glyph counts
    #   reader = Collection::Reader.open("family.ttc")
    #   reader.stats.map { |s| [s.index, s.glyph_count] }
    #
    # @example Cmap union
    #   Collection::Reader.open("family.otc").cmap_union.size
    class Reader
      autoload :Stats, "fontisan/collection/reader/stats"

      # @!attribute [r] path
      #   @return [String] the file path this reader was opened with
      attr_reader :path

      # Collection formats this reader accepts. Single source of truth —
      # matches {FontLoader::COLLECTION_CLASSES}.
      FORMATS = %i[ttc otc dfont].freeze

      # @param path [String] path to a TTC/OTC/dfont file
      # @raise [ArgumentError] if the file is not a recognized collection
      def initialize(path)
        @path = path
        detected = FontLoader.detect_format(path)
        unless FORMATS.include?(detected)
          raise ArgumentError,
                "#{path} is not a TTC/OTC/dfont (detected: #{detected.inspect})"
        end

        @collection = FontLoader.load_collection(path)
      end

      # Convenience constructor.
      # @param path [String]
      # @return [Reader]
      def self.open(path)
        new(path)
      end

      # @return [Integer] number of faces in the collection
      def face_count
        @collection.num_fonts
      end

      # Yields each face as a loaded TTF/OTF font. Without a block,
      # returns an Enumerator (so callers can chain +each_with_index+).
      # The Enumerator's size is set to +face_count+ so size-based
      # assertions work without consuming it.
      #
      # @yieldparam face [TrueTypeFont, OpenTypeFont]
      # @return [Enumerator, void]
      def each_face
        return enum_for(:each_face) { face_count } unless block_given?

        face_count.times { |i| yield FontLoader.load(@path, font_index: i) }
      end

      # @return [Array<Stats>] one Stats per face, in face-index order
      def stats
        each_face.map.with_index do |face, i|
          Stats.new(
            index: i,
            glyph_count: face.table("maxp")&.num_glyphs || 0,
            codepoint_count: (face.table("cmap")&.unicode_mappings || {}).size,
            sfnt_version: face.header.sfnt_version,
          )
        end
      end

      # Union of every face's cmap keys.
      #
      # @return [Set<Integer>]
      def cmap_union
        each_face.with_object(Set.new) do |face, union|
          union.merge((face.table("cmap")&.unicode_mappings || {}).keys)
        end
      end
    end
  end
end
