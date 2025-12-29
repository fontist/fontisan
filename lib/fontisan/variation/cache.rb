# frozen_string_literal: true

require_relative "cache_key_builder"

module Fontisan
  module Variation
    # Caches variation calculations for performance
    #
    # This class implements a caching layer for expensive variation calculations
    # to significantly improve instance generation performance. It caches:
    # - Normalized scalars per coordinate set
    # - Interpolated values
    # - Instance generation results
    # - Region matches
    #
    # Cache strategies:
    # 1. LRU (Least Recently Used) for memory management
    # 2. Coordinate-based keys for scalar caching
    # 3. Invalidation on font modification
    # 4. Optional persistent caching across sessions
    #
    # @example Using the cache with instance generation
    #   cache = Fontisan::Variation::Cache.new(max_size: 100)
    #   scalars = cache.fetch_scalars(coordinates, axes) do
    #     calculate_scalars(coordinates, axes)
    #   end
    #
    # @example Cache statistics
    #   cache.statistics
    #   # => { hits: 150, misses: 50, hit_rate: 0.75 }
    class Cache
      # @return [Integer] Maximum cache size
      attr_reader :max_size

      # @return [Hash] Cache statistics
      attr_reader :stats

      # Initialize cache
      #
      # @param max_size [Integer] Maximum number of entries (default: 1000)
      # @param ttl [Integer, nil] Time-to-live in seconds (nil for no expiration)
      def initialize(max_size: 1000, ttl: nil)
        @max_size = max_size
        @ttl = ttl
        @cache = {}
        @access_times = {}
        @access_counter = 0
        @stats = {
          hits: 0,
          misses: 0,
          evictions: 0,
          invalidations: 0,
        }
      end

      # Fetch or compute scalars for coordinates
      #
      # @param coordinates [Hash<String, Float>] Design space coordinates
      # @param axes [Array] Variation axes
      # @yield Block to calculate scalars if not cached
      # @return [Array<Float>] Cached or computed scalars
      def fetch_scalars(coordinates, axes, &)
        key = CacheKeyBuilder.scalars_key(coordinates, axes)
        fetch(key, &)
      end

      # Fetch or compute interpolated value
      #
      # @param base_value [Numeric] Base value
      # @param deltas [Array<Numeric>] Delta values
      # @param scalars [Array<Float>] Region scalars
      # @yield Block to calculate value if not cached
      # @return [Float] Cached or computed value
      def fetch_interpolated(base_value, deltas, scalars, &)
        key = CacheKeyBuilder.interpolation_key(base_value, deltas, scalars)
        fetch(key, &)
      end

      # Fetch or compute instance generation result
      #
      # @param font_checksum [String] Font identifier
      # @param coordinates [Hash<String, Float>] Instance coordinates
      # @yield Block to generate instance if not cached
      # @return [Hash] Cached or generated instance tables
      def fetch_instance(font_checksum, coordinates, &)
        key = CacheKeyBuilder.instance_key(font_checksum, coordinates)
        fetch(key, &)
      end

      # Fetch or compute region matches
      #
      # @param coordinates [Hash<String, Float>] Design space coordinates
      # @param regions [Array] Variation regions
      # @yield Block to calculate matches if not cached
      # @return [Array] Cached or computed region matches
      def fetch_region_matches(coordinates, regions, &)
        key = CacheKeyBuilder.region_matches_key(coordinates, regions)
        fetch(key, &)
      end

      # Generic fetch with caching
      #
      # @param key [String] Cache key
      # @yield Block to compute value if not cached
      # @return [Object] Cached or computed value
      def fetch(key)
        if cached?(key)
          @stats[:hits] += 1
          touch(key)
          return @cache[key][:value]
        end

        @stats[:misses] += 1
        value = yield
        store(key, value)
        value
      end

      # Check if key is cached and valid
      #
      # @param key [String] Cache key
      # @return [Boolean] True if cached and valid
      def cached?(key)
        return false unless @cache.key?(key)
        return false if expired?(key)

        true
      end

      # Store value in cache
      #
      # @param key [String] Cache key
      # @param value [Object] Value to store
      def store(key, value)
        evict_if_needed

        @cache[key] = {
          value: value,
          created_at: Time.now,
        }
        touch(key)
      end

      # Clear entire cache
      def clear
        @cache.clear
        @access_times.clear
        @stats[:invalidations] += 1
      end

      # Invalidate specific key
      #
      # @param key [String] Cache key to invalidate
      def invalidate(key)
        @cache.delete(key)
        @access_times.delete(key)
        @stats[:invalidations] += 1
      end

      # Invalidate keys matching pattern
      #
      # @param pattern [Regexp] Pattern to match keys
      def invalidate_matching(pattern)
        keys = @cache.keys.select { |k| k.match?(pattern) }
        keys.each { |k| invalidate(k) }
      end

      # Get cache statistics
      #
      # @return [Hash] Statistics including hit rate
      def statistics
        total = @stats[:hits] + @stats[:misses]
        hit_rate = total.zero? ? 0.0 : @stats[:hits].to_f / total

        @stats.merge(
          total_requests: total,
          hit_rate: hit_rate,
          size: @cache.size,
          max_size: @max_size,
        )
      end

      # Get cache size
      #
      # @return [Integer] Number of cached entries
      def size
        @cache.size
      end

      # Check if cache is empty
      #
      # @return [Boolean] True if empty
      def empty?
        @cache.empty?
      end

      # Check if cache is full
      #
      # @return [Boolean] True if at capacity
      def full?
        @cache.size >= @max_size
      end

      private

      # Check if entry has expired
      #
      # @param key [String] Cache key
      # @return [Boolean] True if expired
      def expired?(key)
        return false unless @ttl

        entry = @cache[key]
        return true unless entry

        Time.now - entry[:created_at] > @ttl
      end

      # Update access time for LRU
      #
      # @param key [String] Cache key
      def touch(key)
        @access_counter += 1
        @access_times[key] = @access_counter
      end

      # Evict entries if cache is full
      def evict_if_needed
        return unless full?

        # Remove least recently used entry
        lru_key = @access_times.min_by { |_k, v| v }&.first
        return unless lru_key

        @cache.delete(lru_key)
        @access_times.delete(lru_key)
        @stats[:evictions] += 1
      end
    end

    # Thread-safe cache wrapper
    #
    # Wraps Cache with Mutex for thread-safe operations.
    class ThreadSafeCache < Cache
      def initialize(max_size: 1000, ttl: nil)
        super
        @mutex = Mutex.new
      end

      def fetch(key)
        # Check cache without entering critical section for computation
        @mutex.synchronize do
          if cached?(key)
            @stats[:hits] += 1
            touch(key)
            return @cache[key][:value]
          end
        end

        # Compute value outside of mutex
        value = yield

        # Store result
        @mutex.synchronize do
          evict_if_needed
          @cache[key] = {
            value: value,
            created_at: Time.now,
          }
          touch(key)
        end

        value
      end

      def store(key, value)
        @mutex.synchronize do
          evict_if_needed
          @cache[key] = {
            value: value,
            created_at: Time.now,
          }
          touch(key)
        end
      end

      def clear
        @mutex.synchronize { super }
      end

      def invalidate(key)
        @mutex.synchronize { super }
      end

      def statistics
        @mutex.synchronize { super }
      end
    end
  end
end
