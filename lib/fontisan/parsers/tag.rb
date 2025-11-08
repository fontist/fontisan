# frozen_string_literal: true

module Fontisan
  module Parsers
    # Represents an OpenType tag (4-character identifier)
    #
    # OpenType tags are four-byte identifiers used to identify tables,
    # scripts, languages, and features. Tags are case-sensitive and
    # padded with spaces if shorter than 4 characters.
    class Tag
      attr_reader :value

      # Initialize a new Tag
      #
      # @param value [String] Tag value (1-4 characters)
      # @raise [Fontisan::Error] If value is not a String
      def initialize(value)
        @value = normalize_tag(value)
      end

      # Convert tag to string
      #
      # @return [String] 4-character tag string
      def to_s
        @value
      end

      # Compare tag with another tag or string
      #
      # @param other [Tag, String] Object to compare with
      # @return [Boolean] True if tags are equal
      def ==(other)
        case other
        when Tag
          @value == other.value
        when String
          @value == normalize_tag(other)
        else
          false
        end
      end

      alias eql? ==

      # Generate hash for use as Hash key
      #
      # @return [Integer] Hash value
      def hash
        @value.hash
      end

      # Check if tag is valid (exactly 4 characters)
      #
      # @return [Boolean] True if tag is valid
      def valid?
        @value.length == 4
      end

      private

      # Normalize tag to 4 characters
      #
      # @param tag [String] Tag to normalize
      # @return [String] Normalized 4-character tag
      # @raise [Fontisan::Error] If tag is not a String
      def normalize_tag(tag)
        case tag
        when String
          tag = tag.slice(0, 4).ljust(4, " ")
        else
          raise Error, "Invalid tag: #{tag.inspect}"
        end
        tag
      end
    end
  end
end
