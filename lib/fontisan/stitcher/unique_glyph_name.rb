# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Stateless glyph-name deconfliction for the Stitcher's target UFO.
    #
    # The Layer's contract (see +Ufo::Layer+) is that two glyphs cannot
    # share a name — +#add+ raises on conflict. Most Stitcher call sites
    # already know the name they want is free (e.g. they just synthesised
    # it). The two that don't — GlyphCopier (outline donors may share
    # post-table names) and CbdtPropagator (placeholders named "gid{N}"
    # collide with outline glyphs sharing the same donor-gid scheme) —
    # ask this helper to allocate a non-colliding name first.
    #
    # Centralising the rule here keeps the deconfliction algorithm in
    # one place: the suffix-search loop, the separator, the order in
    # which candidates are tried. Changing the rule (e.g. to a UUID
    # scheme) is a one-file edit.
    module UniqueGlyphName
      # Separator between the base name and the disambiguating suffix.
      # A literal period so the generated name ("gid110.1") still
      # reads as a variant of the original.
      SUFFIX_SEPARATOR = "."

      # @param target [Ufo::Font, #glyphs] the target whose +#glyphs+
      #   hash is the namespace being deconflicted against. Accepts the
      #   UFO font directly so callers don't have to dig out the layer.
      # @param base_name [String, #to_s] the requested name.
      # @return [String] +base_name+ unchanged if no glyph with that
      #   name exists in +target.glyphs+; otherwise the first
      #   +"base.1"+, +"base.2"+, ... that does not exist.
      def self.in(target, base_name)
        base = base_name.to_s
        return base unless target.glyphs.key?(base)

        suffix = 1
        loop do
          candidate = "#{base}#{SUFFIX_SEPARATOR}#{suffix}"
          return candidate unless target.glyphs.key?(candidate)

          suffix += 1
        end
      end
    end
  end
end
