# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Ttx
      module Tables
        # PostTable represents the 'post' table in TTX format
        #
        # Contains PostScript information following the OpenType
        # specification for the post table.
        class PostTable < Lutaml::Model::Serializable
          attribute :format_type, :float
          attribute :italic_angle, :float
          attribute :underline_position, :integer
          attribute :underline_thickness, :integer
          attribute :is_fixed_pitch, :integer
          attribute :min_mem_type42, :integer
          attribute :max_mem_type42, :integer
          attribute :min_mem_type1, :integer
          attribute :max_mem_type1, :integer

          xml do
            root "post"

            map_element "formatType", to: :format_type,
                                      render_default: true
            map_element "italicAngle", to: :italic_angle,
                                       render_default: true
            map_element "underlinePosition", to: :underline_position,
                                             render_default: true
            map_element "underlineThickness", to: :underline_thickness,
                                              render_default: true
            map_element "isFixedPitch", to: :is_fixed_pitch,
                                        render_default: true
            map_element "minMemType42", to: :min_mem_type42,
                                        render_default: true
            map_element "maxMemType42", to: :max_mem_type42,
                                        render_default: true
            map_element "minMemType1", to: :min_mem_type1,
                                       render_default: true
            map_element "maxMemType1", to: :max_mem_type1,
                                       render_default: true
          end
        end
      end
    end
  end
end
