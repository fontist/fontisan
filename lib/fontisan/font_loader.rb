# frozen_string_literal: true

require "stringio"

module Fontisan
  # FontLoader provides unified font loading with content-based format detection.
  #
  # This class is the primary entry point for loading fonts in Fontisan.
  # It inspects each file's magic bytes to determine the on-disk format and
  # returns the appropriate domain object (TrueTypeFont, OpenTypeFont,
  # Type1Font, TrueTypeCollection, or OpenTypeCollection).
  #
  # Detection is purely content-based — the file extension is ignored. This
  # matters because vendors occasionally ship files with a misleading
  # extension (e.g. Apple ships a single OpenType-CFF font as `.ttc` in
  # macOS's private FontServices framework).
  #
  # @example Load any font type
  #   font = FontLoader.load("font.ttf")  # => TrueTypeFont
  #   font = FontLoader.load("font.otf")  # => OpenTypeFont
  #   font = FontLoader.load("font.pfb")  # => Type1Font
  #   font = FontLoader.load("font.pfa")  # => Type1Font
  #   font = FontLoader.load("fonts.ttc") # => TrueTypeFont (first in collection)
  #   font = FontLoader.load("fonts.ttc", font_index: 2) # => TrueTypeFont (third in collection)
  #
  # @example Loading modes
  #   font = FontLoader.load("font.ttf", mode: :metadata)  # Load only metadata tables
  #   font = FontLoader.load("font.ttf", mode: :full)      # Load all tables
  #
  # @example Lazy loading control
  #   font = FontLoader.load("font.ttf", lazy: true)   # Tables loaded on-demand
  #   font = FontLoader.load("font.ttf", lazy: false)  # All tables loaded upfront
  class FontLoader
    # Number of bytes read from the start of a file to identify its format.
    # 100 bytes is enough to comfortably contain the Adobe Type 1 PFA header
    # plus its leading whitespace, and far more than the 4 bytes needed for
    # any SFNT-style or dfont magic.
    PFA_PROBE_LENGTH = 100
    private_constant :PFA_PROBE_LENGTH

    # Map of collection format symbols to the class that loads them. Single
    # source of truth for "what counts as a collection"; both {.collection?}
    # and {.load_collection} dispatch off this table.
    COLLECTION_CLASSES = {
      ttc: TrueTypeCollection,
      otc: OpenTypeCollection,
      dfont: DfontCollection,
    }.freeze
    private_constant :COLLECTION_CLASSES

    # Load a font from file with content-based format detection.
    #
    # The file's bytes determine its format; the extension is ignored. See
    # {.detect_format} for the full list of recognised formats and how they
    # are detected.
    #
    # @param path [String] Path to the font file
    # @param font_index [Integer] Index of font in collection (0-based, default: 0)
    # @param mode [Symbol] Loading mode (:metadata or :full, default: from ENV or :full)
    # @param lazy [Boolean] If true, load tables on demand (default: false for eager loading)
    # @return [TrueTypeFont, OpenTypeFont, Type1Font, WoffFont, Woff2Font] The loaded font object
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [UnsupportedFormatError] for unsupported formats
    # @raise [InvalidFontError] for corrupted or unknown formats
    def self.load(path, font_index: 0, mode: nil, lazy: nil)
      resolved_mode = mode || env_mode || LoadingModes::FULL
      resolved_lazy = if lazy.nil?
                        env_lazy.nil? ? false : env_lazy
                      else
                        lazy
                      end
      LoadingModes.validate_mode!(resolved_mode)

      format = detect(path)
      case format
      when :ttf   then TrueTypeFont.from_file(path, mode: resolved_mode,
                                                    lazy: resolved_lazy)
      when :otf   then OpenTypeFont.from_file(path, mode: resolved_mode,
                                                    lazy: resolved_lazy)
      when :woff  then WoffFont.from_file(path, mode: resolved_mode,
                                                lazy: resolved_lazy)
      when :woff2 then Woff2Font.from_file(path, mode: resolved_mode,
                                                 lazy: resolved_lazy)
      when :ttc, :otc then load_from_collection(path, format, font_index,
                                                mode: resolved_mode)
      when :dfont then load_dfont(path, font_index: font_index,
                                        mode: resolved_mode)
      when :pfa, :pfb then Type1Font.from_file(path, mode: resolved_mode)
      else
        raise InvalidFontError,
              "Unknown font format. Expected TTF, OTF, TTC, OTC, WOFF, WOFF2, PFB, or PFA file."
      end
    end

    # Check if a file is a collection (TTC, OTC, or dfont).
    #
    # Returns `false` for a ttcf-headed file whose inner fonts can't be
    # classified (truncated header, offsets past EOF, unrecognised inner
    # SFNT versions). Such a file is structurally invalid as a collection
    # and would fail to load, so reporting it as "not a collection" matches
    # what callers can actually do with it.
    #
    # @param path [String] Path to the font file
    # @return [Boolean] true if file is a loadable collection
    # @raise [Errno::ENOENT] if file does not exist
    #
    # @example Check if file is collection
    #   FontLoader.collection?("fonts.ttc") # => true
    #   FontLoader.collection?("font.ttf")  # => false
    def self.collection?(path) = COLLECTION_CLASSES.key?(detect(path))

    # Identify a font file by inspecting its magic bytes (content-based detection).
    #
    # Returns the actual on-disk format regardless of the file extension. This
    # is the authoritative way to determine how a file should be parsed,
    # because vendors occasionally ship files with a misleading extension
    # (for example, Apple ships a single OpenType-CFF font as `.ttc` in
    # macOS's private FontServices framework).
    #
    # Collections are distinguished by scanning the inner fonts: if any inner
    # font is OpenType (CFF), the file is reported as `:otc`; otherwise (all
    # inner fonts are TrueType) it is reported as `:ttc`. A ttcf-headed file
    # whose inner fonts can't be classified (truncated header, offsets past
    # EOF, unrecognised inner SFNT versions) returns `nil`. dfont detection
    # uses the canonical resource-data-offset (256) magic only; non-canonical
    # but structurally valid dfonts are accepted by {.load_collection} as a
    # fallback but not reported here.
    #
    # @param path [String] Path to the font file
    # @return [Symbol, nil] One of `:ttf`, `:otf`, `:ttc`, `:otc`, `:woff`,
    #   `:woff2`, `:dfont`, `:pfa`, `:pfb`, or `nil` when the format is not
    #   recognised.
    # @raise [Errno::ENOENT] if the file does not exist
    #
    # @example Detect a real collection
    #   FontLoader.detect_format("fonts.ttc")          # => :ttc
    #
    # @example Detect a single OTF mislabeled as .ttc
    #   FontLoader.detect_format("SauberScript.ttc")   # => :otf
    def self.detect_format(path) = detect(path)

    # Load a collection object without extracting fonts
    #
    # Returns the collection object (TrueTypeCollection, OpenTypeCollection,
    # or DfontCollection) without extracting individual fonts. Useful for
    # inspecting collection metadata and structure.
    #
    # The TTC vs. OTC distinction is resolved by {.detect_format}, which
    # scans the inner fonts; see that method for details.
    #
    # @param path [String] Path to the collection file
    # @return [TrueTypeCollection, OpenTypeCollection, DfontCollection]
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [InvalidFontError] if file is not a collection or type cannot be determined
    #
    # @example Load collection for inspection
    #   collection = FontLoader.load_collection("fonts.ttc")
    #   puts "Collection has #{collection.num_fonts} fonts"
    def self.load_collection(path)
      format = detect(path)
      return COLLECTION_CLASSES.fetch(format).from_file(path) if COLLECTION_CLASSES.key?(format)

      # Lenient fallback: a dfont whose resource-data offset isn't the
      # canonical 256 fails the strict magic test in {.detect} but may still
      # be structurally valid; try the structural check before giving up.
      File.open(path, "rb") do |io|
        return DfontCollection.from_file(path) if Parsers::DfontParser.dfont?(io)
      end
      raise InvalidFontError,
            "File is not a collection (TTC/OTC/dfont). Use FontLoader.load instead."
    end

    # Content-based detection. Reads 4 bytes first (covers every SFNT-style
    # and canonical dfont magic), then tops up to {PFA_PROBE_LENGTH} for
    # Type 1 only on an SFNT miss.
    def self.detect(path)
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      File.open(path, "rb") do |io|
        head4 = io.read(4)
        return nil if head4.nil? || head4.empty?

        sfnt = case head4
               when Constants::TTC_TAG then scan_collection(io)
               when Constants::SFNT_OTTO_MAGIC then :otf
               when Constants::SFNT_TRUETYPE_MAGIC, Constants::SFNT_TRUE_MAGIC then :ttf
               when Constants::WOFF_MAGIC then :woff
               when Constants::WOFF2_MAGIC then :woff2
               when Constants::DFONT_RESOURCE_HEADER
                 io.rewind
                 Parsers::DfontParser.dfont?(io) ? :dfont : nil
               end
        return sfnt if sfnt

        rest = head4.bytesize < PFA_PROBE_LENGTH ? io.read(PFA_PROBE_LENGTH - head4.bytesize) : nil
        type1_format_from_header(rest ? head4 + rest : head4)
      end
    end

    # Identify the Type 1 sub-format (`:pfa` or `:pfb`) from a probe of the
    # file's leading bytes. Returns nil if the bytes don't match Type 1.
    def self.type1_format_from_header(header)
      if header.bytesize >= 2
        marker = (header.getbyte(0) << 8) | header.getbyte(1)
        if [Constants::PFB_ASCII_CHUNK, Constants::PFB_BINARY_CHUNK].include?(marker)
          return :pfb
        end
      end

      # PFA is plain text — the Adobe Type 1 header must appear at the very
      # start (allowing only leading ASCII whitespace), not anywhere in the
      # probe. Using start_with? avoids matching a non-Type-1 PostScript file
      # that happens to mention the signature in a comment.
      stripped = header.lstrip
      if stripped.start_with?(Constants::PFA_SIGNATURE_ADOBE_1_0, Constants::PFA_SIGNATURE_ADOBE_3_0)
        return :pfa
      end

      nil
    end

    # Walk a ttcf-headed file via BaseCollection. Returns `:ttc`, `:otc`, or
    # nil for any truncation, unreadable offset, or unrecognised inner magic.
    def self.scan_collection(io)
      io.rewind
      header = BaseCollection.read(io)
      has_otf = false
      header.font_offsets.each do |offset|
        io.seek(offset)
        case Constants.sfnt_format_for(io.read(4))
        when :otf then has_otf = true
        when :ttf then next
        else return nil
        end
      end
      has_otf ? :otc : :ttc
    rescue BinData::ValidityError, IOError
      nil
    end

    # Mode override from FONTISAN_MODE env var, or nil.
    def self.env_mode
      env_value = ENV["FONTISAN_MODE"]
      return nil unless env_value

      mode = env_value.to_sym
      LoadingModes.valid_mode?(mode) ? mode : nil
    end

    # Lazy override from FONTISAN_LAZY env var, or nil.
    def self.env_lazy
      env_value = ENV["FONTISAN_LAZY"]
      return nil unless env_value

      env_value.downcase == "true"
    end

    # Load a single font from a TTC/OTC collection. `format` is the detected
    # symbol routed from `.load`'s case statement, so no second magic read.
    def self.load_from_collection(path, format, font_index, mode:)
      collection = COLLECTION_CLASSES.fetch(format).from_file(path)
      if font_index >= collection.num_fonts
        raise InvalidFontError,
              "Font index #{font_index} out of range (collection has #{collection.num_fonts} fonts)"
      end

      File.open(path, "rb") { |io| collection.font(font_index, io, mode: mode) }
    end

    # Extract an SFNT from a dfont resource fork into memory and load it via
    # `SfntFont.from_collection` so the loading-mode handling matches the
    # TTC/OTC path. Lazy loading is a no-op for in-memory StringIO so the
    # public `lazy:` flag is not threaded through this path.
    def self.load_dfont(path, font_index:, mode:)
      File.open(path, "rb") do |io|
        sfnt_io = StringIO.new(Parsers::DfontParser.extract_sfnt(io,
                                                                 index: font_index))
        klass = case Constants.sfnt_format_for(sfnt_io.read(4))
                when :ttf then TrueTypeFont
                when :otf then OpenTypeFont
                else raise InvalidFontError, "Invalid SFNT in dfont resource"
                end
        klass.from_collection(sfnt_io, 0, mode: mode)
      end
    end

    private_class_method :detect,
                         :type1_format_from_header,
                         :scan_collection,
                         :env_mode,
                         :env_lazy,
                         :load_from_collection,
                         :load_dfont
  end
end
