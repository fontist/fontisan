# frozen_string_literal: true

require_relative "../../models/outline"

module Fontisan
  module Tables
    # Resolves compound glyphs into simple outlines
    #
    # [`CompoundGlyphResolver`](lib/fontisan/tables/glyf/compound_glyph_resolver.rb)
    # handles the recursive resolution of compound (composite) glyphs in TrueType fonts.
    # Compound glyphs are composed of references to other glyphs with transformation
    # matrices applied. This resolver:
    #
    # - Recursively resolves component glyphs (which may themselves be compound)
    # - Applies transformation matrices to each component
    # - Merges all components into a single simple outline
    # - Handles nested compound glyphs (compound glyphs referencing other compounds)
    # - Detects and prevents circular references
    #
    # **Transformation Process:**
    #
    # Each component has a transformation matrix [a, b, c, d, e, f] representing:
    #   x' = a*x + c*y + e
    #   y' = b*x + d*y + f
    #
    # Where:
    # - a, d: Scale factors for x and y
    # - b, c: Rotation/skew components
    # - e, f: Translation offsets (x, y)
    #
    # **Resolution Strategy:**
    #
    # 1. Start with compound glyph
    # 2. For each component:
    #    a. Get component glyph (may be simple or compound)
    #    b. If compound, recursively resolve it first
    #    c. Apply component's transformation matrix
    #    d. Merge into result outline
    # 3. Return merged simple outline
    #
    # @example Resolving a compound glyph
    #   resolver = CompoundGlyphResolver.new(glyf_table, loca_table, head_table)
    #   outline = resolver.resolve(compound_glyph)
    #
    # @example With circular reference detection
    #   visited = Set.new
    #   outline = resolver.resolve(compound_glyph, visited)
    class CompoundGlyphResolver
      # Maximum recursion depth to prevent infinite loops
      MAX_DEPTH = 32

      # @return [Glyf] The glyf table
      attr_reader :glyf

      # @return [Loca] The loca table
      attr_reader :loca

      # @return [Head] The head table
      attr_reader :head

      # Initialize resolver with required tables
      #
      # @param glyf [Glyf] Glyf table
      # @param loca [Loca] Loca table
      # @param head [Head] Head table
      def initialize(glyf, loca, head)
        @glyf = glyf
        @loca = loca
        @head = head
      end

      # Resolve a compound glyph into a simple outline
      #
      # @param compound_glyph [CompoundGlyph] Compound glyph to resolve
      # @param visited [Set<Integer>] Set of visited glyph IDs (for circular ref detection)
      # @param depth [Integer] Current recursion depth
      # @return [Outline] Resolved simple outline
      # @raise [Error] If circular reference detected or max depth exceeded
      def resolve(compound_glyph, visited = Set.new, depth = 0)
        # Check recursion depth
        if depth > MAX_DEPTH
          raise Fontisan::Error,
                "Maximum recursion depth (#{MAX_DEPTH}) exceeded resolving compound glyph #{compound_glyph.glyph_id}"
        end

        # Check for circular reference
        if visited.include?(compound_glyph.glyph_id)
          raise Fontisan::Error,
                "Circular reference detected in compound glyph #{compound_glyph.glyph_id}"
        end

        # Mark as visited
        visited = visited.dup.add(compound_glyph.glyph_id)

        # Start with empty merged outline
        merged_outline = Models::Outline.new(
          glyph_id: compound_glyph.glyph_id,
          commands: [],
          bbox: {
            x_min: compound_glyph.x_min,
            y_min: compound_glyph.y_min,
            x_max: compound_glyph.x_max,
            y_max: compound_glyph.y_max,
          },
        )

        # Resolve each component
        compound_glyph.components.each do |component|
          # Get component glyph
          component_glyph = glyf.glyph_for(component.glyph_index, loca, head)

          # Skip empty components
          next if component_glyph.nil? || component_glyph.empty?

          # Get component outline (recursively if compound)
          component_outline = if component_glyph.compound?
                                # Recursively resolve compound component
                                resolve(component_glyph, visited, depth + 1)
                              else
                                # Convert simple glyph to outline
                                Models::Outline.from_truetype(component_glyph,
                                                              component.glyph_index)
                              end

          # Apply transformation matrix
          matrix = component.transformation_matrix
          transformed_outline = component_outline.transform(matrix)

          # Merge into result
          merged_outline.merge!(transformed_outline)
        end

        merged_outline
      end
    end
  end
end
