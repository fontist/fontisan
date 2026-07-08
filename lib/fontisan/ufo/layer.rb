# frozen_string_literal: true

module Fontisan
  module Ufo
    # A single layer in a UFO source. A Layer holds a set of glyphs
    # keyed by name. The default layer is `public.default` per UFO 3.
    #
    # == Naming contract
    #
    # Glyph names are the layer's primary key. Two distinct glyphs with
    # the same name cannot coexist — adding the second would silently
    # destroy the first, a class of bug that has historically cost real
    # data (e.g. CJK Ext G cmap loss when CBDT placeholders collided
    # with outline glyphs sharing "gid{N}" names).
    #
    # To make that contract unbreakable, +#add+ RAISES on conflict.
    # Callers who want one of the other two semantics pick the method
    # that names it:
    #
    #   +#add+::    insert; raise if the name is taken (the safe default)
    #   +#put+::    insert; overwrite any existing glyph with the same name
    #
    # Callers that need auto-renaming (insertion without giving up on a
    # collision) call +UniqueGlyphName.in(target, base)+ first, then
    # +#add+ the glyph under the returned name.
    class Layer
      DEFAULT_NAME = "public.default"

      # Raised by +#add+ when a glyph with the same name already exists.
      # Surfaces what would otherwise be a silent overwrite so the
      # caller can decide between +#put+ (intentional replace) and
      # +UniqueGlyphName.in+ (auto-rename).
      class GlyphExistsError < StandardError
        attr_reader :name

        def initialize(name)
          @name = name
          super("a glyph named #{name.inspect} already exists; use #put " \
                "to overwrite or UniqueGlyphName.in to deconflict")
        end
      end

      attr_reader :name, :glyphs

      def initialize(name = DEFAULT_NAME)
        @name = name
        @glyphs = {}
      end

      def [](glyph_name)
        @glyphs[glyph_name.to_s]
      end

      # Insert +glyph+. Raises +GlyphExistsError+ if a glyph with the
      # same name is already present — this is the contract that keeps
      # the layer's key namespace trustworthy.
      #
      # @param glyph [Glyph]
      # @return [Glyph] the same glyph
      # @raise [GlyphExistsError] if +glyph.name+ is already taken
      def add(glyph)
        name = glyph.name.to_s
        raise GlyphExistsError, name if @glyphs.key?(name)

        @glyphs[name] = glyph
        glyph
      end

      # Insert +glyph+, replacing any existing glyph with the same
      # name. Use this when the caller has positively decided that the
      # previous glyph (if any) should be discarded.
      #
      # @param glyph [Glyph]
      # @return [Glyph] the same glyph
      def put(glyph)
        @glyphs[glyph.name.to_s] = glyph
        glyph
      end

      def each(&)
        @glyphs.each_value(&)
      end

      def size
        @glyphs.size
      end
    end
  end
end
