# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `fvar` (Font Variations) table from a
      # list of axis definitions and named instances.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/fvar
      module Fvar
        VERSION_MAJOR = 1
        VERSION_MINOR = 0
        AXIS_SIZE = 20
        INSTANCE_SIZE = 4 # + 4 per axis
        FIXED_SHIFT = 16
        FIXED_ONE = 1 << FIXED_SHIFT

        # @param font [Fontisan::Ufo::Font]
        # @param axes [Array<Hash>] axis definitions
        # @param instances [Array<Hash>] named instance definitions
        # @return [String, nil] fvar table bytes, or nil if no axes
        def self.build(font, axes: nil, instances: nil)
          axes ||= font.info.respond_to?(:axes) ? font.info.axes : nil
          instances ||= font.info.respond_to?(:named_instances) ? font.info.named_instances : nil

          axes ||= []
          return nil if axes.empty?

          axes_bytes = build_axes(axes)
          instances_bytes = build_instances(instances || [], axes.size)
          header = build_header(axes.size, axes_bytes, instances_bytes, instances)
          header + axes_bytes + instances_bytes
        end

        # ---------- header ----------

        # Header is 16 bytes:
        #   majorVersion (2) + minorVersion (2) + axesArrayOffset (2)
        #   + reserved (2) + axisCount (2) + axisSize (2)
        #   + instanceCount (2) + instanceSize (2)
        def self.build_header(axis_count, axes_bytes, _instances_bytes, instances)
          axes_offset = 16
          axes_offset + axes_bytes.bytesize

          [
            VERSION_MAJOR,
            VERSION_MINOR,
            axes_offset,
            0, # reserved
            axis_count,
            AXIS_SIZE,
            instances&.size || 0,
            (instances&.size || 0).zero? ? 0 : (INSTANCE_SIZE + axis_count * 4),
          ].pack("nnnnnnnn")
        end

        # ---------- axes ----------

        # Each axis record is 20 bytes:
        #   axisTag (4) + minValue (4) + defaultValue (4) + maxValue (4)
        #   + flags (2) + axisNameID (2)
        def self.build_axes(axes)
          io = +""
          axes.each do |axis|
            tag = (axis[:tag] || axis["tag"] || "wght").to_s.ljust(4, " ")[0, 4]
            min = fixed_value(axis[:min] || axis["min"] || 100)
            default = fixed_value(axis[:default] || axis["default"] || 400)
            max = fixed_value(axis[:max] || axis["max"] || 900)
            flags = axis[:flags] || axis["flags"] || 0
            name_id = axis[:name_id] || axis["name_id"] || 0

            io << tag
            io << [min, default, max, flags, name_id].pack("NNNnn")
          end
          io
        end

        # ---------- instances ----------

        # Each instance record: subfamilyNameID (2) + flags (2) + per-axis coords
        def self.build_instances(instances, axis_count)
          return +"" if instances.empty?

          io = +""
          instances.each do |inst|
            name_id = inst[:name_id] || inst["name_id"] || 0
            flags = inst[:flags] || inst["flags"] || 0
            coords = inst[:coords] || inst["coords"] || []
            padded = coords.first(axis_count) + Array.new([axis_count - coords.size, 0].max, 0)
            padded = padded.first(axis_count).map { |c| fixed_value(c) }

            io << [name_id, flags].pack("nn")
            io << padded.pack("N*")
          end
          io
        end

        # ---------- helpers ----------

        # Convert a float to OpenType Fixed 16.16 (int32).
        def self.fixed_value(value)
          (value.to_f * FIXED_ONE).to_i
        end
        private_class_method :build_header, :build_axes, :build_instances,
                             :fixed_value
      end
    end
  end
end
