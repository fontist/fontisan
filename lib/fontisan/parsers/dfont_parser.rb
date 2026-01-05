# frozen_string_literal: true

require "bindata"
require_relative "../error"

module Fontisan
  module Parsers
    # Parser for Apple dfont (Data Fork Font) resource fork format.
    #
    # dfont files store resource fork data in the data fork, containing
    # TrueType or OpenType SFNT data embedded in a resource fork structure.
    #
    # @example Extract SFNT from dfont
    #   File.open("font.dfont", "rb") do |io|
    #     sfnt_data = DfontParser.extract_sfnt(io)
    #     # sfnt_data is raw SFNT binary
    #   end
    class DfontParser
      # Resource fork header structure (16 bytes)
      class ResourceHeader < BinData::Record
        endian :big
        uint32 :resource_data_offset    # Offset to resource data section
        uint32 :resource_map_offset     # Offset to resource map
        uint32 :resource_data_length    # Length of resource data
        uint32 :resource_map_length     # Length of resource map
      end

      # Resource type entry in type list
      class ResourceType < BinData::Record
        endian :big
        string :type_code, length: 4        # Resource type (e.g., 'sfnt')
        uint16 :resource_count_minus_1      # Number of resources - 1
        uint16 :reference_list_offset       # Offset to reference list
      end

      # Resource reference in reference list
      class ResourceReference < BinData::Record
        endian :big
        uint16 :resource_id           # Resource ID
        int16 :name_offset            # Offset to name in name list (-1 if none)
        uint8 :attributes             # Resource attributes
        bit24 :data_offset            # Offset to data (relative to resource data section)
        uint32 :reserved              # Reserved (handle to resource in memory)
      end

      # Extract SFNT data from dfont file
      #
      # @param io [IO] Open file handle
      # @param index [Integer] Font index for multi-font suitcases (default: 0)
      # @return [String] Raw SFNT binary data
      # @raise [InvalidFontError] if not valid dfont or index out of range
      def self.extract_sfnt(io, index: 0)
        header = parse_header(io)
        sfnt_resources = find_sfnt_resources(io, header)

        if sfnt_resources.empty?
          raise InvalidFontError, "No sfnt resources found in dfont file"
        end

        if index >= sfnt_resources.length
          raise InvalidFontError,
                "Font index #{index} out of range (dfont has #{sfnt_resources.length} fonts)"
        end

        extract_resource_data(io, header, sfnt_resources[index])
      end

      # Count number of sfnt resources (fonts) in dfont
      #
      # @param io [IO] Open file handle
      # @return [Integer] Number of fonts
      def self.sfnt_count(io)
        header = parse_header(io)
        sfnt_resources = find_sfnt_resources(io, header)
        sfnt_resources.length
      end

      # Check if file is valid dfont resource fork
      #
      # @param io [IO] Open file handle
      # @return [Boolean]
      def self.dfont?(io)
        io.rewind
        header_bytes = io.read(16)
        io.rewind

        return false if header_bytes.nil? || header_bytes.length < 16

        # Basic sanity check on resource fork structure
        data_offset = header_bytes[0..3].unpack1("N")
        map_offset = header_bytes[4..7].unpack1("N")

        data_offset.positive? && map_offset > data_offset
      end

      # Parse resource fork header
      #
      # @param io [IO] Open file handle
      # @return [ResourceHeader] Parsed header
      # @raise [InvalidFontError] if header invalid
      # @api private
      def self.parse_header(io)
        io.rewind
        ResourceHeader.read(io)
      rescue BinData::ValidityError => e
        raise InvalidFontError, "Invalid dfont resource header: #{e.message}"
      end

      # Find all sfnt resources in resource map
      #
      # @param io [IO] Open file handle
      # @param header [ResourceHeader] Parsed header
      # @return [Array<Hash>] Array of resource info hashes with :id and :offset
      # @api private
      def self.find_sfnt_resources(io, header)
        # Seek to resource map
        io.seek(header.resource_map_offset)

        # Skip resource map header (22 bytes reserved + 4 bytes attributes + 2 bytes type list offset + 2 bytes name list offset)
        # The actual layout is:
        # - Bytes 0-15: Copy of resource header (16 bytes)
        # - Bytes 16-19: Reserved for handle to next resource map (4 bytes)
        # - Bytes 20-21: Reserved for file reference number (2 bytes)
        # - Bytes 22-23: Resource file attributes (2 bytes)
        # - Bytes 24-25: Offset to type list (2 bytes)
        # - Bytes 26-27: Offset to name list (2 bytes)
        io.seek(header.resource_map_offset + 24)

        # Read type list offset (relative to start of resource map)
        type_list_offset = io.read(2).unpack1("n")

        # Seek to type list
        io.seek(header.resource_map_offset + type_list_offset)

        # Read number of types minus 1
        type_count_minus_1 = io.read(2).unpack1("n")
        type_count = type_count_minus_1 + 1

        # Find 'sfnt' type in type list
        sfnt_type = nil
        type_count.times do
          type_entry = ResourceType.read(io)

          if type_entry.type_code == "sfnt"
            sfnt_type = type_entry
            break
          end
        end

        return [] unless sfnt_type

        # Read reference list for sfnt resources
        reference_list_offset = header.resource_map_offset + type_list_offset + sfnt_type.reference_list_offset
        io.seek(reference_list_offset)

        resource_count = sfnt_type.resource_count_minus_1 + 1
        resources = []

        resource_count.times do
          ref = ResourceReference.read(io)
          resources << { id: ref.resource_id, offset: ref.data_offset }
        end

        resources
      end

      # Extract resource data at specific offset
      #
      # @param io [IO] Open file handle
      # @param header [ResourceHeader] Parsed header
      # @param resource_info [Hash] Resource info with :offset
      # @return [String] Raw SFNT binary data
      # @api private
      def self.extract_resource_data(io, header, resource_info)
        # Calculate absolute offset to resource data
        # The offset in the reference is relative to the start of the resource data section
        data_offset = header.resource_data_offset + resource_info[:offset]

        io.seek(data_offset)

        # Read data length (first 4 bytes of resource data)
        data_length = io.read(4).unpack1("N")

        # Read the actual data
        io.read(data_length)
      end

      private_class_method :parse_header, :find_sfnt_resources,
                           :extract_resource_data
    end
  end
end
