# frozen_string_literal: true

module Fontisan
  module Ufo
    # Custom font-wide data from `lib.plist`. Generic key/value store.
    # Not used by standard UFO compilation, but downstream tools may
    # read it.
    class Lib
      attr_reader :data

      def initialize(values = {})
        @data = values
      end

      def [](key)
        @data[key.to_s]
      end

      def []=(key, value)
        @data[key.to_s] = value
      end
    end
  end
end
