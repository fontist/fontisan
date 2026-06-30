# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `STAT` (Style Attributes) table.
      #
      # Describes style attributes for each axis and named instances.
      # Required for proper font matching in operating systems.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/STAT
      module Stat
        HEADER_SIZE = 20
        DESIGN_AXIS_RECORD_SIZE = 8 # tag(4) + nameID(2) + ordering(2)
        AXIS_VALUE_OFFSET_SIZE = 4  # uint32 per axis value

        # @param axes [Array<Hash>] axis definitions with tag + name_id + ordering
        # @param axis_values [Array<Hash>] value records per axis
        # @param elided_name_id [Integer, nil] fallback name ID
        # @return [String] STAT table bytes
        def self.build(axes:, axis_values: nil, elided_name_id: nil)
          return nil if axes.nil? || axes.empty?

          design_axis_count = axes.size
          axis_value_list = axis_values || []
          axis_value_count = axis_value_list.size

          design_axes = serialize_design_axes(axes)
          value_tables, value_offsets = serialize_axis_values(axis_value_list, design_axes.bytesize)

          header = serialize_header(
            design_axis_count: design_axis_count,
            design_axes_size: design_axes.bytesize,
            axis_value_count: axis_value_count,
            elided_name_id: elided_name_id,
          )

          io = +""
          io << header
          io << design_axes
          axis_value_list.each_index do |i|
            io << [value_offsets[i]].pack("N")
          end
          io << value_tables
          io
        end

        def self.serialize_header(design_axis_count:, design_axes_size:, axis_value_count:, elided_name_id:)
          design_axes_offset = HEADER_SIZE
          offset_to_axis_value_offsets = design_axes_offset + design_axes_size

          [
            0x00010001, # version 1.1
            DESIGN_AXIS_RECORD_SIZE,
            design_axis_count,
            design_axes_offset,
            axis_value_count,
            offset_to_axis_value_offsets,
            elided_name_id || 0,
          ].pack("NnnNnNn")
        end

        def self.serialize_design_axes(axes)
          io = +""
          axes.each_with_index do |axis, i|
            tag = (axis[:tag] || axis["tag"] || "    ").to_s.ljust(4, " ")[0, 4]
            name_id = axis[:name_id] || axis["name_id"] || 0
            ordering = axis[:ordering] || axis["ordering"] || i
            io << tag
            io << [name_id, ordering].pack("nn")
          end
          io
        end

        # Each AxisValueTable is Format 1 (nominal): format(2) + axisIndex(2)
        # + flags(2) + valueNameID(2) + value(F2DOT14) = 10 bytes.
        def self.serialize_axis_values(axis_values, design_axes_size)
          value_tables = +""
          value_offsets = []
          base = HEADER_SIZE + design_axes_size + (axis_values.size * AXIS_VALUE_OFFSET_SIZE)

          axis_values.each do |av|
            value_offsets << (base + value_tables.bytesize)
            format = 1
            axis_idx = av[:axis_index] || av["axis_index"] || 0
            flags = av[:flags] || av["flags"] || 0
            name_id = av[:name_id] || av["name_id"] || 0
            value = f2dot14(av[:value] || av["value"] || 0)
            value_tables << [format, axis_idx, flags, name_id, value].pack("nnnnn")
          end

          [value_tables, value_offsets]
        end

        def self.f2dot14(value)
          (value.to_f * 16384).to_i.clamp(-16384, 16384)
        end
        private_class_method :serialize_header, :serialize_design_axes,
                             :serialize_axis_values, :f2dot14
      end
    end
  end
end
