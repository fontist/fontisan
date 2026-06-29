# frozen_string_literal: true

module Fontisan
  module Ufo
    # The collection of layers in a UFO source. The default layer is
    # always present and keyed by `"public.default"`.
    class LayerSet
      attr_reader :layers

      def initialize
        @layers = { Layer::DEFAULT_NAME => Layer.new }
      end

      def default_layer
        @layers[Layer::DEFAULT_NAME]
      end

      def [](name)
        @layers[name.to_s]
      end

      def add(name)
        name = name.to_s
        @layers[name] ||= Layer.new(name)
        @layers[name]
      end

      def each(&)
        @layers.each_value(&)
      end

      def size
        @layers.size
      end
    end
  end
end
