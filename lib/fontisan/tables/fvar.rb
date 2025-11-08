# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"

module Fontisan
  module Tables
    # BinData structure for variation axis record
    #
    # Each axis defines a design dimension along which the font can vary,
    # such as weight (wght), width (wdth), italic (ital), or slant (slnt).
    class VariationAxisRecord < Binary::BaseRecord
      string :axis_tag, length: 4
      int32 :min_value_raw
      int32 :default_value_raw
      int32 :max_value_raw
      uint16 :flags
      uint16 :axis_name_id

      # Convert minimum value from fixed-point to float
      #
      # @return [Float] Minimum value for this axis
      def min_value
        fixed_to_float(min_value_raw)
      end

      # Convert default value from fixed-point to float
      #
      # @return [Float] Default value for this axis
      def default_value
        fixed_to_float(default_value_raw)
      end

      # Convert maximum value from fixed-point to float
      #
      # @return [Float] Maximum value for this axis
      def max_value
        fixed_to_float(max_value_raw)
      end
    end

    # BinData structure for instance record
    #
    # Each instance defines a predefined combination of axis values,
    # representing a named style/weight/width combination.
    class InstanceRecord < Binary::BaseRecord
      uint16 :subfamily_name_id
      uint16 :flags
      # Coordinates are read based on axis_count from parent fvar table
      # This needs to be handled by the parent

      # Get the instance name ID
      #
      # @return [Integer] Name table ID for this instance
      def name_id
        subfamily_name_id
      end
    end

    # Parser for the 'fvar' (Font Variations) table
    #
    # The fvar table contains information about variation axes and named
    # instances for variable fonts. This table is present only in variable
    # fonts (OpenType Font Variations).
    #
    # Reference: OpenType specification, fvar table
    #
    # @example Reading an fvar table
    #   data = font.table_data("fvar")
    #   fvar = Fontisan::Tables::Fvar.read(data)
    #   fvar.axes.each do |axis|
    #     puts "#{axis.axis_tag}: #{axis.min_value} - #{axis.max_value}"
    #   end
    class Fvar < Binary::BaseRecord
      uint16 :major_version
      uint16 :minor_version
      uint16 :axes_array_offset
      uint16 :reserved
      uint16 :axis_count
      uint16 :axis_size
      uint16 :instance_count
      uint16 :instance_size

      # Parse variation axes from the table data
      #
      # @return [Array<VariationAxisRecord>] Array of axis records
      def axes
        return @axes if @axes
        return @axes = [] if axis_count.zero?

        # Get the full data buffer as binary string
        data = to_binary_s

        @axes = Array.new(axis_count) do |i|
          offset = axes_array_offset + (i * axis_size)
          axis_data = data.byteslice(offset, axis_size)
          VariationAxisRecord.read(axis_data)
        end
      end

      # Parse instance records from the table data
      #
      # @return [Array<Hash>] Array of instance information hashes
      def instances
        return @instances if @instances
        return @instances = [] if instance_count.zero?

        # Get the full data buffer as binary string
        data = to_binary_s

        # Calculate instance data offset (after all axes)
        instance_offset = axes_array_offset + (axis_count * axis_size)

        @instances = Array.new(instance_count) do |i|
          offset = instance_offset + (i * instance_size)

          # Check bounds
          next nil if offset + instance_size > data.bytesize

          instance_data = data.byteslice(offset, instance_size)
          next nil if instance_data.nil? || instance_data.empty?

          # Parse instance data manually
          io = StringIO.new(instance_data)
          io.set_encoding(Encoding::BINARY)

          # Read subfamily name ID and flags
          subfamily_name_id = io.read(2).unpack1("n")
          flags = io.read(2).unpack1("n")

          # Read coordinates for each axis (as int32 fixed-point values)
          coordinates = Array.new(axis_count) do
            fixed_to_float(io.read(4).unpack1("N"))
          end

          # Read optional postScriptNameID if present
          postscript_name_id = nil
          postscript_name_id = io.read(2).unpack1("n") if instance_size >= (4 + (axis_count * 4) + 2)

          {
            name_id: subfamily_name_id,
            flags: flags,
            coordinates: coordinates,
            postscript_name_id: postscript_name_id,
          }
        end.compact
      end

      # Get version as a float
      #
      # @return [Float] Version number (e.g., 1.0)
      def version
        major_version + (minor_version / 10.0)
      end
    end
  end
end
