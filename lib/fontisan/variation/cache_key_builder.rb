# frozen_string_literal: true

module Fontisan
  module Variation
    # Builds cache keys for variation calculations
    #
    # This class centralizes cache key generation with consistent formatting
    # and efficient string construction. All variation caches should use
    # this builder to ensure key compatibility.
    #
    # @example Building cache keys
    #   builder = CacheKeyBuilder
    #
    #   # Scalars key
    #   key = builder.scalars_key(coordinates, axes)
    #
    #   # Instance key
    #   key = builder.instance_key(font_checksum, coordinates)
    class CacheKeyBuilder
      class << self
        # Build cache key for scalars
        #
        # Generates a deterministic key based on axis tags and coordinate values.
        # Axes are sorted to ensure consistent keys regardless of hash order.
        #
        # @param coordinates [Hash<String, Float>] Design space coordinates
        # @param axes [Array<VariationAxisRecord>] Variation axes
        # @return [String] Cache key
        #
        # @example
        #   key = CacheKeyBuilder.scalars_key(
        #     { "wght" => 700, "wdth" => 100 },
        #     axes
        #   )
        #   # => "scalars:wdth,wght:100.0,700.0"
        def scalars_key(coordinates, axes)
          axis_tags = axes.map(&:axis_tag).sort
          coord_values = axis_tags.map { |tag| coordinates[tag] || 0.0 }
          "scalars:#{axis_tags.join(',')}:#{coord_values.join(',')}"
        end

        # Build cache key for interpolated value
        #
        # Generates key based on base value, deltas, and scalars.
        # Useful for caching individual interpolation results.
        #
        # @param base_value [Numeric] Base value
        # @param deltas [Array<Numeric>] Delta values
        # @param scalars [Array<Float>] Region scalars
        # @return [String] Cache key
        #
        # @example
        #   key = CacheKeyBuilder.interpolation_key(100, [10, 5], [0.8, 0.5])
        #   # => "interp:100:10,5:0.8,0.5"
        def interpolation_key(base_value, deltas, scalars)
          "interp:#{base_value}:#{deltas.join(',')}:#{scalars.join(',')}"
        end

        # Build cache key for font instance
        #
        # Generates key for entire instance generation result.
        # Coordinates are sorted to ensure consistency.
        #
        # @param font_checksum [String] Font identifier
        # @param coordinates [Hash<String, Float>] Instance coordinates
        # @return [String] Cache key
        #
        # @example
        #   key = CacheKeyBuilder.instance_key("font_123", { "wght" => 700 })
        #   # => "instance:font_123:{\"wght\"=>700.0}"
        def instance_key(font_checksum, coordinates)
          sorted_coords = coordinates.sort.to_h
          "instance:#{font_checksum}:#{sorted_coords}"
        end

        # Build cache key for region matches
        #
        # Generates key based on coordinates and region hash.
        # Region hash is used to quickly identify region set without
        # serializing entire region data.
        #
        # @param coordinates [Hash<String, Float>] Design space coordinates
        # @param regions [Array<Hash>] Variation regions
        # @return [String] Cache key
        #
        # @example
        #   key = CacheKeyBuilder.region_matches_key(coords, regions)
        #   # => "regions:{\"wght\"=>700.0}:12345678"
        def region_matches_key(coordinates, regions)
          sorted_coords = coordinates.sort.to_h
          region_hash = regions.hash
          "regions:#{sorted_coords}:#{region_hash}"
        end

        # Build cache key for glyph deltas
        #
        # Generates key for cached glyph delta application results.
        #
        # @param glyph_id [Integer] Glyph ID
        # @param coordinates [Hash<String, Float>] Design space coordinates
        # @return [String] Cache key
        #
        # @example
        #   key = CacheKeyBuilder.glyph_deltas_key(42, { "wght" => 700 })
        #   # => "glyph:42:{\"wght\"=>700.0}"
        def glyph_deltas_key(glyph_id, coordinates)
          sorted_coords = coordinates.sort.to_h
          "glyph:#{glyph_id}:#{sorted_coords}"
        end

        # Build cache key for metrics deltas
        #
        # Generates key for cached metrics variation results.
        #
        # @param metrics_type [String] Metrics table tag (HVAR, VVAR, MVAR)
        # @param glyph_id [Integer, nil] Glyph ID (nil for font-wide metrics)
        # @param coordinates [Hash<String, Float>] Design space coordinates
        # @return [String] Cache key
        #
        # @example
        #   key = CacheKeyBuilder.metrics_deltas_key("HVAR", 42, coords)
        #   # => "metrics:HVAR:42:{\"wght\"=>700.0}"
        def metrics_deltas_key(metrics_type, glyph_id, coordinates)
          sorted_coords = coordinates.sort.to_h
          glyph_part = glyph_id ? ":#{glyph_id}" : ""
          "metrics:#{metrics_type}#{glyph_part}:#{sorted_coords}"
        end

        # Build cache key for blend operations
        #
        # Generates key for CFF2 blend operator results.
        #
        # @param blend_index [Integer] Blend operation index
        # @param scalars [Array<Float>] Variation scalars
        # @return [String] Cache key
        #
        # @example
        #   key = CacheKeyBuilder.blend_key(0, [0.8, 0.5])
        #   # => "blend:0:0.8,0.5"
        def blend_key(blend_index, scalars)
          "blend:#{blend_index}:#{scalars.join(',')}"
        end

        # Build custom cache key
        #
        # Generates key with custom prefix and components.
        # Use for specialized caching needs.
        #
        # @param prefix [String] Key prefix
        # @param components [Array] Key components (will be joined with :)
        # @return [String] Cache key
        #
        # @example
        #   key = CacheKeyBuilder.custom_key("mydata", [font_id, value1, value2])
        #   # => "mydata:font_123:100:200"
        def custom_key(prefix, *components)
          "#{prefix}:#{components.join(':')}"
        end
      end
    end
  end
end
