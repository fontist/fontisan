# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Owns the mechanical concerns of copying glyphs from donor sources
    # into a target UFO font.
    #
    # The Stitcher's per-subfont build needs to:
    #   - inject a `.notdef` glyph at GID 0
    #   - copy outline glyphs from donor sources, optionally skipping
    #     donors the caller names (e.g. the CBDT source, whose glyphs
    #     take a different code path)
    #   - register each copied glyph with the deduplicator so visually
    #     identical glyphs from different donors share a gid
    #
    # GlyphCopier centralizes that logic in one stateless-per-call
    # collaborator. The Stitcher constructs one with a deduplicator and
    # calls its methods in the order the cmap contract requires
    # (see Fontisan::Ufo::Compile::Cmap for first-wins semantics).
    class GlyphCopier
      # @param deduplicator [Stitcher::Deduplicator, nil] when non-nil,
      #   visually identical glyphs share a gid in the target. Pass nil
      #   to disable deduplication.
      def initialize(deduplicator)
        @deduplicator = deduplicator
      end

      # Inject a `.notdef` glyph at GID 0 of `target`.
      #
      # If a binding exists with `donor_gid == 0`, copy the donor's
      # .notdef; otherwise synthesize an empty one. The injected glyph
      # is registered with the deduplicator so subsequent .notdef
      # references deduplicate against it.
      #
      # @param bindings [Array<Hash>] stitch bindings to search
      # @param target [Ufo::Font] target UFO
      def inject_notdef(bindings, target)
        notdef_binding = bindings.find { |b| b[:donor_gid].zero? }
        if notdef_binding
          copy_glyph_into(target, name: ".notdef",
                                  source: notdef_binding[:source],
                                  donor_gid: 0)
        else
          target.layers.default_layer.add(Ufo::Glyph.new(name: ".notdef"))
        end
        dedup_target = target.glyphs[".notdef"]
        @deduplicator&.register(dedup_target, ".notdef") if dedup_target
      end

      # Copy outline glyphs from `bindings` into `target`, skipping any
      # sources the caller names (e.g. the CBDT source).
      #
      # Bindings are sorted by `[codepoint, donor_gid]` for deterministic
      # output. For each binding:
      #   - if deduplicator has seen a visually identical glyph that's
      #     already in the target, attach the codepoint to that glyph
      #     (extra unicode mapping);
      #   - otherwise copy the glyph under a unique name and register
      #     with the deduplicator.
      #
      # @param bindings [Array<Hash>] stitch bindings
      # @param target [Ufo::Font] target UFO
      # @param skip_sources [Array<Stitcher::Source>] sources whose
      #   bindings should be skipped (e.g. CBDT placeholder source)
      def copy_outlines(bindings, target, skip_sources: [])
        sorted_bindings(bindings).each do |binding|
          next if binding[:donor_gid].zero?
          next if skip_sources.any? { |s| s.equal?(binding[:source]) }

          glyph = binding[:source].glyph_for_gid(binding[:donor_gid])
          next unless glyph

          canonical = @deduplicator&.find(glyph)
          if canonical && target.glyphs.key?(canonical)
            add_extra_unicode(target, canonical, binding[:codepoint])
          else
            name = UniqueGlyphName.in(target, glyph.name)
            copy_glyph_into(target, name: name, source: binding[:source],
                                    donor_gid: binding[:donor_gid],
                                    codepoint: binding[:codepoint])
            @deduplicator&.register(glyph, name)
          end
        end
      end

      private

      def sorted_bindings(bindings)
        bindings.sort_by { |b| [b[:codepoint] || Float::INFINITY, b[:donor_gid]] }
      end

      def copy_glyph_into(target_font, name:, source:, donor_gid:, codepoint: nil)
        original = source.glyph_for_gid(donor_gid)
        return unless original

        copy = GlyphCloner.clone(original, name: name)
        copy.add_unicode(codepoint) if codepoint
        target_font.layers.default_layer.add(copy)
      end

      def add_extra_unicode(target_font, glyph_name, codepoint)
        return unless codepoint

        glyph = target_font.glyph(glyph_name)
        glyph.add_unicode(codepoint) unless glyph.unicodes.include?(codepoint)
      end
    end
  end
end
