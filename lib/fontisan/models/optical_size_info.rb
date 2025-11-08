# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # OpticalSizeInfo model represents optical size information from a font
    #
    # Optical size information indicates the design size range for which a font
    # is optimized. This can come from the OS/2 table (version 5+) or from the
    # GPOS 'size' feature.
    class OpticalSizeInfo < Lutaml::Model::Serializable
      attribute :has_optical_size, Lutaml::Model::Type::Boolean
      attribute :source, :string
      attribute :lower_point_size, :float
      attribute :upper_point_size, :float

      json do
        map "has_optical_size", to: :has_optical_size
        map "source", to: :source
        map "lower_point_size", to: :lower_point_size
        map "upper_point_size", to: :upper_point_size
      end

      yaml do
        map "has_optical_size", to: :has_optical_size
        map "source", to: :source
        map "lower_point_size", to: :lower_point_size
        map "upper_point_size", to: :upper_point_size
      end
    end
  end
end
