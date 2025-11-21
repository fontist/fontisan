# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Ttx
      module Tables
        # HeadTable represents the 'head' table in TTX format
        #
        # Contains global font metrics and metadata following the OpenType
        # specification for the head table.
        class HeadTable < Lutaml::Model::Serializable
          attribute :table_version, :float
          attribute :font_revision, :float
          attribute :checksum_adjustment, :integer
          attribute :magic_number, :integer
          attribute :flags, :integer
          attribute :units_per_em, :integer
          attribute :created, :string
          attribute :modified, :string
          attribute :x_min, :integer
          attribute :y_min, :integer
          attribute :x_max, :integer
          attribute :y_max, :integer
          attribute :mac_style, :string
          attribute :lowest_rec_ppem, :integer
          attribute :font_direction_hint, :integer
          attribute :index_to_loc_format, :integer
          attribute :glyph_data_format, :integer

          xml do
            root "head"

            map_element "tableVersion", to: :table_version,
                                        render_default: true
            map_element "fontRevision", to: :font_revision,
                                        render_default: true
            map_element "checkSumAdjustment", to: :checksum_adjustment,
                                              render_default: true
            map_element "magicNumber", to: :magic_number,
                                       render_default: true
            map_element "flags", to: :flags,
                                 render_default: true
            map_element "unitsPerEm", to: :units_per_em,
                                      render_default: true
            map_element "created", to: :created,
                                   render_default: true
            map_element "modified", to: :modified,
                                    render_default: true
            map_element "xMin", to: :x_min,
                                render_default: true
            map_element "yMin", to: :y_min,
                                render_default: true
            map_element "xMax", to: :x_max,
                                render_default: true
            map_element "yMax", to: :y_max,
                                render_default: true
            map_element "macStyle", to: :mac_style,
                                    render_default: true
            map_element "lowestRecPPEM", to: :lowest_rec_ppem,
                                         render_default: true
            map_element "fontDirectionHint", to: :font_direction_hint,
                                             render_default: true
            map_element "indexToLocFormat", to: :index_to_loc_format,
                                            render_default: true
            map_element "glyphDataFormat", to: :glyph_data_format,
                                           render_default: true
          end
        end
      end
    end
  end
end
