# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Layout-critical metrics for a face, consolidated from head, hhea,
      # OS/2, and post tables. Designers and engineers can read all
      # spacing-relevant numbers in one place instead of cross-referencing
      # raw table dumps.
      #
      # All fields are nil-safe — Type 1 fonts and stripped WOFF builds
      # may not carry every table. Derived booleans (e.g. metrics_consistent?)
      # tolerate nil inputs and return false rather than raising.
      class Metrics < Lutaml::Model::Serializable
        # head
        attribute :units_per_em, :integer
        attribute :bbox_x_min,   :integer
        attribute :bbox_y_min,   :integer
        attribute :bbox_x_max,   :integer
        attribute :bbox_y_max,   :integer

        # hhea (horizontal)
        attribute :hhea_ascent,  :integer
        attribute :hhea_descent, :integer
        attribute :hhea_line_gap, :integer

        # OS/2 typo
        attribute :typo_ascender, :integer
        attribute :typo_descender, :integer
        attribute :typo_line_gap, :integer

        # OS/2 win
        attribute :win_ascent,  :integer
        attribute :win_descent, :integer

        # OS/2 v2+ (optional)
        attribute :x_height,   :integer
        attribute :cap_height, :integer

        # OS/2 subscript/superscript
        attribute :subscript_x_size,    :integer
        attribute :subscript_y_size,    :integer
        attribute :subscript_x_offset,  :integer
        attribute :subscript_y_offset,  :integer
        attribute :superscript_x_size,    :integer
        attribute :superscript_y_size,    :integer
        attribute :superscript_x_offset,  :integer
        attribute :superscript_y_offset,  :integer

        # OS/2 strikeout
        attribute :strikeout_size,     :integer
        attribute :strikeout_position, :integer

        # post underline
        attribute :underline_position,  :float
        attribute :underline_thickness, :float

        key_value do
          map "units_per_em",     to: :units_per_em
          map "bbox_x_min",       to: :bbox_x_min
          map "bbox_y_min",       to: :bbox_y_min
          map "bbox_x_max",       to: :bbox_x_max
          map "bbox_y_max",       to: :bbox_y_max

          map "hhea_ascent",   to: :hhea_ascent
          map "hhea_descent",  to: :hhea_descent
          map "hhea_line_gap", to: :hhea_line_gap

          map "typo_ascender",  to: :typo_ascender
          map "typo_descender", to: :typo_descender
          map "typo_line_gap",  to: :typo_line_gap

          map "win_ascent",  to: :win_ascent
          map "win_descent", to: :win_descent

          map "x_height",   to: :x_height
          map "cap_height", to: :cap_height

          map "subscript_x_size",   to: :subscript_x_size
          map "subscript_y_size",   to: :subscript_y_size
          map "subscript_x_offset", to: :subscript_x_offset
          map "subscript_y_offset", to: :subscript_y_offset
          map "superscript_x_size",   to: :superscript_x_size
          map "superscript_y_size",   to: :superscript_y_size
          map "superscript_x_offset", to: :superscript_x_offset
          map "superscript_y_offset", to: :superscript_y_offset

          map "strikeout_size",     to: :strikeout_size
          map "strikeout_position", to: :strikeout_position

          map "underline_position",  to: :underline_position
          map "underline_thickness", to: :underline_thickness
        end

        # True when hhea ascent/descent match OS/2 typo ascent/descent.
        # Mismatch is a common font bug that causes inconsistent line
        # height across platforms.
        #
        # @return [Boolean]
        def metrics_consistent?
          return false if hhea_ascent.nil? || typo_ascender.nil?
          return false if hhea_descent.nil? || typo_descender.nil?

          hhea_ascent == typo_ascender && hhea_descent == typo_descender
        end
      end
    end
  end
end
