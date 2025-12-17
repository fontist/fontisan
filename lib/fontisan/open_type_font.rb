# frozen_string_literal: true

require "bindata"
require_relative "constants"
require_relative "loading_modes"
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
  # @example Loading with metadata mode
  #   otf = OpenTypeFont.from_file("font.otf", mode: :metadata)
  #   puts otf.loading_mode  # => :metadata
  #   otf.table_available?("GSUB")  # => false
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

    # Loading mode for this font (:metadata or :full)
    attr_accessor :loading_mode

    # IO source for lazy loading
    attr_accessor :io_source

    # Whether lazy loading is enabled
    attr_accessor :lazy_load_enabled

    # Page cache for lazy loading (maps page_start_offset => page_data)
    attr_accessor :page_cache

    # Page size for lazy loading alignment (typical filesystem page size)
    PAGE_SIZE = 4096

    # Read OpenType Font from a file
    #
    # @param path [String] Path to the OTF file
    # @param mode [Symbol] Loading mode (:metadata or :full, default: :full)
    # @param lazy [Boolean] If true, load tables on demand (default: false for eager loading)
    # @return [OpenTypeFont] A new instance
    # @raise [ArgumentError] if path is nil or empty, or if mode is invalid
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [RuntimeError] if file format is invalid
    def self.from_file(path, mode: LoadingModes::FULL, lazy: false)
      if path.nil? || path.to_s.empty?
        raise ArgumentError,
              "path cannot be nil or empty"
      end
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      # Validate mode
      LoadingModes.validate_mode!(mode)

      File.open(path, "rb") do |io|
        font = read(io)
        font.initialize_storage
        font.loading_mode = mode
        font.lazy_load_enabled = lazy

        if lazy
          # Keep file handle open for lazy loading
          font.io_source = File.open(path, "rb")
          font.setup_finalizer
        else
          # Read tables upfront
          font.read_table_data(io)
        end

        font
      end
    rescue BinData::ValidityError, EOFError => e
      raise "Invalid OTF file: #{e.message}"
    end

    # Read OpenType Font from collection at specific offset
    #
    # @param io [IO] Open file handle
    # @param offset [Integer] Byte offset to the font
    # @param mode [Symbol] Loading mode (:metadata or :full, default: :full)
    # @return [OpenTypeFont] A new instance
    def self.from_collection(io, offset, mode: LoadingModes::FULL)
      LoadingModes.validate_mode!(mode)

      io.seek(offset)
      font = read(io)
      font.initialize_storage
      font.loading_mode = mode
      font.read_table_data(io)
      font
    end

    # Initialize storage hashes
    #
    # @return [void]
    def initialize_storage
      @table_data = {}
      @parsed_tables = {}
      @loading_mode = LoadingModes::FULL
      @lazy_load_enabled = false
      @io_source = nil
      @page_cache = {}
    end

    # Read table data for all tables
    #
    # In metadata mode, only reads metadata tables. In full mode, reads all tables.
    # In lazy load mode, doesn't read data upfront.
    #
    # @param io [IO] Open file handle
    # @return [void]
    def read_table_data(io)
      @table_data = {}

      if @lazy_load_enabled
        # Don't read data, just keep IO reference
        @io_source = io
        return
      end

      if @loading_mode == LoadingModes::METADATA
        # Only read metadata tables for performance
        # Use page-aware batched reading to maximize filesystem prefetching
        read_metadata_tables_batched(io)
      else
        # Read all tables
        tables.each do |entry|
          io.seek(entry.offset)
          # Force UTF-8 encoding on tag for hash key consistency
          tag_key = entry.tag.dup.force_encoding("UTF-8")
          @table_data[tag_key] = io.read(entry.table_length)
        end
      end
    end

    # Read metadata tables using page-aware batching
    #
    # Groups adjacent tables within page boundaries and reads them together
    # to maximize filesystem prefetching and minimize random seeks.
    #
    # @param io [IO] Open file handle
    # @return [void]
    def read_metadata_tables_batched(io)
      # Typical filesystem page size (4KB is common, but 8KB gives better prefetch window)
      page_threshold = 8192

      # Get metadata tables sorted by offset for sequential access
      metadata_entries = tables.select { |entry| LoadingModes::METADATA_TABLES_SET.include?(entry.tag) }
      metadata_entries.sort_by!(&:offset)

      return if metadata_entries.empty?

      # Group adjacent tables within page threshold for batched reading
      i = 0
      while i < metadata_entries.size
        batch_start = metadata_entries[i]
        batch_end = batch_start
        batch_entries = [batch_start]

        # Extend batch while next table is within page threshold
        j = i + 1
        while j < metadata_entries.size
          next_entry = metadata_entries[j]
          gap = next_entry.offset - (batch_end.offset + batch_end.table_length)

          # If gap is small (within page threshold), include in batch
          if gap <= page_threshold
            batch_end = next_entry
            batch_entries << next_entry
            j += 1
          else
            break
          end
        end

        # Read batch
        if batch_entries.size == 1
          # Single table, read normally
          io.seek(batch_start.offset)
          tag_key = batch_start.tag.dup.force_encoding("UTF-8")
          @table_data[tag_key] = io.read(batch_start.table_length)
        else
          # Multiple tables, read contiguous segment
          batch_offset = batch_start.offset
          batch_length = (batch_end.offset + batch_end.table_length) - batch_start.offset

          io.seek(batch_offset)
          batch_data = io.read(batch_length)

          # Extract individual tables from batch
          batch_entries.each do |entry|
            relative_offset = entry.offset - batch_offset
            tag_key = entry.tag.dup.force_encoding("UTF-8")
            @table_data[tag_key] = batch_data[relative_offset, entry.table_length]
          end
        end

        i = j
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

    # Check if a table is available in the current loading mode
    #
    # @param tag [String] The table tag to check
    # @return [Boolean] true if table is available in current mode
    def table_available?(tag)
      return false unless has_table?(tag)
      LoadingModes.table_allowed?(@loading_mode, tag)
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
    # and caches the result for subsequent calls. Enforces mode restrictions.
    #
    # @param tag [String] The table tag to retrieve
    # @return [Tables::*, nil] Parsed table object or nil if not found
    # @raise [ArgumentError] if table is not available in current loading mode
    def table(tag)
      # Check mode restrictions
      unless table_available?(tag)
        if has_table?(tag)
          raise ArgumentError,
                "Table '#{tag}' is not available in #{@loading_mode} mode. " \
                "Available tables: #{LoadingModes.tables_for(@loading_mode).inspect}"
        else
          return nil
        end
      end

      return @parsed_tables[tag] if @parsed_tables.key?(tag)

      # Lazy load table data if enabled
      if @lazy_load_enabled && !@table_data.key?(tag)
        load_table_data(tag)
      end

      @parsed_tables[tag] ||= parse_table(tag)
    end

    # Get units per em from head table
    #
    # @return [Integer, nil] Units per em value
    def units_per_em
      head = table(Constants::HEAD_TAG)
      head&.units_per_em
    end

    # Convenience methods for accessing common name table fields
    # These are particularly useful in minimal mode

    # Get font family name
    #
    # @return [String, nil] Family name or nil if not found
    def family_name
      name_table = table(Constants::NAME_TAG)
      name_table&.english_name(Tables::Name::FAMILY)
    end

    # Get font subfamily name (e.g., Regular, Bold, Italic)
    #
    # @return [String, nil] Subfamily name or nil if not found
    def subfamily_name
      name_table = table(Constants::NAME_TAG)
      name_table&.english_name(Tables::Name::SUBFAMILY)
    end

    # Get full font name
    #
    # @return [String, nil] Full name or nil if not found
    def full_name
      name_table = table(Constants::NAME_TAG)
      name_table&.english_name(Tables::Name::FULL_NAME)
    end

    # Get PostScript name
    #
    # @return [String, nil] PostScript name or nil if not found
    def post_script_name
      name_table = table(Constants::NAME_TAG)
      name_table&.english_name(Tables::Name::POSTSCRIPT_NAME)
    end

    # Get preferred family name
    #
    # @return [String, nil] Preferred family name or nil if not found
    def preferred_family_name
      name_table = table(Constants::NAME_TAG)
      name_table&.english_name(Tables::Name::PREFERRED_FAMILY)
    end

    # Get preferred subfamily name
    #
    # @return [String, nil] Preferred subfamily name or nil if not found
    def preferred_subfamily_name
      name_table = table(Constants::NAME_TAG)
      name_table&.english_name(Tables::Name::PREFERRED_SUBFAMILY)
    end

    # Close the IO source (for lazy loading)
    #
    # @return [void]
    def close
      @io_source&.close
      @io_source = nil
    end

    # Setup finalizer for cleanup
    #
    # @return [void]
    def setup_finalizer
      ObjectSpace.define_finalizer(self, self.class.finalize(@io_source))
    end

    # Finalizer proc for closing IO
    #
    # @param io [IO] The IO object to close
    # @return [Proc] The finalizer proc
    def self.finalize(io)
      proc { io&.close }
    end

    private

    # Load a single table's data on demand
    #
    # Uses page-aligned reads and caches pages to ensure lazy loading
    # performance is not slower than eager loading.
    #
    # @param tag [String] The table tag to load
    # @return [void]
    def load_table_data(tag)
      return unless @io_source

      entry = find_table_entry(tag)
      return nil unless entry

      # Use page-aligned reading with caching
      table_start = entry.offset
      table_end = entry.offset + entry.table_length

      # Calculate page boundaries
      page_start = (table_start / PAGE_SIZE) * PAGE_SIZE
      page_end = ((table_end + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE

      # Read all required pages (or use cached pages)
      table_data_parts = []
      current_page = page_start

      while current_page < page_end
        page_data = @page_cache[current_page]

        unless page_data
          # Read page from disk and cache it
          @io_source.seek(current_page)
          page_data = @io_source.read(PAGE_SIZE) || ""
          @page_cache[current_page] = page_data
        end

        # Calculate which part of this page we need
        chunk_start = [table_start - current_page, 0].max
        chunk_end = [table_end - current_page, PAGE_SIZE].min

        if chunk_end > chunk_start
          table_data_parts << page_data[chunk_start...chunk_end]
        end

        current_page += PAGE_SIZE
      end

      # Combine parts and store
      tag_key = tag.dup.force_encoding("UTF-8")
      @table_data[tag_key] = table_data_parts.join
    end

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
        Constants::HHEA_TAG => Tables::Hhea,
        Constants::HMTX_TAG => Tables::Hmtx,
        Constants::MAXP_TAG => Tables::Maxp,
        Constants::NAME_TAG => Tables::Name,
        Constants::OS2_TAG => Tables::Os2,
        Constants::POST_TAG => Tables::Post,
        Constants::CMAP_TAG => Tables::Cmap,
        Constants::FVAR_TAG => Tables::Fvar,
        Constants::GSUB_TAG => Tables::Gsub,
        Constants::GPOS_TAG => Tables::Gpos,
        Constants::GLYF_TAG => Tables::Glyf,
        Constants::LOCA_TAG => Tables::Loca,
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
