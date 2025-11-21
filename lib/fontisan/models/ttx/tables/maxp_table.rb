# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Ttx
      module Tables
        # MaxpTable represents the 'maxp' table in TTX format
        #
        # Contains maximum profile information following the OpenType
        # specification for the maxp table.
        class MaxpTable < Lutaml::Model::Serializable
          attribute :table_version, :string
          attribute :num_glyphs, :integer
          attribute :max_points, :integer
          attribute :max_contours, :integer
          attribute :max_composite_points, :integer
          attribute :max_composite_contours, :integer
          attribute :max_zones, :integer
          attribute :max_twilight_points, :integer
          attribute :max_storage, :integer
          attribute :max_function_defs, :integer
          attribute :max_instruction_defs, :integer
          attribute :max_stack_elements, :integer
          attribute :max_size_of_instructions, :integer
          attribute :max_component_elements, :integer
          attribute :max_component_depth, :integer

          xml do
            root "maxp"

            map_element "tableVersion", to: :table_version,
                                        render_default: true
            map_element "numGlyphs", to: :num_glyphs,
                                     render_default: true
            map_element "maxPoints", to: :max_points
            map_element "maxContours", to: :max_contours
            map_element "maxCompositePoints", to: :max_composite_points
            map_element "maxCompositeContours", to: :max_composite_contours
            map_element "maxZones", to: :max_zones
            map_element "maxTwilightPoints", to: :max_twilight_points
            map_element "maxStorage", to: :max_storage
            map_element "maxFunctionDefs", to: :max_function_defs
            map_element "maxInstructionDefs", to: :max_instruction_defs
            map_element "maxStackElements", to: :max_stack_elements
            map_element "maxSizeOfInstructions", to: :max_size_of_instructions
            map_element "maxComponentElements", to: :max_component_elements
            map_element "maxComponentDepth", to: :max_component_depth
          end
        end
      end
    end
  end
end
