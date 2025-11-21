# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Ttx
      module Tables
        # HheaTable represents the 'hhea' table in TTX format
        #
        # Contains horizontal header information following the OpenType
        # specification for the hhea table.
        class HheaTable < Lutaml::Model::Serializable
          attribute :table_version, :string
          attribute :ascent, :integer
          attribute :descent, :integer
          attribute :line_gap, :integer
          attribute :advance_width_max, :integer
          attribute :min_left_side_bearing, :integer
          attribute :min_right_side_bearing, :integer
          attribute :x_max_extent, :integer
          attribute :caret_slope_rise, :integer
          attribute :caret_slope_run, :integer
          attribute :caret_offset, :integer
          attribute :reserved0, :integer, default: -> { 0 }
          attribute :reserved1, :integer, default: -> { 0 }
          attribute :reserved2, :integer, default: -> { 0 }
          attribute :reserved3, :integer, default: -> { 0 }
          attribute :metric_data_format, :integer
          attribute :number_of_h_metrics, :integer

          xml do
            root "hhea"

            map_element "tableVersion", to: :table_version,
                                        render_default: true
            map_element "ascent", to: :ascent,
                                  render_default: true
            map_element "descent", to: :descent,
                                   render_default: true
            map_element "lineGap", to: :line_gap,
                                   render_default: true
            map_element "advanceWidthMax", to: :advance_width_max,
                                           render_default: true
            map_element "minLeftSideBearing", to: :min_left_side_bearing,
                                              render_default: true
            map_element "minRightSideBearing", to: :min_right_side_bearing,
                                               render_default: true
            map_element "xMaxExtent", to: :x_max_extent,
                                      render_default: true
            map_element "caretSlopeRise", to: :caret_slope_rise,
                                          render_default: true
            map_element "caretSlopeRun", to: :caret_slope_run,
                                         render_default: true
            map_element "caretOffset", to: :caret_offset,
                                       render_default: true
            map_element "reserved0", to: :reserved0,
                                     render_default: true
            map_element "reserved1", to: :reserved1,
                                     render_default: true
            map_element "reserved2", to: :reserved2,
                                     render_default: true
            map_element "reserved3", to: :reserved3,
                                     render_default: true
            map_element "metricDataFormat", to: :metric_data_format,
                                            render_default: true
            map_element "numberOfHMetrics", to: :number_of_h_metrics,
                                            render_default: true
          end
        end
      end
    end
  end
end
