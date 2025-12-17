# frozen_string_literal: true

require_relative "instance_generator"
require_relative "cache"
require_relative "../utils/thread_pool"
require "etc"

module Fontisan
  module Variation
    # Generates multiple font instances in parallel
    #
    # Uses thread pool for efficient batch processing with caching.
    # Supports progress tracking and graceful error handling per instance.
    #
    # @example Basic batch generation
    #   generator = ParallelGenerator.new(font)
    #   coordinates_list = [
    #     { "wght" => 300 },
    #     { "wght" => 700 }
    #   ]
    #   instances = generator.generate_batch(coordinates_list)
    #
    # @example With progress callback
    #   generator.generate_batch(coordinates_list) do |index, total|
    #     puts "Generated #{index}/#{total}"
    #   end
    #
    # @example Custom thread count
    #   generator = ParallelGenerator.new(font, threads: 8)
    class ParallelGenerator
      # @return [TrueTypeFont, OpenTypeFont] Variable font
      attr_reader :font

      # @return [ThreadSafeCache] Thread-safe cache
      attr_reader :cache

      # @return [Integer] Number of threads
      attr_reader :thread_count

      # Initialize parallel generator
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font
      # @param options [Hash] Options
      # @option options [ThreadSafeCache] :cache Cache instance (creates new if not provided)
      # @option options [Integer] :threads Thread count (default: max(4, processor_count))
      def initialize(font, options = {})
        @font = font
        @cache = options[:cache] || ThreadSafeCache.new
        @thread_count = options[:threads] || [4, Etc.nprocessors].max
      end

      # Generate multiple instances in parallel
      #
      # Processes each coordinate set in parallel using thread pool.
      # Returns results in same order as input coordinates.
      #
      # @param coordinates_list [Array<Hash>] List of coordinate sets
      # @yield [index, total] Progress callback (optional)
      # @yieldparam index [Integer] Current completed count
      # @yieldparam total [Integer] Total count
      # @return [Array<Hash>] Generated instances with metadata
      def generate_batch(coordinates_list, &progress_callback)
        return [] if coordinates_list.empty?

        total = coordinates_list.length
        results = Array.new(total)
        completed = 0
        mutex = Mutex.new

        # Create thread pool
        pool = Fontisan::Utils::ThreadPool.new(@thread_count)

        # Schedule all jobs
        futures = coordinates_list.map.with_index do |coordinates, index|
          pool.schedule do
            {
              index: index,
              result: generate_with_cache(coordinates),
            }
          end
        end

        # Collect results
        futures.each do |future|
          job_result = future.value
          results[job_result[:index]] = job_result[:result]

          # Update progress
          if progress_callback
            mutex.synchronize do
              completed += 1
              yield(completed, total)
            end
          end
        end

        # Shutdown pool
        pool.shutdown

        results
      end

      # Generate instance with caching
      #
      # Uses cache to avoid regenerating identical instances.
      #
      # @param coordinates [Hash<String, Float>] Design space coordinates
      # @return [Hash] Instance data with metadata
      def generate_with_cache(coordinates)
        font_checksum = calculate_font_checksum

        begin
          tables = @cache.fetch_instance(font_checksum, coordinates) do
            generator = InstanceGenerator.new(@font, coordinates)
            generator.generate
          end

          {
            success: true,
            coordinates: coordinates,
            tables: tables,
            error: nil,
          }
        rescue StandardError => e
          {
            success: false,
            coordinates: coordinates,
            tables: nil,
            error: {
              message: e.message,
              class: e.class.name,
              backtrace: e.backtrace&.first(5),
            },
          }
        end
      end

      private

      # Calculate font checksum for cache key
      #
      # @return [String] Font identifier
      def calculate_font_checksum
        # Use combination of table checksums for quick identification
        # In production, might use actual checksum from head table
        "font_#{@font.object_id}"
      end
    end
  end
end
