# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Glyph-processing filters applied between the UFO model and the
      # binary table compilers. Each filter is a stateless module
      # with `.run(glyphs, **opts)` that mutates the glyph list
      # (or returns a new one).
      #
      # OCP: adding a filter = new module + one REGISTRY entry.
      # The compiler picks which filters to run based on the output
      # format — not a switch statement in compiler code.
      module Filters
        autoload :ReverseContourDirection,
                 "fontisan/ufo/compile/filters/reverse_contour_direction"
        autoload :CubicToQuadratic,
                 "fontisan/ufo/compile/filters/cubic_to_quadratic"
        autoload :DecomposeComponents,
                 "fontisan/ufo/compile/filters/decompose_components"
        autoload :FlattenComponents,
                 "fontisan/ufo/compile/filters/flatten_components"
        autoload :Transformations,
                 "fontisan/ufo/compile/filters/transformations"
        autoload :SortContours,
                 "fontisan/ufo/compile/filters/sort_contours"
        autoload :PropagateAnchors,
                 "fontisan/ufo/compile/filters/propagate_anchors"

        # Filters that MUST run for TTF output (TrueType only
        # supports quadratic curves + clockwise outer winding).
        TTF_REQUIRED = %i[
          cubic_to_quadratic
          reverse_contour_direction
        ].freeze

        # Filters that MUST run for OTF output (CFF handles cubic
        # natively, so no curve conversion needed; winding is
        # already correct for PostScript).
        OTF_REQUIRED = [].freeze

        REGISTRY = {
          reverse_contour_direction: ReverseContourDirection,
          cubic_to_quadratic: CubicToQuadratic,
          decompose_components: DecomposeComponents,
          flatten_components: FlattenComponents,
          transformations: Transformations,
          sort_contours: SortContours,
          propagate_anchors: PropagateAnchors,
        }.freeze

        # @param names [Array<Symbol>] filter names from REGISTRY
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] glyphs to filter
        # @param opts [Hash] per-filter options
        # @return [Array<Fontisan::Ufo::Glyph>] the (possibly mutated) glyphs
        def self.apply(names, glyphs, **)
          Array(names).reduce(glyphs) do |current, name|
            klass = REGISTRY[name.to_sym] or
              raise ArgumentError, "unknown filter: #{name.inspect}"
            klass.run(current, **)
          end
        end
      end
    end
  end
end
