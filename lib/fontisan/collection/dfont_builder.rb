# frozen_string_literal: true

require_relative "../font_writer"
require_relative "../error"
require_relative "../validation/collection_validator"

module Fontisan
  module Collection
    # DfontBuilder creates Apple dfont (Data Fork Font) resource fork structures
    #
    # Main responsibility: Build complete dfont binary from multiple fonts
    # by creating a resource fork structure containing 'sfnt' resources.
    #
    # dfont is an Apple-specific format that stores Mac font suitcase resources
    # in the data fork instead of the resource fork. It can contain multiple fonts.
    #
    # @example Build dfont from multiple fonts
    #   builder = DfontBuilder.new([font1, font2, font3])
    #   binary = builder.build
    #
    # @example Write directly to file
    #   builder = DfontBuilder.new([font1, font2])
    #   builder.build_to_file("family.dfont")
    class DfontBuilder
      # Source fonts
      # @return [Array<TrueTypeFont, OpenTypeFont>]
      attr_reader :fonts

      # Build result (populated after build)
      # @return [Hash, nil]
      attr_reader :result

      # Constants for resource reference packing
      NO_NAME_OFFSET = [-1].freeze
      ZERO_ATTRIBUTES = [0].freeze
      ZERO_RESERVED = [0].freeze

      # Initialize builder with fonts
      #
      # @param fonts [Array<TrueTypeFont, OpenTypeFont>] Fonts to pack into dfont
      # @param options [Hash] Builder options
      # @raise [ArgumentError] if fonts array is invalid
      def initialize(fonts, options = {})
        if fonts.nil? || fonts.empty?
          raise ArgumentError, "fonts cannot be nil or empty"
        end
        raise ArgumentError, "fonts must be an array" unless fonts.is_a?(Array)

        unless fonts.all? { |f| f.respond_to?(:table_data) }
          raise ArgumentError, "all fonts must respond to table_data"
        end

        @fonts = fonts
        @options = options
        @result = nil

        validate_fonts!
      end

      # Build dfont and return binary
      #
      # Executes the complete dfont creation process:
      # 1. Serialize each font to SFNT binary
      # 2. Build resource data section
      # 3. Calculate resource map size
      # 4. Build resource map
      # 5. Build resource fork header
      # 6. Assemble complete dfont binary
      #
      # @return [Hash] Build result with:
      #   - :binary [String] - Complete dfont binary
      #   - :num_fonts [Integer] - Number of fonts packed
      #   - :total_size [Integer] - Total size in bytes
      def build
        # Step 1: Serialize all fonts to SFNT binaries
        sfnt_binaries = serialize_fonts

        # Step 2: Build resource data section
        resource_data = build_resource_data(sfnt_binaries)

        # Step 3: Calculate expected resource map size
        # Map header: 28 bytes
        # Type list header: 2 bytes
        # Type entry: 8 bytes
        # References: 12 bytes each
        map_size = 28 + 2 + 8 + (sfnt_binaries.size * 12)

        # Step 4: Build resource map
        resource_map = build_resource_map(sfnt_binaries,
                                          resource_data.bytesize, map_size)

        # Step 5: Build header
        header = build_header(resource_data.bytesize, resource_map.bytesize)

        # Step 6: Assemble complete dfont binary
        binary = header + resource_data + resource_map

        # Store result
        @result = {
          binary: binary,
          num_fonts: @fonts.size,
          total_size: binary.bytesize,
          format: :dfont,
        }

        @result
      end

      # Build dfont and write to file
      #
      # @param path [String] Output file path
      # @return [Hash] Build result (same as build method)
      def build_to_file(path)
        result = build
        File.binwrite(path, result[:binary])
        result[:output_path] = path
        result
      end

      private

      # Validate fonts can be packed into dfont
      #
      # @return [void]
      # @raise [Error] if validation fails
      def validate_fonts!
        validator = Validation::CollectionValidator.new
        validator.validate!(@fonts, :dfont)
      end

      # Check if font is a web font
      #
      # @param font [Object] Font object
      # @return [Boolean] true if WOFF or WOFF2
      def web_font?(font)
        font.class.name.include?("Woff")
      end

      # Serialize all fonts to SFNT binaries
      #
      # @return [Array<String>] Array of SFNT binaries
      def serialize_fonts
        @fonts.map do |font|
          # Get all table data from font
          tables_hash = font.table_data

          # Determine sfnt version from font
          sfnt_version = detect_sfnt_version(font)

          # Write font to binary using FontWriter
          FontWriter.write_font(tables_hash, sfnt_version: sfnt_version)
        end
      end

      # Detect sfnt version from font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font object
      # @return [Integer] sfnt version
      def detect_sfnt_version(font)
        if font.respond_to?(:header) && font.header.respond_to?(:sfnt_version)
          font.header.sfnt_version
        elsif font.respond_to?(:table_data)
          # Auto-detect from tables
          FontWriter.detect_sfnt_version(font.table_data)
        else
          0x00010000 # Default to TrueType
        end
      end

      # Build resource fork header (16 bytes)
      #
      # @param data_length [Integer] Length of resource data section
      # @param map_length [Integer] Length of resource map section
      # @return [String] Binary header
      def build_header(data_length, map_length)
        # Resource fork header structure:
        # - resource_data_offset (4 bytes): always 256 (0x100) for dfont
        # - resource_map_offset (4 bytes): header_size + data_length
        # - resource_data_length (4 bytes)
        # - resource_map_length (4 bytes)

        data_offset = 256 # Standard dfont offset (conceptual, points to useful data)
        header_size = 16  # Actual header size in file
        map_offset = header_size + data_length # Map comes after header + data

        [
          data_offset,
          map_offset,
          data_length,
          map_length,
        ].pack("N4")
      end

      # Build resource data section
      #
      # Contains all SFNT resources with 4-byte length prefix for each.
      #
      # @param sfnt_binaries [Array<String>] SFNT binaries
      # @return [String] Resource data section binary
      def build_resource_data(sfnt_binaries)
        data = String.new(encoding: Encoding::BINARY)

        # Add padding to reach offset 256 (header is 16 bytes, pad 240 bytes)
        data << ("\0" * 240)

        # Write each SFNT resource with length prefix
        sfnt_binaries.each do |sfnt|
          # 4-byte length prefix (big-endian)
          data << [sfnt.bytesize].pack("N")
          # SFNT data
          data << sfnt
        end

        data
      end

      # Build resource map section
      #
      # Contains type list and reference list for all 'sfnt' resources.
      #
      # @param sfnt_binaries [Array<String>] SFNT binaries for offset calculation
      # @param data_length [Integer] Actual resource data section length
      # @param map_length [Integer] Actual resource map section length
      # @return [String] Resource map section binary
      def build_resource_map(sfnt_binaries, data_length, map_length)
        map = String.new(encoding: Encoding::BINARY)

        # Calculate offsets for header copy (must match main header)
        data_offset = 256 # Standard dfont offset (conceptual)
        header_size = 16 # Actual header size in file
        map_offset = header_size + data_length # Map comes after header + data

        # Resource map header (28 bytes):
        # - Copy of resource header (16 bytes)
        # - Handle to next resource map (4 bytes) - set to 0
        # - File reference number (2 bytes) - set to 0
        # - Resource file attributes (2 bytes) - set to 0
        # - Offset to type list (2 bytes) - set to 28
        # - Offset to name list (2 bytes) - calculated later

        # Copy of resource header (must match main header exactly)
        map << [data_offset, map_offset, data_length, map_length].pack("N4")

        # Reserved fields
        map << [0, 0, 0].pack("N n n")

        # Offset to type list (from start of map)
        map << [28].pack("n")

        # Offset to name list (we don't use names, so point past all data)
        type_list_size = 2 + 8 + (sfnt_binaries.size * 12) # type count + type entry + references
        name_list_offset = 28 + type_list_size
        map << [name_list_offset].pack("n")

        # Type list:
        # - Number of types - 1 (2 bytes) - we have 1 type ('sfnt')
        # - Type entries (8 bytes each)
        map << [0].pack("n") # 1 type - 1 = 0

        # Type entry for 'sfnt':
        # - Resource type (4 bytes): 'sfnt'
        # - Number of resources - 1 (2 bytes)
        # - Offset to reference list (2 bytes): from start of type list
        map << "sfnt"
        map << [sfnt_binaries.size - 1].pack("n")
        reference_list_offset = 2 + 8 # After type count and type entry
        map << [reference_list_offset].pack("n")

        # Build reference list
        map << build_reference_list(sfnt_binaries)

        map
      end

      # Build reference list for 'sfnt' resources
      #
      # @param sfnt_binaries [Array<String>] SFNT binaries
      # @return [String] Reference list binary
      def build_reference_list(sfnt_binaries)
        refs = String.new(encoding: Encoding::BINARY)

        # Calculate offset for each resource in data section
        # Offsets are relative to the start of the resource data section (not including padding)
        # The resource_data_offset in header points to where resources actually start
        current_offset = 0

        sfnt_binaries.each_with_index do |sfnt, i|
          # Resource reference (12 bytes):
          # - Resource ID (2 bytes): start from 128
          # - Name offset (2 bytes): -1 (no name)
          # - Attributes (1 byte): 0
          # - Data offset (3 bytes): offset in data section (24-bit big-endian)
          # - Reserved (4 bytes): 0

          resource_id = 128 + i
          refs << [resource_id].pack("n")
          refs << NO_NAME_OFFSET.pack("n") # No name
          refs << ZERO_ATTRIBUTES.pack("C") # Attributes

          # Pack 24-bit offset (3 bytes big-endian)
          # Offset is from start of resource data section
          offset_bytes = [current_offset].pack("N")[1..3]
          refs << offset_bytes

          refs << ZERO_RESERVED.pack("N") # Reserved

          # Update offset for next resource
          # Each resource has: 4-byte length + SFNT data
          current_offset += 4 + sfnt.bytesize
        end

        refs
      end
    end
  end
end
