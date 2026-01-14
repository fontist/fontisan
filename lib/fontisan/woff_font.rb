# frozen_string_literal: true

require "bindata"
require "zlib"
require_relative "constants"
require_relative "utilities/checksum_calculator"

module Fontisan
  # WOFF Header structure
  class WoffHeader < BinData::Record
    endian :big
    uint32 :signature        # 0x774F4646 'wOFF'
    uint32 :flavor           # sfnt version (0x00010000 for TTF, 'OTTO' for CFF)
    uint32 :woff_length      # Total size of WOFF file
    uint16 :num_tables       # Number of entries in directory
    uint16 :reserved         # Reserved, must be zero
    uint32 :total_sfnt_size  # Total size needed for uncompressed font
    uint16 :major_version    # Major version of WOFF file
    uint16 :minor_version    # Minor version of WOFF file
    uint32 :meta_offset      # Offset to metadata block
    uint32 :meta_length      # Length of compressed metadata block
    uint32 :meta_orig_length # Length of uncompressed metadata block
    uint32 :priv_offset      # Offset to private data block
    uint32 :priv_length      # Length of private data block
  end

  # WOFF Table Directory Entry structure
  class WoffTableDirectoryEntry < BinData::Record
    endian :big
    string :tag, length: 4 # Table identifier
    uint32 :offset                   # Offset to compressed table data
    uint32 :comp_length              # Length of compressed data
    uint32 :orig_length              # Length of uncompressed data
    uint32 :orig_checksum            # Checksum of uncompressed table
  end

  # Web Open Font Format (WOFF) font domain object
  #
  # Represents a WOFF font file that uses zlib compression for table data.
  # WOFF is a simple wrapper format for TTF/OTF fonts with compression.
  #
  # According to the WOFF specification (https://www.w3.org/TR/WOFF/):
  # - Tables are individually compressed using zlib
  # - Optional metadata block (compressed XML)
  # - Optional private data block
  #
  # @example Reading a WOFF font
  #   woff = WoffFont.from_file("font.woff")
  #   puts woff.header.num_tables
  #   name_table = woff.table("name")
  #   puts name_table.english_name(Tables::Name::FAMILY)
  #
  # @example Converting to TTF/OTF
  #   woff = WoffFont.from_file("font.woff")
  #   woff.to_ttf("output.ttf")  # if TrueType flavored
  #   woff.to_otf("output.otf")  # if CFF flavored
  class WoffFont < BinData::Record
    endian :big

    woff_header :header
    array :table_entries, type: :woff_table_directory_entry, initial_length: lambda {
      header.num_tables
    }

    # Table data storage (decompressed on demand)
    attr_accessor :decompressed_tables
    attr_accessor :compressed_table_data

    # Parsed table instances cache
    attr_accessor :parsed_tables

    # File IO handle for lazy table decompression
    attr_accessor :io_source

    # WOFF signature constant
    WOFF_SIGNATURE = 0x774F4646 # 'wOFF'

    # Read WOFF font from a file
    #
    # @param path [String] Path to the WOFF file
    # @param mode [Symbol] Loading mode (:metadata or :full) - currently ignored, loads all tables
    # @param lazy [Boolean] Lazy loading flag - currently ignored, always eager
    # @return [WoffFont] A new instance
    # @raise [ArgumentError] if path is nil or empty
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [InvalidFontError] if file format is invalid
    def self.from_file(path, mode: LoadingModes::FULL, lazy: false)
      if path.nil? || path.to_s.empty?
        raise ArgumentError,
              "path cannot be nil or empty"
      end
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      File.open(path, "rb") do |io|
        font = read(io)
        font.validate_signature!
        font.initialize_storage
        font.io_source = io
        font.read_compressed_table_data(io)
        font
      end
    rescue BinData::ValidityError, EOFError => e
      Kernel.raise(::Fontisan::InvalidFontError,
                   "Invalid WOFF file: #{e.message}")
    end

    # Initialize storage hashes
    #
    # @return [void]
    def initialize_storage
      @decompressed_tables = {}
      @compressed_table_data = {}
      @parsed_tables = {}
    end

    # Validate WOFF signature
    #
    # @raise [InvalidFontError] if signature is invalid
    # @return [void]
    def validate_signature!
      signature_value = header.signature.to_i
      unless signature_value == WOFF_SIGNATURE
        Kernel.raise(::Fontisan::InvalidFontError,
                     "Invalid WOFF signature: expected 0x#{WOFF_SIGNATURE.to_s(16)}, " \
                     "got 0x#{signature_value.to_s(16)}")
      end
    end

    # Read compressed table data for all tables
    #
    # Tables are decompressed on-demand for efficiency
    #
    # @param io [IO] Open file handle
    # @return [void]
    def read_compressed_table_data(io)
      @compressed_table_data = {}
      table_entries.each do |entry|
        io.seek(entry.offset)
        # Force UTF-8 encoding on tag for hash key consistency
        tag_key = entry.tag.dup.force_encoding("UTF-8")
        @compressed_table_data[tag_key] = io.read(entry.comp_length)
      end
    end

    # Check if font is TrueType flavored
    #
    # @return [Boolean] true if TrueType, false if CFF
    def truetype?
      [Constants::SFNT_VERSION_TRUETYPE, 0x00010000].include?(header.flavor)
    end

    # Check if font is CFF flavored (OpenType with CFF outlines)
    #
    # @return [Boolean] true if CFF, false if TrueType
    def cff?
      [Constants::SFNT_VERSION_OTTO, 0x4F54544F].include?(header.flavor) # 'OTTO'
    end

    # Get decompressed table data
    #
    # Decompresses table data on first access and caches result
    #
    # @param tag [String, nil] The table tag (optional)
    # @return [String, Hash, nil] Decompressed table data, hash of all tables, or nil if not found
    def table_data(tag = nil)
      # If no tag provided, return all tables
      if tag.nil?
        # Decompress all tables and return as hash
        result = {}
        @compressed_table_data.each_key do |table_tag|
          result[table_tag] = table_data(table_tag)
        end
        return result
      end

      # Tag provided - return specific table
      return @decompressed_tables[tag] if @decompressed_tables.key?(tag)

      compressed_data = @compressed_table_data[tag]
      return nil unless compressed_data

      entry = find_table_entry(tag)
      return nil unless entry

      # Decompress if compressed (comp_length != orig_length)
      @decompressed_tables[tag] = if entry.comp_length == entry.orig_length
                                    # Table is not compressed
                                    compressed_data
                                  else
                                    # Decompress using zlib
                                    Zlib::Inflate.inflate(compressed_data)
                                  end

      # Verify decompressed size matches expected
      if @decompressed_tables[tag].bytesize != entry.orig_length
        Kernel.raise(::Fontisan::InvalidFontError,
                     "Decompressed table '#{tag}' size mismatch: " \
                     "expected #{entry.orig_length}, got #{@decompressed_tables[tag].bytesize}")
      end

      @decompressed_tables[tag]
    end

    # Check if font has a specific table
    #
    # @param tag [String] The table tag to check for
    # @return [Boolean] true if table exists, false otherwise
    def has_table?(tag)
      table_entries.any? { |entry| entry.tag == tag }
    end

    # Find a table entry by tag
    #
    # @param tag [String] The table tag to find
    # @return [WoffTableDirectoryEntry, nil] The table entry or nil
    def find_table_entry(tag)
      table_entries.find { |entry| entry.tag == tag }
    end

    # Get list of all table tags
    #
    # @return [Array<String>] Array of table tag strings
    def table_names
      table_entries.map(&:tag)
    end

    # Get parsed table instance
    #
    # This method decompresses and parses the raw table data into a
    # structured table object and caches the result for subsequent calls.
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

    # Get WOFF metadata if present
    #
    # WOFF metadata is optional compressed XML describing the font
    #
    # @return [String, nil] Decompressed metadata XML or nil
    def metadata
      return nil if header.meta_length.zero?
      return @metadata if defined?(@metadata)

      File.open(io_source.path, "rb") do |io|
        io.seek(header.meta_offset)
        compressed_meta = io.read(header.meta_length)
        @metadata = Zlib::Inflate.inflate(compressed_meta)

        # Verify decompressed size
        if @metadata.bytesize != header.meta_orig_length
          Kernel.raise(::Fontisan::InvalidFontError,
                       "Metadata size mismatch: expected #{header.meta_orig_length}, " \
                       "got #{@metadata.bytesize}")
        end

        @metadata
      end
    rescue StandardError => e
      warn "Failed to decompress WOFF metadata: #{e.message}"
      @metadata = nil
    end

    # Get WOFF private data if present
    #
    # WOFF private data is optional application-specific data
    #
    # @return [String, nil] Private data or nil
    def private_data
      return nil if header.priv_length.zero?
      return @private_data if defined?(@private_data)

      File.open(io_source.path, "rb") do |io|
        io.seek(header.priv_offset)
        @private_data = io.read(header.priv_length)
      end
    rescue StandardError => e
      warn "Failed to read WOFF private data: #{e.message}"
      @private_data = nil
    end

    # Convert WOFF to TTF format
    #
    # Decompresses all tables and reconstructs a standard TTF file
    #
    # @param output_path [String] Path where TTF file will be written
    # @return [Integer] Number of bytes written
    # @raise [InvalidFontError] if font is not TrueType flavored
    def to_ttf(output_path)
      unless truetype?
        Kernel.raise(::Fontisan::InvalidFontError,
                     "Cannot convert to TTF: font is CFF flavored (use to_otf)")
      end

      build_sfnt_font(output_path, Constants::SFNT_VERSION_TRUETYPE)
    end

    # Convert WOFF to OTF format
    #
    # Decompresses all tables and reconstructs a standard OTF file
    #
    # @param output_path [String] Path where OTF file will be written
    # @return [Integer] Number of bytes written
    # @raise [InvalidFontError] if font is not CFF flavored
    def to_otf(output_path)
      unless cff?
        Kernel.raise(::Fontisan::InvalidFontError,
                     "Cannot convert to OTF: font is TrueType flavored (use to_ttf)")
      end

      build_sfnt_font(output_path, Constants::SFNT_VERSION_OTTO)
    end

    # Validate format correctness
    #
    # @return [Boolean] true if the WOFF format is valid, false otherwise
    def valid?
      return false unless header
      return false unless header.signature == WOFF_SIGNATURE
      return false unless table_entries.respond_to?(:length)
      return false if table_entries.length != header.num_tables
      return false unless has_table?(Constants::HEAD_TAG)

      true
    end

    private

    # Parse a table from decompressed data
    #
    # @param tag [String] The table tag to parse
    # @return [Tables::*, nil] Parsed table object or nil
    def parse_table(tag)
      raw_data = table_data(tag)
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
      }[tag]
    end

    # Build an SFNT font file (TTF or OTF) from decompressed WOFF data
    #
    # @param output_path [String] Path where font will be written
    # @param sfnt_version [Integer] SFNT version (0x00010000 for TTF, 0x4F54544F for OTF)
    # @return [Integer] Number of bytes written
    def build_sfnt_font(output_path, sfnt_version)
      File.open(output_path, "wb") do |io|
        # Decompress all tables
        decompressed_tables = {}
        table_entries.each do |entry|
          tag = entry.tag.dup.force_encoding("UTF-8")
          decompressed_tables[tag] = table_data(tag)
        end

        # Calculate offset table fields
        num_tables = table_entries.length
        search_range, entry_selector, range_shift = calculate_offset_table_fields(num_tables)

        # Write offset table
        io.write([sfnt_version].pack("N"))
        io.write([num_tables].pack("n"))
        io.write([search_range].pack("n"))
        io.write([entry_selector].pack("n"))
        io.write([range_shift].pack("n"))

        # Calculate table offsets
        offset = 12 + (num_tables * 16) # Header + directory
        table_records = []

        table_entries.each do |entry|
          tag = entry.tag.dup.force_encoding("UTF-8")
          data = decompressed_tables[tag]
          length = data.bytesize

          # Calculate checksum
          checksum = Utilities::ChecksumCalculator.calculate_table_checksum(data)

          table_records << {
            tag: entry.tag,
            checksum: checksum,
            offset: offset,
            length: length,
            data: data,
          }

          # Update offset for next table (with padding)
          offset += length
          padding = (Constants::TABLE_ALIGNMENT - (length % Constants::TABLE_ALIGNMENT)) %
            Constants::TABLE_ALIGNMENT
          offset += padding
        end

        # Write table directory
        table_records.each do |record|
          io.write(record[:tag])
          io.write([record[:checksum]].pack("N"))
          io.write([record[:offset]].pack("N"))
          io.write([record[:length]].pack("N"))

          # Write table data
          io.write(record[:data])

          # Add padding
          padding = (Constants::TABLE_ALIGNMENT - (record[:length] % Constants::TABLE_ALIGNMENT)) %
            Constants::TABLE_ALIGNMENT
          io.write("\x00" * padding) if padding.positive?
        end

        io.pos
      end

      # Update checksum adjustment in head table
      update_checksum_adjustment_in_file(output_path)

      File.size(output_path)
    end

    # Calculate offset table fields
    #
    # @param num_tables [Integer] Number of tables
    # @return [Array<Integer>] [searchRange, entrySelector, rangeShift]
    def calculate_offset_table_fields(num_tables)
      entry_selector = (Math.log(num_tables) / Math.log(2)).floor
      search_range = (2**entry_selector) * 16
      range_shift = num_tables * 16 - search_range
      [search_range, entry_selector, range_shift]
    end

    # Update checksumAdjustment field in head table
    #
    # @param path [String] Path to the font file
    # @return [void]
    def update_checksum_adjustment_in_file(path)
      # Find head table position in output file
      head_offset = nil
      File.open(path, "rb") do |io|
        io.seek(4) # Skip sfnt_version
        num_tables = io.read(2).unpack1("n")
        io.seek(12) # Start of table directory

        num_tables.times do
          tag = io.read(4)
          io.read(4) # checksum
          offset = io.read(4).unpack1("N")
          io.read(4) # length

          if tag == Constants::HEAD_TAG
            head_offset = offset
            break
          end
        end
      end

      return unless head_offset

      # Calculate checksum directly from IO to avoid Windows Tempfile issues
      File.open(path, "r+b") do |io|
        checksum = Utilities::ChecksumCalculator.calculate_checksum_from_io(io)

        # Calculate adjustment
        adjustment = Utilities::ChecksumCalculator.calculate_adjustment(checksum)

        # Write adjustment to head table (offset 8 within head table)
        io.seek(head_offset + 8)
        io.write([adjustment].pack("N"))
      end
    end
  end
end
