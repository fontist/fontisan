# frozen_string_literal: true

require "bindata"
require "brotli"
require "stringio"
require_relative "constants"
require_relative "loading_modes"
require_relative "utilities/checksum_calculator"
require_relative "woff2/header"
require_relative "woff2/glyf_transformer"
require_relative "woff2/hmtx_transformer"
require_relative "true_type_font"
require_relative "open_type_font"
require_relative "error"

module Fontisan
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
      # Don't initialize transform_version - leave it nil
      # It will be set during parsing if table is transformed
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

  # Web Open Font Format 2.0 (WOFF2) font loader
  #
  # This class manages WOFF2 font files and provides access to
  # decompressed tables and transformed data.
  #
  # @example Reading a WOFF2 font
  #   font = Woff2Font.from_file("font.woff2")
  #   puts font.header.flavor
  #   puts font.table_names
  class Woff2Font
    # Simple struct for storing file path
    IOSource = Struct.new(:path)

    attr_accessor :header, :table_entries, :decompressed_tables, :parsed_tables, :io_source, :underlying_font # Allow both reading and setting for table delegation

    def initialize
      @header = nil
      @table_entries = []
      @decompressed_tables = {}
      @parsed_tables = {}
      @io_source = nil
      @underlying_font = nil # Store the actual TrueTypeFont/OpenTypeFont
    end

    # Initialize storage hashes
    def initialize_storage
      @decompressed_tables ||= {}
      @initialize_storage ||= {}
    end

    # Check if font has TrueType flavor
    def truetype?
      return false unless @header

      [Constants::SFNT_VERSION_TRUETYPE, 0x00010000].include?(@header.flavor)
    end

    # Check if font has CFF flavor
    def cff?
      return false unless @header

      [Constants::SFNT_VERSION_OTTO, 0x4F54544F].include?(@header.flavor)
    end

    # Check if font is a variable font
    #
    # @return [Boolean] true if font has fvar table (variable font)
    def variable_font?
      has_table?("fvar")
    end

    # Validate WOFF2 signature
    def validate_signature!
      unless @header && @header.signature == Woff2::Woff2Header::SIGNATURE
        raise InvalidFontError, "Invalid WOFF2 signature"
      end
    end

    # Check if font is valid
    def valid?
      return false unless @header
      return false unless @header.signature == Woff2::Woff2Header::SIGNATURE
      return false unless @header.num_tables == @table_entries.length
      return false unless has_table?("head")

      true
    end

    # Check if table exists
    def has_table?(tag)
      @table_entries.any? { |entry| entry.tag == tag }
    end

    # Find table entry by tag
    def find_table_entry(tag)
      @table_entries.find { |entry| entry.tag == tag }
    end

    # Get list of table tags
    def table_names
      @table_entries.map(&:tag)
    end

    # Get decompressed table data
    #
    # @param tag [String, nil] The table tag (optional)
    # @return [String, Hash, nil] Table data if tag provided, or hash of all tables if no tag
    def table_data(tag = nil)
      # If no tag provided, return all tables
      if tag.nil?
        # First try underlying font's table data if available
        if @underlying_font.respond_to?(:table_data)
          return @underlying_font.table_data
        end

        # Fallback to decompressed_tables
        return @decompressed_tables
      end

      # Tag provided - return specific table
      # First try underlying font's table data if available
      if @underlying_font.respond_to?(:table_data)
        underlying_data = @underlying_font.table_data[tag]
        return underlying_data if underlying_data
      end

      # Fallback to decompressed_tables
      @decompressed_tables[tag]
    end

    # Get parsed table object
    def table(tag)
      # Delegate to underlying font if available
      return @underlying_font.table(tag) if @underlying_font

      # Fallback to parsed_tables hash
      # Normalize tag to UTF-8 string for hash lookup
      tag_key = tag.to_s
      tag_key.force_encoding("UTF-8") unless tag_key.encoding == Encoding::UTF_8
      @parsed_tables[tag_key]
    end

    # Convert to TTF
    def to_ttf(output_path)
      unless truetype?
        raise InvalidFontError,
              "Cannot convert to TTF: font is not TrueType flavored"
      end

      # Build SFNT and create TrueTypeFont
      sfnt_data = self.class.build_sfnt_in_memory(@header, @table_entries,
                                                  @decompressed_tables)
      sfnt_io = StringIO.new(sfnt_data)

      # Create actual TrueTypeFont and save for table delegation
      @underlying_font = TrueTypeFont.read(sfnt_io)
      @underlying_font.initialize_storage
      @underlying_font.read_table_data(sfnt_io)

      FontWriter.write_to_file(@underlying_font.tables, output_path)
    end

    # Convert to OTF
    def to_otf(output_path)
      unless cff?
        raise InvalidFontError,
              "Cannot convert to OTF: font is not CFF flavored"
      end

      # Build SFNT and create OpenTypeFont
      sfnt_data = self.class.build_sfnt_in_memory(@header, @table_entries,
                                                  @decompressed_tables)
      sfnt_io = StringIO.new(sfnt_data)

      # Create actual OpenTypeFont and save for table delegation
      @underlying_font = OpenTypeFont.read(sfnt_io)
      @underlying_font.initialize_storage
      @underlying_font.read_table_data(sfnt_io)

      FontWriter.write_to_file(@underlying_font.tables, output_path)
    end

    # Get metadata (if present)
    def metadata
      return nil unless @header&.meta_length&.positive?
      return nil unless @io_source

      begin
        File.open(@io_source.path, "rb") do |io|
          io.seek(@header.meta_offset)
          compressed_meta = io.read(@header.meta_length)
          Brotli.inflate(compressed_meta)
        end
      rescue StandardError => e
        warn "Failed to decompress metadata: #{e.message}"
        nil
      end
    end

    # Convenience methods for accessing common name table fields

    # Get font family name
    def family_name
      name_table = table("name")
      name_table&.english_name(Tables::Name::FAMILY)
    end

    # Get font subfamily name
    def subfamily_name
      name_table = table("name")
      name_table&.english_name(Tables::Name::SUBFAMILY)
    end

    # Get full font name
    def full_name
      name_table = table("name")
      name_table&.english_name(Tables::Name::FULL_NAME)
    end

    # Get PostScript name
    def post_script_name
      name_table = table("name")
      name_table&.english_name(Tables::Name::POSTSCRIPT_NAME)
    end

    # Get preferred family name
    def preferred_family_name
      name_table = table("name")
      name_table&.english_name(Tables::Name::PREFERRED_FAMILY)
    end

    # Get preferred subfamily name
    def preferred_subfamily_name
      name_table = table("name")
      name_table&.english_name(Tables::Name::PREFERRED_SUBFAMILY)
    end

    # Get units per em
    def units_per_em
      head = table("head")
      head&.units_per_em
    end

    # Read WOFF2 font from a file and return Woff2Font instance
    #
    # @param path [String] Path to the WOFF2 file
    # @param mode [Symbol] Loading mode (:metadata or :full)
    # @param lazy [Boolean] If true, load tables on demand
    # @return [Woff2Font] The WOFF2 font object
    # @raise [ArgumentError] if path is nil or empty
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [InvalidFontError] if file format is invalid
    def self.from_file(path, mode: LoadingModes::FULL, lazy: false)
      if path.nil? || path.to_s.empty?
        raise ArgumentError, "path cannot be nil or empty"
      end
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      woff2 = new
      woff2.io_source = IOSource.new(path)

      File.open(path, "rb") do |io|
        # Read header to determine font flavor
        woff2.header = Woff2::Woff2Header.read(io)

        # Validate signature
        unless woff2.header.signature == Woff2::Woff2Header::SIGNATURE
          raise InvalidFontError,
                "Invalid WOFF2 signature: expected 0x#{Woff2::Woff2Header::SIGNATURE.to_s(16)}, " \
                "got 0x#{woff2.header.signature.to_i.to_s(16)}"
        end

        # Read table directory
        woff2.table_entries = read_table_directory_from_io(io, woff2.header)

        # Decompress table data
        woff2.decompressed_tables = decompress_tables(io, woff2.header,
                                                      woff2.table_entries)

        # Apply table transformations if present
        apply_transformations!(woff2.table_entries, woff2.decompressed_tables)

        # Build SFNT structure in memory
        sfnt_data = build_sfnt_in_memory(woff2.header, woff2.table_entries,
                                         woff2.decompressed_tables)

        # Create StringIO for reading
        sfnt_io = StringIO.new(sfnt_data)
        sfnt_io.rewind

        # Parse tables based on font type
        if woff2.truetype?
          font = TrueTypeFont.read(sfnt_io)
          font.initialize_storage
          font.loading_mode = mode
          font.lazy_load_enabled = lazy

          # Create fresh StringIO for table data reading
          table_io = StringIO.new(sfnt_data)
          font.read_table_data(table_io)

          # Store underlying font for table access delegation
          woff2.underlying_font = font
          woff2.parsed_tables = font.parsed_tables
        elsif woff2.cff?
          font = OpenTypeFont.read(sfnt_io)
          font.initialize_storage
          font.loading_mode = mode
          font.lazy_load_enabled = lazy

          # Create fresh StringIO for table data reading
          table_io = StringIO.new(sfnt_data)
          font.read_table_data(table_io)

          # Store underlying font for table access delegation
          woff2.underlying_font = font
          woff2.parsed_tables = font.parsed_tables
        else
          raise InvalidFontError,
                "Unknown WOFF2 flavor: 0x#{woff2.header.flavor.to_s(16)}"
        end
      end

      woff2
    rescue BinData::ValidityError, EOFError => e
      raise InvalidFontError, "Invalid WOFF2 file: #{e.message}"
    end

    # Read table directory from IO
    #
    # @param io [IO] Open file handle
    # @param header [Woff2::Woff2Header] WOFF2 header
    # @return [Array<Woff2TableDirectoryEntry>] Table entries
    def self.read_table_directory_from_io(io, header)
      table_entries = []

      header.num_tables.times do
        entry = Woff2TableDirectoryEntry.new

        # Read flags byte with nil check
        flags_data = io.read(1)
        if flags_data.nil?
          raise EOFError,
                "Unexpected EOF while reading table directory flags"
        end

        flags = flags_data.unpack1("C")
        entry.flags = flags

        # Determine tag
        tag_index = flags & 0x3F
        if tag_index == 0x3F
          # Custom tag (4 bytes)
          tag_data = io.read(4)
          if tag_data.nil? || tag_data.bytesize < 4
            raise EOFError,
                  "Unexpected EOF while reading custom tag"
          end

          entry.tag = tag_data.force_encoding("UTF-8")
        else
          # Known tag from table
          entry.tag = Woff2TableDirectoryEntry::KNOWN_TAGS[tag_index]
          unless entry.tag
            raise InvalidFontError, "Invalid table tag index: #{tag_index}"
          end
        end

        # Read orig_length (UIntBase128)
        entry.orig_length = read_uint_base128_from_io(io)

        # Determine if transformLength should be read
        # According to WOFF2 spec section 4.2:
        # - transformLength is ONLY present when table is actually transformed
        # - For glyf/loca: transformation is indicated by transform_version = 0
        # - For hmtx: transformation is indicated by transform_version = 1
        # - For all other tables: no transformation, no transformLength
        transform_version = (flags >> 6) & 0x03

        # transformLength is present when table is actually transformed
        # glyf/loca use version 0 for transformation, hmtx uses version 1
        has_transform_length = if ["glyf", "loca"].include?(entry.tag)
                                 # For glyf/loca, version 0 means transformed
                                 transform_version.zero?
                               elsif entry.tag == "hmtx"
                                 # For hmtx, version 1 means transformed
                                 transform_version == 1
                               else
                                 false
                               end

        if has_transform_length
          entry.transform_length = read_uint_base128_from_io(io)
          entry.transform_version = transform_version
        end

        table_entries << entry
      end

      table_entries
    end

    # Read variable-length UIntBase128 integer from IO
    #
    # @param io [IO] Open file handle
    # @return [Integer] The decoded integer value
    def self.read_uint_base128_from_io(io)
      result = 0
      5.times do
        byte_data = io.read(1)
        if byte_data.nil?
          raise EOFError,
                "Unexpected EOF while reading UIntBase128"
        end

        byte = byte_data.unpack1("C")

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

    # Decompress tables from WOFF2 compressed data block
    #
    # @param io [IO] Open file handle
    # @param header [Woff2::Woff2Header] WOFF2 header
    # @param table_entries [Array<Woff2TableDirectoryEntry>] Table entries
    # @return [Hash<String, String>] Map of tag to decompressed data
    def self.decompress_tables(io, header, table_entries)
      # IO stream is already positioned at compressed data after reading table directory
      # No need to seek - just read from current position
      compressed_data = io.read(header.total_compressed_size)

      # Decompress entire data block with Brotli
      decompressed_data = Brotli.inflate(compressed_data)

      # Split decompressed data into individual tables
      decompressed_tables = {}
      offset = 0

      table_entries.each do |entry|
        table_size = entry.transform_length || entry.orig_length
        table_data = decompressed_data[offset, table_size]
        offset += table_size

        decompressed_tables[entry.tag] = table_data
      end

      decompressed_tables
    end

    # Apply table transformations for glyf/loca/hmtx tables
    #
    # @param table_entries [Array<Woff2TableDirectoryEntry>] Table entries
    # @param decompressed_tables [Hash<String, String>] Decompressed tables
    # @return [void] Modifies decompressed_tables in place
    def self.apply_transformations!(table_entries, decompressed_tables)
      # Find entries that need transformation
      glyf_entry = table_entries.find { |e| e.tag == "glyf" }
      hmtx_entry = table_entries.find { |e| e.tag == "hmtx" }

      # Get required metadata for transformations
      maxp_data = decompressed_tables["maxp"]
      hhea_data = decompressed_tables["hhea"]

      return unless maxp_data && hhea_data

      # Parse num_glyphs from maxp table
      # maxp format: version(4) + numGlyphs(2) + ...
      num_glyphs = maxp_data[4, 2].unpack1("n")

      # Parse numberOfHMetrics from hhea table
      # hhea format: ... + numberOfHMetrics(2) at offset 34
      number_of_h_metrics = hhea_data[34, 2].unpack1("n")

      # Check if this is a variable font by checking for fvar table
      variable_font = table_entries.any? { |e| e.tag == "fvar" }

      # Transform glyf/loca if needed
      # transform_length is only set when table is actually transformed
      # Check that transform_length exists and is greater than 0
      if glyf_entry&.instance_variable_defined?(:@transform_length) &&
          glyf_entry.transform_length&.positive?
        transformed_glyf = decompressed_tables["glyf"]

        if transformed_glyf
          result = Woff2::GlyfTransformer.reconstruct(
            transformed_glyf,
            num_glyphs,
            variable_font: variable_font,
          )
          decompressed_tables["glyf"] = result[:glyf]
          decompressed_tables["loca"] = result[:loca]
        end
      end

      # Transform hmtx if needed
      # transform_length is only set when table is actually transformed
      # Check that transform_length exists and is greater than 0
      if hmtx_entry&.instance_variable_defined?(:@transform_length) &&
          hmtx_entry.transform_length&.positive?
        transformed_hmtx = decompressed_tables["hmtx"]

        if transformed_hmtx
          decompressed_tables["hmtx"] = Woff2::HmtxTransformer.reconstruct(
            transformed_hmtx,
            num_glyphs,
            number_of_h_metrics,
          )
        end
      end
    end

    # Calculate size of table directory
    #
    # @param table_entries [Array<Woff2TableDirectoryEntry>] Table entries
    # @return [Integer] Size in bytes
    def self.calculate_table_directory_size(table_entries)
      size = 0
      table_entries.each do |entry|
        size += 1 # flags byte

        # Tag (4 bytes if custom, 0 if known)
        tag_index = entry.flags & 0x3F
        size += 4 if tag_index == 0x3F

        # orig_length (UIntBase128) - estimate
        size += uint_base128_size(entry.orig_length)

        # transform_length if present
        if entry.transform_version && !entry.transform_version.nil?
          size += uint_base128_size(entry.transform_length)
        end
      end
      size
    end

    # Estimate size of UIntBase128 encoded value
    #
    # @param value [Integer] The value to encode
    # @return [Integer] Estimated size in bytes
    def self.uint_base128_size(value)
      return 1 if value < 128

      bytes = 0
      v = value
      while v.positive?
        bytes += 1
        v >>= 7
      end
      [
        bytes,
        5,
      ].min # Max 5 bytes
    end

    # Build SFNT binary structure in memory
    #
    # @param header [Woff2::Woff2Header] WOFF2 header
    # @param table_entries [Array<Woff2TableDirectoryEntry>] Table entries
    # @param decompressed_tables [Hash<String, String>] Decompressed table data
    # @return [String] Complete SFNT binary data
    def self.build_sfnt_in_memory(header, table_entries, decompressed_tables)
      sfnt_data = +""

      # Calculate offset table fields
      num_tables = table_entries.length
      entry_selector = (Math.log(num_tables) / Math.log(2)).floor
      search_range = (2**entry_selector) * 16
      range_shift = num_tables * 16 - search_range

      # Write offset table
      sfnt_data << [header.flavor].pack("N")
      sfnt_data << [num_tables].pack("n")
      sfnt_data << [search_range].pack("n")
      sfnt_data << [entry_selector].pack("n")
      sfnt_data << [range_shift].pack("n")

      # Calculate table offsets
      offset = 12 + (num_tables * 16) # Header + directory
      table_records = []

      table_entries.each do |entry|
        tag = entry.tag
        data = decompressed_tables[tag]
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

      # Write table directory (all entries first)
      # rubocop:disable Style/CombinableLoops - Must write directory entries first, then data
      table_records.each do |record|
        sfnt_data << record[:tag].ljust(4, "\x00")
        sfnt_data << [record[:checksum]].pack("N")
        sfnt_data << [record[:offset]].pack("N")
        sfnt_data << [record[:length]].pack("N")
      end

      # Then write all table data with padding
      table_records.each do |record|
        sfnt_data << record[:data]

        # Add padding
        padding = (Constants::TABLE_ALIGNMENT - (record[:length] % Constants::TABLE_ALIGNMENT)) %
          Constants::TABLE_ALIGNMENT
        sfnt_data << ("\x00" * padding) if padding.positive?
      end
      # rubocop:enable Style/CombinableLoops

      # Update checksumAdjustment in head table
      update_checksum_in_memory(sfnt_data, table_records)

      sfnt_data
    end

    # Update checksumAdjustment field in head table in memory
    #
    # @param sfnt_data [String] The SFNT binary data
    # @param table_records [Array<Hash>] Table records with offsets
    # @return [void]
    def self.update_checksum_in_memory(sfnt_data, table_records)
      # Find head table record
      head_record = table_records.find { |r| r[:tag] == Constants::HEAD_TAG }
      return unless head_record

      # Zero out checksumAdjustment field first
      head_offset = head_record[:offset]
      sfnt_data[head_offset + 8, 4] = "\x00\x00\x00\x00"

      # Calculate file checksum
      checksum = 0
      sfnt_data.bytes.each_slice(4) do |bytes|
        word = bytes.pack("C*").ljust(4, "\x00").unpack1("N")
        checksum = (checksum + word) & 0xFFFFFFFF
      end

      # Calculate adjustment
      adjustment = (0xB1B0AFBA - checksum) & 0xFFFFFFFF

      # Write adjustment to head table
      sfnt_data[head_offset + 8, 4] = [adjustment].pack("N")
    end

    private

    # Read variable-length UIntBase128 integer from IO
    def read_uint_base128(io)
      self.class.read_uint_base128_from_io(io)
    end

    # Read 255UInt16 variable-length integer
    def read_255_uint16(io)
      code = io.read(1).unpack1("C")

      case code
      when 0..252
        code
      when 253
        253 + io.read(1).unpack1("C")
      when 254
        io.read(2).unpack1("n")
      when 255
        io.read(2).unpack1("n") + 506
      end
    end

    # Calculate offset table fields
    def calculate_offset_table_fields(num_tables)
      entry_selector = (Math.log(num_tables) / Math.log(2)).floor
      search_range = (2**entry_selector) * 16
      range_shift = num_tables * 16 - search_range

      [search_range, entry_selector, range_shift]
    end
  end
end
