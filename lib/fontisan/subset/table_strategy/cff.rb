# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # CFF (Compact Font Format) subsetter strategy.
      #
      # Subsets CFF tables by routing through the UFO model:
      #
      #   source font → Ufo::Convert::FromBinData → UFO (with contours)
      #                → filter glyphs to mapping →
      #                → Ufo::Compile::Cff.build → new CFF bytes
      #
      # This is the architecturally preferred path: the UFO model is
      # the canonical representation, CFF is a serialization. The
      # strategy reuses the existing compile pipeline rather than
      # reimplementing CFF INDEX arithmetic.
      #
      # Glyphs not in the mapping are dropped from the UFO before
      # compilation. The Cff.build pipeline generates the correct
      # charset (GID → SID mapping) from the retained glyph names.
      #
      # See TODO #15 for the full design rationale and the CFF2
      # extension path.
      class Cff
        # @param context [SubsetContext]
        # @param tag [String] "CFF "
        # @param table [Object] parsed CFF table (unused — we work
        #   from the source font directly)
        # @return [String] subset CFF table bytes
        def self.call(context:, tag:, table:)
          source_font = context.font
          mapping = context.mapping

          ufo = Ufo::Convert::FromBinData.convert(source_font)
          filter_ufo_glyphs!(ufo, mapping)

          # Rename the first glyph (source GID 0) to .notdef so the
          # CFF compiler's charset generation produces a valid .notdef
          # entry at GID 0.
          first_name = ufo.glyphs.keys.first
          if first_name && first_name != ".notdef"
            notdef = ufo.glyphs.delete(first_name)
            notdef = Ufo::Glyph.new(name: ".notdef") if notdef.nil?
            ufo.glyphs[".notdef"] = notdef
          end

          glyphs = ufo.layers.default_layer.each.to_a
          Fontisan::Ufo::Compile::Cff.build(ufo, glyphs: glyphs)
        end

        # Drop glyphs from the UFO that are not in the mapping's
        # new-id set. Keeps .notdef (GID 0) regardless of mapping.
        #
        # @param ufo [Ufo::Font]
        # @param mapping [GlyphMapping]
        def self.filter_ufo_glyphs!(ufo, mapping)
          retained_old_ids = Set.new(mapping.old_ids)

          # Build the set of glyph names to keep by resolving old
          # GIDs → names via the source's post table.
          kept_names = []
          ufo.glyphs.each_key do |name|
            kept_names << name
          end

          # We need to filter by GID, but UFO is name-keyed.
          # Resolve: walk the source post table to get GID → name,
          # then keep only names whose GID is in the mapping.
          source = ufo
          post = nil
          # The UFO doesn't carry GID info after conversion; we rely
          # on the mapping's old_ids. Since the UFO was converted
          # from the same source font, the UFO glyph order matches
          # the source GID order. So GID N in the source = Nth glyph
          # added to the UFO default layer.
          all_names = ufo.glyphs.keys
          names_to_keep = all_names.each_with_index.each_with_object(Set.new) do |(name, gid), keep|
            keep << name if retained_old_ids.include?(gid)
          end

          # Always keep .notdef
          names_to_keep << ".notdef" if all_names.any? { |n| n == ".notdef" }

          ufo.glyphs.reject! { |name, _| !names_to_keep.include?(name) }
        end

        # Ensure .notdef is present at GID 0. The CFF compiler
        # expects it.
        #
        # @param ufo [Ufo::Font]
        def self.ensure_notdef_present!(ufo)
          return if ufo.glyphs.key?(".notdef")

          notdef = Ufo::Glyph.new(name: ".notdef")
          notdef.width = 0
          ufo.layers.default_layer.add(notdef)
        end

        private_class_method :filter_ufo_glyphs!, :ensure_notdef_present!
      end
    end
  end
end
