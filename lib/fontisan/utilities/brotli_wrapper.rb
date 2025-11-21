# frozen_string_literal: true

require "brotli"

module Fontisan
  module Utilities
    # Wrapper for Brotli compression with consistent settings
    #
    # [`BrotliWrapper`](lib/fontisan/utilities/brotli_wrapper.rb) provides
    # a consistent interface for Brotli compression with configurable quality
    # and error handling. Used primarily for WOFF2 encoding.
    #
    # Brotli compression is significantly more effective than zlib (used in WOFF),
    # typically achieving 20-30% better compression ratios on font data.
    #
    # @example Compress table data
    #   compressed = BrotliWrapper.compress(table_data, quality: 11)
    #
    # @example Decompress data
    #   decompressed = BrotliWrapper.decompress(compressed_data)
    class BrotliWrapper
      # Default compression quality (0-11, higher = better but slower)
      # Quality 11 gives best compression for WOFF2
      DEFAULT_QUALITY = 11

      # Minimum quality level
      MIN_QUALITY = 0

      # Maximum quality level
      MAX_QUALITY = 11

      # Compress data using Brotli
      #
      # @param data [String] Data to compress
      # @param quality [Integer] Compression quality (0-11)
      # @param mode [Symbol] Compression mode (:generic, :text, :font)
      # @return [String] Compressed data
      # @raise [ArgumentError] If quality is out of range
      # @raise [Error] If compression fails
      #
      # @example Compress with default quality
      #   compressed = BrotliWrapper.compress(data)
      #
      # @example Compress with specific quality
      #   compressed = BrotliWrapper.compress(data, quality: 9)
      def self.compress(data, quality: DEFAULT_QUALITY, mode: :font)
        validate_quality!(quality)
        validate_data!(data)

        begin
          # Use Brotli gem with specified quality
          # The brotli gem doesn't expose mode constants, only quality
          Brotli.deflate(data, quality: quality)
        rescue StandardError => e
          raise Fontisan::Error,
                "Brotli compression failed: #{e.message}"
        end
      end

      # Decompress Brotli-compressed data
      #
      # @param data [String] Compressed data
      # @return [String] Decompressed data
      # @raise [Error] If decompression fails
      #
      # @example
      #   decompressed = BrotliWrapper.decompress(compressed_data)
      def self.decompress(data)
        validate_data!(data)

        begin
          Brotli.inflate(data)
        rescue StandardError => e
          raise Fontisan::Error,
                "Brotli decompression failed: #{e.message}"
        end
      end

      # Calculate compression ratio
      #
      # @param original_size [Integer] Original data size
      # @param compressed_size [Integer] Compressed data size
      # @return [Float] Compression ratio (0.0-1.0)
      #
      # @example
      #   ratio = BrotliWrapper.compression_ratio(1000, 300)
      #   # => 0.3 (30% of original size)
      def self.compression_ratio(original_size, compressed_size)
        return 0.0 if original_size.zero?

        compressed_size.to_f / original_size
      end

      # Calculate compression percentage
      #
      # @param original_size [Integer] Original data size
      # @param compressed_size [Integer] Compressed data size
      # @return [Float] Compression percentage reduction
      #
      # @example
      #   pct = BrotliWrapper.compression_percentage(1000, 300)
      #   # => 70.0 (70% reduction)
      def self.compression_percentage(original_size, compressed_size)
        return 0.0 if original_size.zero?

        ((original_size - compressed_size).to_f / original_size * 100).round(1)
      end

      class << self
        private

        # Validate compression quality parameter
        #
        # @param quality [Integer] Quality level
        # @raise [ArgumentError] If quality is invalid
        def validate_quality!(quality)
          unless quality.is_a?(Integer)
            raise ArgumentError,
                  "Quality must be an Integer, got #{quality.class}"
          end

          unless (MIN_QUALITY..MAX_QUALITY).cover?(quality)
            raise ArgumentError,
                  "Quality must be between #{MIN_QUALITY} and #{MAX_QUALITY}, " \
                  "got #{quality}"
          end
        end

        # Validate data parameter
        #
        # @param data [String] Data to validate
        # @raise [ArgumentError] If data is invalid
        def validate_data!(data)
          if data.nil?
            raise ArgumentError, "Data cannot be nil"
          end

          unless data.respond_to?(:bytesize)
            raise ArgumentError,
                  "Data must be a String-like object, got #{data.class}"
          end
        end

        # Convert mode symbol to Brotli constant
        #
        # NOTE: The brotli gem doesn't expose mode constants
        # This method is kept for API compatibility but unused
        #
        # @param mode [Symbol] Mode symbol
        # @return [Integer] Mode value (unused)
        def brotli_mode(_mode)
          # The brotli gem only accepts quality parameter
          # Mode is not configurable in current version
          0
        end
      end
    end
  end
end
