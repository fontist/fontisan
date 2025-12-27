# frozen_string_literal: true

require_relative "base_strategy"
require_relative "instance_strategy"
require_relative "../../variation/variation_context"

module Fontisan
  module Pipeline
    module Strategies
      # Strategy for generating instances from named instances
      #
      # This strategy creates a static font instance using coordinates from
      # a named instance defined in the fvar table. It extracts the coordinates
      # from the specified instance and delegates to InstanceStrategy for
      # actual generation.
      #
      # Named instances are predefined design space coordinates stored in the
      # fvar table, typically representing common styles like "Bold", "Light",
      # "Condensed", etc.
      #
      # @example Generate "Bold" instance
      #   strategy = NamedStrategy.new(instance_index: 0)
      #   tables = strategy.resolve(variable_font)
      #
      # @example Use specific named instance
      #   # Find instance by name first, then use index
      #   fvar = font.table("fvar")
      #   bold_index = fvar.instances.find_index { |i| i[:name] =~ /Bold/ }
      #   strategy = NamedStrategy.new(instance_index: bold_index)
      #   tables = strategy.resolve(variable_font)
      class NamedStrategy < BaseStrategy
        # @return [Integer] Named instance index
        attr_reader :instance_index

        # Initialize strategy with instance index
        #
        # @param options [Hash] Strategy options
        # @option options [Integer] :instance_index Index of named instance in fvar
        # @raise [ArgumentError] If instance_index not provided
        def initialize(options = {})
          super
          @instance_index = options[:instance_index]

          if @instance_index.nil?
            raise ArgumentError, "instance_index is required for NamedStrategy"
          end
        end

        # Resolve by using named instance coordinates
        #
        # Extracts coordinates from the fvar table's named instance and
        # delegates to InstanceStrategy for actual instance generation.
        #
        # @param font [TrueTypeFont, OpenTypeFont] Variable font
        # @return [Hash<String, String>] Static font tables
        # @raise [ArgumentError] If instance index is invalid
        def resolve(font)
          # Extract coordinates from named instance
          coordinates = extract_coordinates(font)

          # Use InstanceStrategy to generate instance
          instance_strategy = InstanceStrategy.new(coordinates: coordinates)
          instance_strategy.resolve(font)
        end

        # Check if strategy preserves variation data
        #
        # @return [Boolean] Always false for this strategy
        def preserves_variation?
          false
        end

        # Get strategy name
        #
        # @return [Symbol] :named
        def strategy_name
          :named
        end

        private

        # Extract coordinates from named instance in fvar table
        #
        # @param font [TrueTypeFont, OpenTypeFont] Variable font
        # @return [Hash<String, Float>] Design space coordinates
        # @raise [ArgumentError] If instance index is invalid
        def extract_coordinates(font)
          context = Variation::VariationContext.new(font)

          unless context.fvar
            raise ArgumentError, "Font is not a variable font (no fvar table)"
          end

          instances = context.fvar.instances
          if @instance_index.negative? || @instance_index >= instances.length
            raise ArgumentError,
                  "Invalid instance index #{@instance_index}. " \
                  "Font has #{instances.length} named instances."
          end

          instance = instances[@instance_index]
          axes = context.axes

          # Map instance coordinates to axis tags
          coordinates = {}
          instance[:coordinates].each_with_index do |value, i|
            next if i >= axes.length

            axis = axes[i]
            coordinates[axis.axis_tag] = value
          end

          coordinates
        end
      end
    end
  end
end
