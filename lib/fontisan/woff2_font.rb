# frozen_string_literal: true

require "bindata"
require "brotli"
require_relative "constants"
require_relative "utilities/checksum_calculator"

module Fontisan
  # WOFF2 Header structure
  #
  # WOFF2 header is more compact than WOFF, using variable-length integers
  # for some fields and omitting redundant information.
  class Woff2Header < BinData::Record
    endian :big
    uint32 :signature        # 0x774F4632 'wOF2'
    uint32 :flavor           # sfnt version (0x00010000 for TTF, 'OTTO' for CFF)
    uint32 :woff2_length     # Total size of WOFF2 file
    uint16 :num_tables       # Number of entries in directory
    uint16 :reserved         # Reserved, must be zero
    uint32 :total_sfnt_size  # Total size needed for uncompressed font
    uint32 :total_compressed_size # Total size of compressed data block
    uint16 :major_version    # Major version of WOFF file
    uint16 :minor_version    # Minor version of WOFF file
    uint32 :meta_offset      # Offset to metadata block
    uint32 :meta_length      # Length of compressed metadata block
    uint32 :meta_orig_length # Length of uncompressed metadata block
    uint32 :priv_offset      # Offset to private data block
    uint32 :priv_length      # Length of private data block
  end

  # WOFF2 Table Directory Entry structure
  #
  # WOFF2 table directory entries are more complex than WOFF,
  # with transformation flags and variable-length sizes.
  class Woff2TableDirectoryEntry
    attr_accessor :tag, :flags, :transform_version, :orig_length,
                  :transform_length, :offset

    # Transformation version flags
    TRANSFORM_NONE = 0
    TRANSFORM_GLYF_LOCA = 0
    TRANSFORM_LOCA = 1
    TRANSFORM_HMTX = 2

    # Known table tags with assigned indices (0-62)
    KNOWN_TAGS = [
      "cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post",
      "cvt ", "fpgm", "glyf", "loca", "prep", "CFF ", "VORG", "EBDT",
      "EBLC", "gasp", "hdmx", "kern", "LTSH", "PCLT", "VDMX", "vhea",
      "vmtx", "BASE", "GDEF", "GPOS", "GSUB", "EBSC", "JSTF", "MATH",
      "CBDT", "CBLC", "COLR", "CPAL", "SVG ", "sbix", "acnt", "avar",
      "bdat", "bloc", "bsln", "cvar", "fdsc", "feat", "fmtx", "fvar",
      "gvar", "hsty", "just", "lcar", "mort", "morx", "opbd", "prop",
      "trak", "Zapf", "Silf", "Glat", "Gloc", "Feat", "Sill"
    ].freeze

    def initialize
      @flags = 0
      @transform_version = TRANSFORM_NONE
    end

    # Check if table is transformed
    def transformed?
      (@flags & 0x3F) != 0x3F && KNOWN_TAGS[tag_index]&.start_with?(/glyf|loca|hmtx/)
    end

    # Get transform version for this table
    def transform_version
      return TRANSFORM_NONE unless transformed?

      case tag
      when "glyf", "loca"
        TRANSFORM_GLYF_LOCA
      when "hmtx"
        TRANSFORM_HMTX
      else
        TRANSFORM_NONE
      end
    end

    private

    def tag_index
      @flags & 0x3F
    end
  end

  # Web Open Font Format 2.0 (WOFF2) font domain object
  #
  # Represents a WOFF2 font file that uses Brotli compression and table
  # transformations. WOFF2 is significantly more complex than WOFF.
  #
  # According to the WOFF2 specification (https://www.w3.org/TR/WOFF2/):
  # - Tables can be transformed (glyf, loca, hmtx have special formats)
  # - All compressed data in a single Brotli stream
  # - Variable-length integer encoding (UIntBase128, 255UInt16)
  # - More efficient compression than WOFF
  #
  # @example Reading a WOFF2 font
  #   woff2 = Woff2Font.from_file("font.woff2")
  #   puts woff2.header.num_tables
  #   name_table = woff2.table("name")
  #   puts name_table.english_name(Tables::Name::FAMILY)
  #
  # @example Converting to TTF/OTF
  #   woff2 = Woff2Font.from_file("font.woff2")
  #   woff2.to_ttf("output.ttf")  # if TrueType flavored
  #   woff2.to_otf("output.otf")  # if CFF flavored
  class Woff2Font
    attr_accessor :header, :table_entries, :decompressed_tables,
                  :parsed_tables, :io_source

    # WOFF2 signature constant
    WOFF2_SIGNATURE = 0x774F4632 # 'wOF2'

    # Read WOFF2 font from a file
    #
    # @param path [String] Path to the WOFF2 file
    # @return [Woff2Font] A new instance
    # @raise [ArgumentError] if path is nil or empty
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [InvalidFontError] if file format is invalid
    def self.from_file(path)
      if path.nil? || path.to_s.empty?
        raise ArgumentError, "path cannot be nil or empty"
      end
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      File.open(path, "rb") do |io|
        font = new
        font.read_from_io(io)
        font.validate_signature!
        font.initialize_storage
        font.decompress_and_parse_tables(io)
        font.io_source = io
        font
      end
    rescue BinData::ValidityError, EOFError => e
      raise InvalidFontError, "Invalid WOFF2 file: #{e.message}"
    end

    def initialize
      @header = nil
      @table_entries = []
      @decompressed_tables = {}
      @parsed_tables = {}
      @io_source = nil
    end

    # Read header and table directory from IO
    #
    # @param io [IO] Open file handle
    # @return [void]
    def read_from_io(io)
      @header = Woff2Header.read(io)
      read_table_directory(io)
    end

    # Initialize storage hashes
    #
    # @return [void]
    def initialize_storage
      @decompressed_tables ||= {}
      @initialize_storage ||= {}
    end

    # Validate WOFF2 signature
    #
    # @raise [InvalidFontError] if signature is invalid
    # @return [void]
    def validate_signature!
      signature_value = header.signature.to_i
      unless signature_value == WOFF2_SIGNATURE
        Kernel.raise(::Fontisan::InvalidFontError,
                     "Invalid WOFF2 signature: expected 0x#{WOFF2_SIGNATURE.to_s(16)}, " \
                     "got 0x#{signature_value.to_s(16)}")
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
    # Provides unified interface compatible with WoffFont
    #
    # @param tag [String] The table tag
    # @return [String, nil] Decompressed table data or nil if not found
    def table_data(tag)
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
    # @return [Woff2TableDirectoryEntry, nil] The table entry or nil
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

    # Get WOFF2 metadata if present
    #
    # @return [String, nil] Decompressed metadata XML or nil
    def metadata
      return nil if header.meta_length.zero?
      return @metadata if defined?(@metadata)

      File.open(io_source.path, "rb") do |io|
        io.seek(header.meta_offset)
        compressed_meta = io.read(header.meta_length)
        @metadata = Brotli.inflate(compressed_meta)

        # Verify decompressed size
        if @metadata.bytesize != header.meta_orig_length
          raise InvalidFontError,
                "Metadata size mismatch: expected #{header.meta_orig_length}, got #{@metadata.bytesize}"
        end

        @metadata
      end
    rescue StandardError => e
      warn "Failed to decompress WOFF2 metadata: #{e.message}"
      @metadata = nil
    end

    # Convert WOFF2 to TTF format
    #
    # Decompresses and reconstructs tables, then builds a standard TTF file
    #
    # @param output_path [String] Path where TTF file will be written
    # @return [Integer] Number of bytes written
    # @raise [InvalidFontError] if font is not TrueType flavored
    def to_ttf(output_path)
      unless truetype?
        raise InvalidFontError,
              "Cannot convert to TTF: font is CFF flavored (use to_otf)"
      end

      build_sfnt_font(output_path, Constants::SFNT_VERSION_TRUETYPE)
    end

    # Convert WOFF2 to OTF format
    #
    # Decompresses and reconstructs tables, then builds a standard OTF file
    #
    # @param output_path [String] Path where OTF file will be written
    # @return [Integer] Number of bytes written
    # @raise [InvalidFontError] if font is not CFF flavored
    def to_otf(output_path)
      unless cff?
        raise InvalidFontError,
              "Cannot convert to OTF: font is TrueType flavored (use to_ttf)"
      end

      build_sfnt_font(output_path, Constants::SFNT_VERSION_OTTO)
    end

    # Validate format correctness
    #
    # @return [Boolean] true if the WOFF2 format is valid, false otherwise
    def valid?
      return false unless header
      return false unless header.signature == WOFF2_SIGNATURE
      return false unless table_entries.respond_to?(:length)
      return false if table_entries.length != header.num_tables
      return false unless has_table?(Constants::HEAD_TAG)

      true
    end

    private

    # Read variable-length UIntBase128 integer
    #
    # WOFF2 uses a variable-length encoding for table sizes:
    # - If high bit is 0, it's a single byte value
    # - If high bit is 1, continue reading bytes
    # - Maximum 5 bytes for a 32-bit value
    #
    # @param io [IO] Open file handle
    # @return [Integer] The decoded integer value
    def read_uint_base128(io)
      result = 0
      5.times do
        byte = io.read(1).unpack1("C")
        return nil unless byte

        # Continue if high bit is set
        if (byte & 0x80).zero?
          return (result << 7) | byte
        else
          result = (result << 7) | (byte & 0x7F)
        end
      end

      # If we're here, the encoding is invalid
      raise InvalidFontError, "Invalid UIntBase128 encoding"
    end

    # Read 255UInt16 variable-length integer
    #
    # Used in transformed glyf table:
    # - If value < 253, it's the value itself (1 byte)
    # - If value == 253, read next byte + 253 (2 bytes)
    # - If value == 254, read next 2 bytes as big-endian (3 bytes)
    # - If value == 255, read next 2 bytes + 506 (3 bytes special)
    #
    # @param io [IO] Open file handle
    # @return [Integer] The decoded integer value
    def read_255_uint16(io)
      first = io.read(1).unpack1("C")
      return nil unless first

      case first
      when 0..252
        first
      when 253
        second = io.read(1).unpack1("C")
        253 + second
      when 254
        io.read(2).unpack1("n")
      when 255
        value = io.read(2).unpack1("n")
        value + 506
      end
    end

    # Read WOFF2 table directory
    #
    # The table directory in WOFF2 is more compact than WOFF,
    # using variable-length integers and known table indices.
    #
    # @param io [IO] Open file handle
    # @return [void]
    def read_table_directory(io)
      @table_entries = []

      header.num_tables.times do
        entry = Woff2TableDirectoryEntry.new

        # Read flags byte
        flags = io.read(1).unpack1("C")
        entry.flags = flags

        # Determine tag
        tag_index = flags & 0x3F
        if tag_index == 0x3F
          # Custom tag (4 bytes)
          entry.tag = io.read(4).force_encoding("UTF-8")
        else
          # Known tag from table
          entry.tag = Woff2TableDirectoryEntry::KNOWN_TAGS[tag_index]
          unless entry.tag
            raise InvalidFontError, "Invalid table tag index: #{tag_index}"
          end
        end

        # Read orig_length (UIntBase128)
        entry.orig_length = read_uint_base128(io)

        # For transformed tables, read transform_length
        transform_version = (flags >> 6) & 0x03
        if transform_version != 0 && ["glyf", "loca",
                                      "hmtx"].include?(entry.tag)
          entry.transform_length = read_uint_base128(io)
          entry.transform_version = transform_version
        end

        @table_entries << entry
      end
    end

    # Decompress table data block and reconstruct tables
    #
    # WOFF2 stores all table data in a single Brotli-compressed block.
    # After decompression, we need to:
    # 1. Split into individual tables
    # 2. Reconstruct transformed tables (glyf, loca, hmtx)
    #
    # @param io [IO] Open file handle
    # @return [void]
    def decompress_and_parse_tables(io)
      # Position after table directory
      # The compressed data starts immediately after the table directory
      compressed_offset = header.to_binary_s.bytesize +
        calculate_table_directory_size

      io.seek(compressed_offset)
      compressed_data = io.read(header.total_compressed_size)

      # Decompress entire data block with Brotli
      decompressed_data = Brotli.inflate(compressed_data)

      # Split decompressed data into individual tables
      offset = 0
      table_entries.each do |entry|
        table_size = entry.transform_length || entry.orig_length

        table_data = decompressed_data[offset, table_size]
        offset += table_size

        # Reconstruct transformed tables
        if entry.transform_version && entry.transform_version != Woff2TableDirectoryEntry::TRANSFORM_NONE
          table_data = reconstruct_transformed_table(entry, table_data)
        end

        @decompressed_tables[entry.tag] = table_data
      end
    end

    # Calculate size of table directory
    #
    # Variable-length encoding makes this non-trivial
    #
    # @return [Integer] Size in bytes
    def calculate_table_directory_size
      size = 0
      table_entries.each do |entry|
        size += 1 # flags byte

        # Tag (4 bytes if custom, 0 if known)
        tag_index = entry.flags & 0x3F
        size += 4 if tag_index == 0x3F

        # orig_length (UIntBase128) - estimate
        size += uint_base128_size(entry.orig_length)

        # transform_length if present
        if entry.transform_version && entry.transform_version != Woff2TableDirectoryEntry::TRANSFORM_NONE
          size += uint_base128_size(entry.transform_length)
        end
      end
      size
    end

    # Estimate size of UIntBase128 encoded value
    #
    # @param value [Integer] The value to encode
    # @return [Integer] Estimated size in bytes
    def uint_base128_size(value)
      return 1 if value < 128

      bytes = 0
      v = value
      while v.positive?
        bytes += 1
        v >>= 7
      end
      [bytes, 5].min # Max 5 bytes
    end

    # Reconstruct transformed table from WOFF2 format
    #
    # WOFF2 can transform certain tables for better compression:
    # - glyf/loca: Complex transformation with multiple streams
    # - hmtx: Can omit redundant data
    #
    # @param entry [Woff2TableDirectoryEntry] Table entry
    # @param data [String] Transformed table data
    # @return [String] Reconstructed standard table data
    def reconstruct_transformed_table(entry, data)
      case entry.tag
      when "glyf", "loca"
        reconstruct_glyf_loca(entry, data)
      when "hmtx"
        reconstruct_hmtx(entry, data)
      else
        # Unknown transformation, return as-is
        data
      end
    end

    # Reconstruct glyf/loca tables from WOFF2 transformed format
    #
    # This is the most complex WOFF2 transformation. The transformed
    # glyf table contains multiple streams that need to be reconstructed.
    #
    # @param entry [Woff2TableDirectoryEntry] Table entry
    # @param data [String] Transformed data
    # @return [String] Reconstructed glyf or loca table data
    def reconstruct_glyf_loca(_entry, _data)
      # TODO: Implement full glyf/loca reconstruction
      # This is extremely complex and requires:
      # 1. Parse glyph streams (nContour, nPoints, flags, coords, etc.)
      # 2. Reconstruct standard glyf format
      # 3. Build loca table with proper offsets
      #
      # For now, return empty data to prevent crashes
      # This will need proper implementation for production use
      warn "WOFF2 transformed glyf/loca reconstruction not yet implemented"
      ""
    end

    # Reconstruct hmtx table from WOFF2 transformed format
    #
    # WOFF2 can store hmtx in a more compact format by:
    # - Omitting redundant advance widths
    # - Using flags to indicate presence of LSB array
    #
    # @param entry [Woff2TableDirectoryEntry] Table entry
    # @param data [String] Transformed data
    # @return [String] Reconstructed hmtx table data
    def reconstruct_hmtx(_entry, data)
      # TODO: Implement hmtx reconstruction
      # This requires:
      # 1. Parse flags
      # 2. Reconstruct advance width array
      # 3. Reconstruct LSB array (if present) or derive from glyf
      #
      # For now, return as-is
      warn "WOFF2 transformed hmtx reconstruction not yet implemented"
      data
    end

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

    # Build an SFNT font file (TTF or OTF) from decompressed WOFF2 data
    #
    # @param output_path [String] Path where font will be written
    # @param sfnt_version [Integer] SFNT version
    # @return [Integer] Number of bytes written
    def build_sfnt_font(output_path, sfnt_version)
      File.open(output_path, "wb") do |io|
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
          tag = entry.tag
          data = @decompressed_tables[tag]
          next unless data

          length = data.bytesize

          # Calculate checksum
          checksum = Utilities::ChecksumCalculator.calculate_table_checksum(data)

          table_records << {
            tag: tag,
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
          io.write(record[:tag].ljust(4, "\x00"))
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
      # Calculate file checksum
      checksum = Utilities::ChecksumCalculator.calculate_file_checksum(path)

      # Calculate adjustment
      adjustment = Utilities::ChecksumCalculator.calculate_adjustment(checksum)

      # Find head table position in output file
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
            # Write adjustment to head table (offset 8 within head table)
            File.open(path, "r+b") do |write_io|
              write_io.seek(offset + 8)
              write_io.write([adjustment].pack("N"))
            end
            break
          end
        end
      end
    end
  end
end
