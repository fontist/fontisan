# frozen_string_literal: true

require "bindata"
require_relative "constants"
require_relative "utilities/checksum_calculator"

module Fontisan
  # OpenType Font domain object using BinData
  #
  # Represents a complete OpenType Font file (CFF outlines) using BinData's declarative
  # DSL for binary structure definition. Parallel to TrueTypeFont but for CFF format.
  #
  # @example Reading and analyzing a font
  #   otf = OpenTypeFont.from_file("font.otf")
  #   puts otf.header.num_tables  # => 12
  #   name_table = otf.table("name")
  #   puts name_table.english_name(Tables::Name::FAMILY)
  #
  # @example Writing a font
  #   otf.to_file("output.otf")
  class OpenTypeFont < BinData::Record
    endian :big

    offset_table :header
    array :tables, type: :table_directory, initial_length: lambda {
      header.num_tables
    }

    # Table data is stored separately since it's at variable offsets
    attr_accessor :table_data

    # Parsed table instances cache
    attr_accessor :parsed_tables

    # Read OpenType Font from a file
    #
    # @param path [String] Path to the OTF file
    # @return [OpenTypeFont] A new instance
    # @raise [ArgumentError] if path is nil or empty
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [RuntimeError] if file format is invalid
    def self.from_file(path)
      if path.nil? || path.to_s.empty?
        raise ArgumentError,
              "path cannot be nil or empty"
      end
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      File.open(path, "rb") do |io|
        font = read(io)
        font.initialize_storage
        font.read_table_data(io)
        font
      end
    rescue BinData::ValidityError, EOFError => e
      raise "Invalid OTF file: #{e.message}"
    end

    # Read OpenType Font from collection at specific offset
    #
    # @param io [IO] Open file handle
    # @param offset [Integer] Byte offset to the font
    # @return [OpenTypeFont] A new instance
    def self.from_collection(io, offset)
      io.seek(offset)
      font = read(io)
      font.initialize_storage
      font.read_table_data(io)
      font
    end

    # Initialize storage hashes
    #
    # @return [void]
    def initialize_storage
      @table_data = {}
      @parsed_tables = {}
    end

    # Read table data for all tables
    #
    # @param io [IO] Open file handle
    # @return [void]
    def read_table_data(io)
      @table_data = {}
      tables.each do |entry|
        io.seek(entry.offset)
        # Force UTF-8 encoding on tag for hash key consistency
        tag_key = entry.tag.dup.force_encoding("UTF-8")
        @table_data[tag_key] = io.read(entry.table_length)
      end
    end

    # Write OpenType Font to a file
    #
    # Writes the complete OTF structure to disk, including proper checksum
    # calculation and table alignment.
    #
    # @param path [String] Path where the OTF file will be written
    # @return [Integer] Number of bytes written
    # @raise [IOError] if writing fails
    def to_file(path)
      File.open(path, "wb") do |io|
        # Write header and tables (directory)
        write_structure(io)

        # Write table data with updated offsets
        write_table_data_with_offsets(io)

        io.pos
      end

      # Update checksum adjustment in head table
      update_checksum_adjustment_in_file(path) if head_table

      File.size(path)
    end

    # Validate format correctness
    #
    # @return [Boolean] true if the OTF format is valid, false otherwise
    def valid?
      return false unless header
      return false unless tables.respond_to?(:length)
      return false unless @table_data.is_a?(Hash)
      return false if tables.length != header.num_tables
      return false unless head_table
      return false unless has_table?(Constants::CFF_TAG)

      true
    end

    # Check if font has a specific table
    #
    # @param tag [String] The table tag to check for
    # @return [Boolean] true if table exists, false otherwise
    def has_table?(tag)
      tables.any? { |entry| entry.tag == tag }
    end

    # Find a table entry by tag
    #
    # @param tag [String] The table tag to find
    # @return [TableDirectory, nil] The table entry or nil
    def find_table_entry(tag)
      tables.find { |entry| entry.tag == tag }
    end

    # Get the head table entry
    #
    # @return [TableDirectory, nil] The head table entry or nil
    def head_table
      find_table_entry(Constants::HEAD_TAG)
    end

    # Get list of all table tags
    #
    # @return [Array<String>] Array of table tag strings
    def table_names
      tables.map(&:tag)
    end

    # Get parsed table instance
    #
    # This method parses the raw table data into a structured table object
    # and caches the result for subsequent calls.
    #
    # @param tag [String] The table tag to retrieve
    # @return [Tables::*, nil] Parsed table object or nil if not found
    def table(tag)
      @parsed_tables[tag] ||= parse_table(tag)
    end

    # Get units per em from head table
    #
    # @return [Integer, nil] Units per em value
    def units_per_em
      head = table(Constants::HEAD_TAG)
      head&.units_per_em
    end

    private

    # Parse a table from raw data
    #
    # @param tag [String] The table tag to parse
    # @return [Tables::*, nil] Parsed table object or nil
    def parse_table(tag)
      raw_data = @table_data[tag]
      return nil unless raw_data

      table_class = table_class_for(tag)
      return nil unless table_class

      table_class.read(raw_data)
    end

    # Map table tag to parser class
    #
    # @param tag [String] The table tag
    # @return [Class, nil] Table parser class or nil
    def table_class_for(tag)
      {
        Constants::HEAD_TAG => Tables::Head,
        Constants::NAME_TAG => Tables::Name,
        Constants::OS2_TAG => Tables::Os2,
        Constants::POST_TAG => Tables::Post,
        Constants::CMAP_TAG => Tables::Cmap,
        Constants::FVAR_TAG => Tables::Fvar,
        Constants::GSUB_TAG => Tables::Gsub,
        Constants::GPOS_TAG => Tables::Gpos,
      }[tag]
    end

    # Write the structure (header + table directory) to IO
    #
    # @param io [IO] Open file handle
    # @return [void]
    def write_structure(io)
      # Write header
      header.write(io)

      # Write table directory with placeholder offsets
      tables.each do |entry|
        io.write(entry.tag)
        io.write([entry.checksum].pack("N"))
        io.write([0].pack("N")) # Placeholder offset
        io.write([entry.table_length].pack("N"))
      end
    end

    # Write table data and update offsets in directory
    #
    # @param io [IO] Open file handle
    # @return [void]
    def write_table_data_with_offsets(io)
      tables.each_with_index do |entry, index|
        # Record current position
        current_position = io.pos

        # Write table data
        data = @table_data[entry.tag]
        raise IOError, "Missing table data for tag '#{entry.tag}'" if data.nil?

        io.write(data)

        # Add padding to align to 4-byte boundary
        padding = (Constants::TABLE_ALIGNMENT - (io.pos % Constants::TABLE_ALIGNMENT)) % Constants::TABLE_ALIGNMENT
        io.write("\x00" * padding) if padding.positive?

        # Zero out checksumAdjustment field in head table
        if entry.tag == Constants::HEAD_TAG
          current_pos = io.pos
          io.seek(current_position + 8)
          io.write([0].pack("N"))
          io.seek(current_pos)
        end

        # Update offset in table directory
        # Table directory starts at byte 12, each entry is 16 bytes
        # Offset field is at byte 8 within each entry
        directory_offset_position = 12 + (index * 16) + 8
        current_pos = io.pos
        io.seek(directory_offset_position)
        io.write([current_position].pack("N"))
        io.seek(current_pos)
      end
    end

    # Update checksumAdjustment field in head table
    #
    # @param path [String] Path to the OTF file
    # @return [void]
    def update_checksum_adjustment_in_file(path)
      # Calculate file checksum
      checksum = Utilities::ChecksumCalculator.calculate_file_checksum(path)

      # Calculate adjustment
      adjustment = Utilities::ChecksumCalculator.calculate_adjustment(checksum)

      # Find head table position
      head_entry = head_table
      return unless head_entry

      # Write adjustment to head table (offset 8 within head table)
      File.open(path, "r+b") do |io|
        io.seek(head_entry.offset + 8)
        io.write([adjustment].pack("N"))
      end
    end
  end
end
