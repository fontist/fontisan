# frozen_string_literal: true

require "bindata"
require_relative "constants"
require_relative "loading_modes"
require_relative "utilities/checksum_calculator"
require_relative "sfnt_table"
require_relative "tables/head_table"
require_relative "tables/name_table"
require_relative "tables/os2_table"
require_relative "tables/cmap_table"
require_relative "tables/glyf_table"
require_relative "tables/hhea_table"
require_relative "tables/maxp_table"
require_relative "tables/post_table"
require_relative "tables/hmtx_table"
require_relative "tables/loca_table"

module Fontisan
  # SFNT Offset Table structure
  #
  # Common structure for both TrueType and OpenType fonts.
  class OffsetTable < BinData::Record
    endian :big
    uint32 :sfnt_version
    uint16 :num_tables
    uint16 :search_range
    uint16 :entry_selector
    uint16 :range_shift
  end

  # SFNT Table Directory Entry structure
  #
  # Common structure for both TrueType and OpenType fonts.
  class TableDirectory < BinData::Record
    endian :big
    string :tag, length: 4
    uint32 :checksum
    uint32 :offset
    uint32 :table_length
  end

  # Base class for SFNT font formats (TrueType and OpenType)
  #
  # This class contains all shared SFNT structure and behavior.
  # TrueType and OpenType fonts inherit from this class and add
  # format-specific functionality.
  #
  # @abstract Subclasses must implement format-specific validation
  #
  # @example Reading a font (format detected automatically)
  #   font = Fontisan::FontLoader.load("font.ttf")  # Returns TrueTypeFont
  #   font = Fontisan::FontLoader.load("font.otf")  # Returns OpenTypeFont
  #
  # @example Reading and analyzing a font
  #   ttf = Fontisan::TrueTypeFont.from_file("font.ttf")
  #   puts ttf.header.num_tables  # => 14
  #   name_table = ttf.table("name")
  #   puts name_table.english_name(Tables::Name::FAMILY)
  #
  # @example Loading with metadata mode
  #   ttf = Fontisan::TrueTypeFont.from_file("font.ttf", mode: :metadata)
  #   puts ttf.loading_mode  # => :metadata
  #   ttf.table_available?("GSUB")  # => false
  #
  # @example Writing a font
  #   ttf.to_file("output.ttf")
  class SfntFont < BinData::Record
    endian :big

    offset_table :header
    array :tables, type: :table_directory, initial_length: lambda {
      header.num_tables
    }

    # Table data is stored separately since it's at variable offsets
    attr_accessor :table_data

    # Parsed table instances cache
    attr_accessor :parsed_tables

    # OOP SfntTable instances (tag => SfntTable)
    attr_accessor :sfnt_tables

    # Table entry lookup cache (tag => TableDirectory)
    attr_accessor :table_entry_cache

    # Loading mode for this font (:metadata or :full)
    attr_accessor :loading_mode

    # IO source for lazy loading
    attr_accessor :io_source

    # Whether lazy loading is enabled
    attr_accessor :lazy_load_enabled

    # Map table tag to parser class (cached as constant for performance)
    #
    # @return [Hash<String, Class>] Mapping of table tags to parser classes
    TABLE_CLASS_MAP = {
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
      "SVG " => Tables::Svg,
      "COLR" => Tables::Colr,
      "CPAL" => Tables::Cpal,
      "CBDT" => Tables::Cbdt,
      "CBLC" => Tables::Cblc,
      "sbix" => Tables::Sbix,
    }.freeze

    # Map table tag to SfntTable wrapper class (cached as constant for performance)
    #
    # @return [Hash<String, Class>] Mapping of table tags to SfntTable wrapper classes
    SFNT_TABLE_CLASS_MAP = {
      Constants::HEAD_TAG => Tables::HeadTable,
      Constants::NAME_TAG => Tables::NameTable,
      Constants::OS2_TAG => Tables::Os2Table,
      Constants::CMAP_TAG => Tables::CmapTable,
      Constants::GLYF_TAG => Tables::GlyfTable,
      Constants::HHEA_TAG => Tables::HheaTable,
      Constants::MAXP_TAG => Tables::MaxpTable,
      Constants::POST_TAG => Tables::PostTable,
      Constants::HMTX_TAG => Tables::HmtxTable,
      Constants::LOCA_TAG => Tables::LocaTable,
    }.freeze

    # Padding bytes for table alignment (frozen to avoid reallocation)
    PADDING_BYTES = ("\x00" * 4).freeze

    # Read SFNT Font from a file
    #
    # @param path [String] Path to the font file
    # @param mode [Symbol] Loading mode (:metadata or :full, default: :full)
    # @param lazy [Boolean] If true, load tables on demand (default: false)
    # @return [SfntFont] A new instance
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
      raise "Invalid font file: #{e.message}"
    end

    # Read SFNT Font from collection at specific offset
    #
    # @param io [IO] Open file handle
    # @param offset [Integer] Byte offset to the font
    # @param mode [Symbol] Loading mode (:metadata or :full, default: :full)
    # @return [SfntFont] A new instance
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
      @sfnt_tables = {}
      @table_entry_cache = {}
      @tag_encoding_cache = {} # Cache for normalized tag encodings
      @table_names = nil # Cache for table names array
      @loading_mode = LoadingModes::FULL
      @lazy_load_enabled = false
      @io_source = nil
    end

    # Read table data for all tables in the font
    #
    # In metadata mode, only reads metadata tables. In full mode, reads all tables.
    # In lazy load mode, doesn't read data upfront.
    #
    # @param io [IO] IO object to read from
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
          # Normalize tag encoding for hash key consistency
          tag_key = normalize_tag(entry.tag)
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
          tag_key = normalize_tag(batch_start.tag)
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
            tag_key = normalize_tag(entry.tag)
            @table_data[tag_key] =
              batch_data[relative_offset, entry.table_length]
          end
        end

        i = j
      end
    end

    # Write SFNT Font to a file
    #
    # Writes the complete font structure to disk, including proper checksum
    # calculation and table alignment.
    #
    # @param path [String] Path where the font file will be written
    # @return [Integer] Number of bytes written
    # @raise [IOError] if writing fails
    def to_file(path)
      File.open(path, "w+b") do |io|
        # Write header and tables (directory)
        write_structure(io)

        # Write table data with updated offsets
        write_table_data_with_offsets(io)

        # Update checksum adjustment in head table BEFORE closing file
        # This avoids Windows file locking issues when Tempfiles are used
        head = head_table
        update_checksum_adjustment_in_io(io, head.offset) if head

        io.pos
      end

      File.size(path)
    end

    # Validate format correctness
    #
    # @return [Boolean] true if the font format is valid, false otherwise
    def valid?
      return false unless header
      return false unless tables.respond_to?(:length)
      return false unless @table_data.is_a?(Hash)
      return false if tables.length != header.num_tables
      return false unless head_table

      true
    end

    # Check if font has a specific table (optimized with cache)
    #
    # @param tag [String] The table tag to check for
    # @return [Boolean] true if table exists, false otherwise
    def has_table?(tag)
      !find_table_entry(tag).nil?
    end

    # Check if a table is available in the current loading mode
    #
    # @param tag [String] The table tag to check
    # @return [Boolean] true if table is available in current mode
    def table_available?(tag)
      return false unless has_table?(tag)

      LoadingModes.table_allowed?(@loading_mode, tag)
    end

    # Find a table entry by tag (cached for performance)
    #
    # @param tag [String] The table tag to find
    # @return [TableDirectory, nil] The table entry or nil
    def find_table_entry(tag)
      return @table_entry_cache[tag] if @table_entry_cache.key?(tag)

      entry = tables.find { |entry| entry.tag == tag }
      @table_entry_cache[tag] = entry
      entry
    end

    # Get the head table entry
    #
    # @return [TableDirectory, nil] The head table entry or nil
    def head_table
      find_table_entry(Constants::HEAD_TAG)
    end

    # Get list of all table tags (cached for performance)
    #
    # @return [Array<String>] Array of table tag strings
    def table_names
      @table_names ||= tables.map(&:tag)
    end

    # Get OOP SfntTable instance for a table
    #
    # Returns a SfntTable (or subclass) instance that encapsulates the table's
    # metadata, lazy loading, parsing, and validation. This provides a more
    # object-oriented interface than the separate TableDirectory/@table_data/@parsed_tables
    # approach.
    #
    # @param tag [String] The table tag to retrieve
    # @return [SfntTable, nil] SfntTable instance (or subclass like HeadTable), or nil if not found
    #
    # @example Using SfntTable for validation
    #   head = font.sfnt_table("head")
    #   head.validate!  # Performs head-specific validation
    #   head.units_per_em  # => 2048 (convenience method)
    def sfnt_table(tag)
      # Return cached instance if available (fast path)
      cached = @sfnt_tables[tag]
      return cached if cached

      # Only check has_table? if not cached (avoids redundant lookup)
      return nil unless has_table?(tag)

      # Create and cache (find_table_entry is already cached internally)
      @sfnt_tables[tag] = create_sfnt_table(tag)
    end

    # Get all SfntTable instances
    #
    # @return [Hash<String, SfntTable>] Hash mapping tag => SfntTable instance
    def all_sfnt_tables
      table_names.each_with_object({}) do |tag, hash|
        hash[tag] = sfnt_table(tag)
      end
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

      # Return cached if available (fast path)
      return @parsed_tables[tag] if @parsed_tables.key?(tag)

      # Lazy load table data if enabled
      load_table_data(tag) if @lazy_load_enabled && !@table_data.key?(tag)

      # Parse and cache
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

    # Update checksum adjustment in head table using IO
    #
    # Calculates the checksum of the entire file and writes the
    # adjustment value to the head table's checksumAdjustment field.
    #
    # @param io [IO] IO object to read from and write to
    # @param head_offset [Integer] Offset to the head table
    # @return [void]
    def update_checksum_adjustment_in_io(io, head_offset)
      io.rewind
      checksum = Utilities::ChecksumCalculator.calculate_checksum_from_io(io)
      adjustment = Utilities::ChecksumCalculator.calculate_adjustment(checksum)
      io.seek(head_offset + 8)
      io.write([adjustment].pack("N"))
    end

    # Update checksum adjustment in head table by file path
    #
    # Opens the file, calculates the checksum, and updates the adjustment.
    #
    # @param path [String] Path to the font file
    # @param head_offset [Integer] Offset to the head table
    # @return [void]
    def update_checksum_adjustment_in_file(path, head_offset)
      File.open(path, "r+b") do |io|
        update_checksum_adjustment_in_io(io, head_offset)
      end
    end

    private

    # Normalize tag encoding to UTF-8 (cached for performance)
    #
    # @param tag [String] The tag to normalize
    # @return [String] UTF-8 encoded tag
    def normalize_tag(tag)
      @tag_encoding_cache[tag] ||= tag.dup.force_encoding("UTF-8")
    end

    # Load a single table's data on demand
    #
    # Uses direct seek-and-read for minimal overhead. This ensures lazy loading
    # performance is comparable to eager loading when accessing all tables.
    #
    # @param tag [String] The table tag to load
    # @return [void]
    def load_table_data(tag)
      return unless @io_source

      entry = find_table_entry(tag)
      return nil unless entry

      # Direct seek and read - same as eager loading but on-demand
      @io_source.seek(entry.offset)
      tag_key = normalize_tag(tag)
      @table_data[tag_key] = @io_source.read(entry.table_length)
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

    # Map table tag to SfntTable wrapper class
    #
    # @param tag [String] The table tag
    # @return [SfntTable, nil] SfntTable instance or nil
    def create_sfnt_table(tag)
      entry = find_table_entry(tag)
      return nil unless entry

      # Use hash lookup for O(1) dispatch instead of case statement
      table_class = SFNT_TABLE_CLASS_MAP[tag] || SfntTable
      table_class.new(self, entry)
    end

    # Map table tag to parser class
    #
    # @param tag [String] The table tag
    # @return [Class, nil] Table parser class or nil
    def table_class_for(tag)
      TABLE_CLASS_MAP[tag]
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
        io.write(PADDING_BYTES[0, padding]) if padding.positive?

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
        io.write([current_position].pack("N")) # Offset is now known
        io.seek(current_pos)
      end
    end
  end
end
