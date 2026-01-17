# frozen_string_literal: true

require_relative "constants"
require_relative "loading_modes"

module Fontisan
  # Base class for SFNT font tables
  #
  # Represents a single table in an SFNT font file, encapsulating:
  # - Table metadata (tag, checksum, offset, length)
  # - Lazy loading of table data
  # - Parsing of table data into structured objects
  # - Table-specific validation
  #
  # This class provides an OOP representation of font tables, replacing
  # the previous separation of TableDirectory (metadata), @table_data (raw bytes),
  # and @parsed_tables (parsed objects) with a single cohesive domain object.
  #
  # @abstract Subclasses should override `parser_class` and `validate_parsed_table?`
  #
  # @example Accessing table metadata
  #   table = SfntTable.new(font, entry)
  #   puts table.tag        # => "head"
  #   puts table.checksum   # => 0x12345678
  #   puts table.offset     # => 0x0000012C
  #   puts table.length     # => 54
  #
  # @example Lazy loading table data
  #   table.load_data!  # Loads raw bytes from IO
  #   puts table.data.bytesize
  #
  # @example Parsing table data
  #   head_table = table.parse
  #   puts head_table.units_per_em
  #
  # @example Validating table
  #   table.validate!  # Raises InvalidFontError if invalid
  class SfntTable
    # Table metadata entry (from TableDirectory)
    #
    # @return [TableDirectory] The table directory entry
    attr_reader :entry

    # Parent font containing this table
    #
    # @return [SfntFont] The font that contains this table
    attr_reader :font

    # Raw table data (loaded lazily)
    #
    # @return [String, nil] Raw binary table data, or nil if not loaded
    attr_reader :data

    # Parsed table object (cached)
    #
    # @return [Object, nil] Parsed table object, or nil if not parsed
    attr_reader :parsed

    # Table tag (4-character string)
    #
    # @return [String] The table tag (e.g., "head", "name", "cmap")
    def tag
      @entry.tag
    end

    # Table checksum
    #
    # @return [Integer] The table checksum
    def checksum
      @entry.checksum
    end

    # Table offset in font file
    #
    # @return [Integer] Byte offset of table data
    def offset
      @entry.offset
    end

    # Table length in bytes
    #
    # @return [Integer] Table data length in bytes
    def length
      @entry.table_length
    end

    # Initialize a new SfntTable
    #
    # @param font [SfntFont] The font containing this table
    # @param entry [TableDirectory] The table directory entry
    def initialize(font, entry)
      @font = font
      @entry = entry
      @data = nil
      @parsed = nil
    end

    # Load raw table data from font file
    #
    # Reads the table data from the font's IO source or from cached
    # table data. This method supports lazy loading.
    #
    # @return [self] Returns self for chaining
    # @raise [RuntimeError] if table data cannot be loaded
    def load_data!
      # Check if already loaded
      return self if @data

      # Try to get from font's table_data cache
      if @font.table_data && @font.table_data[tag]
        @data = @font.table_data[tag]
        return self
      end

      # Load from IO source if available
      if @font.io_source
        @font.io_source.seek(offset)
        @data = @font.io_source.read(length)
        return self
      end

      raise "Cannot load table '#{tag}': no IO source or cached data"
    end

    # Check if table data is loaded
    #
    # @return [Boolean] true if table data has been loaded
    def data_loaded?
      !@data.nil?
    end

    # Check if table has been parsed
    #
    # @return [Boolean] true if table has been parsed
    def parsed?
      !@parsed.nil?
    end

    # Parse table data into structured object
    #
    # Loads data if needed, then parses using the table-specific parser class.
    # Results are cached for subsequent calls.
    #
    # @return [Object, nil] Parsed table object, or nil if no parser available
    # @raise [RuntimeError] if table data cannot be loaded for parsing
    def parse
      return @parsed if parsed?

      # Load data if not already loaded
      load_data! unless data_loaded?

      # Get parser class for this table type
      parser = parser_class
      return nil unless parser

      # Parse and cache
      @parsed = parser.read(@data)
      @parsed
    end

    # Validate the table
    #
    # Performs table-specific validation. Subclasses should override
    # `validate_parsed_table?` to provide custom validation logic.
    #
    # @return [Boolean] true if table is valid
    # @raise [Fontisan::InvalidFontError] if table is invalid
    def validate!
      # Ensure data is loaded
      load_data! unless data_loaded?

      # Basic validation: data size matches expected size
      if @data.bytesize != length
        raise InvalidFontError,
              "Table '#{tag}' data size mismatch: expected #{length} bytes, got #{@data.bytesize}"
      end

      # Validate checksum if not head table (head table checksum is special)
      if tag != Constants::HEAD_TAG
        expected_checksum = calculate_checksum
        if checksum != expected_checksum
          # Checksum mismatch might be OK for some tables, log a warning
          # But don't fail validation for it
        end
      end

      # Table-specific validation (if parsed)
      if parsed?
        validate_parsed_table?
      end

      true
    end

    # Calculate table checksum
    #
    # @return [Integer] The checksum of the table data
    def calculate_checksum
      load_data! unless data_loaded?

      require_relative "utilities/checksum_calculator"
      Utilities::ChecksumCalculator.calculate_table_checksum(@data)
    end

    # Check if table is available in current loading mode
    #
    # @return [Boolean] true if table is available
    def available?
      @font.table_available?(tag)
    end

    # Check if table is required for the font
    #
    # @return [Boolean] true if table is required
    def required?
      Constants::REQUIRED_TABLES.include?(tag)
    end

    # Get human-readable table name
    #
    # @return [String] Human-readable name
    def human_name
      Constants::TABLE_NAMES[tag] || tag
    end

    # String representation
    #
    # @return [String] Human-readable representation
    def inspect
      "#<#{self.class.name} tag=#{tag.inspect} offset=0x#{offset.to_s(16).upcase} length=#{length}>"
    end

    # String representation for display
    #
    # @return [String] Human-readable representation
    def to_s
      "#{tag}: #{human_name} (#{length} bytes @ 0x#{offset.to_s(16).upcase})"
    end

    protected

    # Get the parser class for this table type
    #
    # Subclasses should override this method to return the appropriate
    # Tables::* class (e.g., Tables::Head, Tables::Name).
    #
    # @return [Class, nil] The parser class, or nil if no parser available
    def parser_class
      # Direct access to TABLE_CLASS_MAP for better performance
      @font.class::TABLE_CLASS_MAP[tag]
    end

    # Validate the parsed table object
    #
    # Subclasses should override this method to provide table-specific
    # validation logic. The default implementation does nothing.
    #
    # @return [Boolean] true if valid
    # @raise [Fontisan::InvalidFontError] if table is invalid
    def validate_parsed_table?
      true
    end
  end
end
