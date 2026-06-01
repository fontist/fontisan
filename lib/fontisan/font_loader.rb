# frozen_string_literal: true

require_relative "constants"
require_relative "loading_modes"
require_relative "true_type_font"
require_relative "open_type_font"
require_relative "true_type_collection"
require_relative "open_type_collection"
require_relative "dfont_collection"
require_relative "woff_font"
require_relative "woff2_font"
require_relative "type1_font"
require_relative "parsers/dfont_parser"
require_relative "error"

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

    # Map of single-font format symbols to the class that loads them.
    SFNT_FONT_CLASSES = {
      ttf: TrueTypeFont,
      otf: OpenTypeFont,
      woff: WoffFont,
      woff2: Woff2Font,
    }.freeze
    private_constant :SFNT_FONT_CLASSES

    # Map of collection format symbols to the class that loads them. The keys
    # are the single source of truth for "what counts as a collection"; both
    # {.collection?} and {.load_collection} dispatch off this table.
    COLLECTION_CLASSES = {
      ttc: TrueTypeCollection,
      otc: OpenTypeCollection,
      dfont: DfontCollection,
    }.freeze
    private_constant :COLLECTION_CLASSES

    # Collection formats whose inner fonts share the ttcf header layout, so
    # they're loaded through {.load_from_collection}. `:dfont` lives in
    # {COLLECTION_CLASSES} but takes a different load path (a resource-fork
    # extractor), so it's not in this subset.
    TTCF_FORMATS = %i[ttc otc].freeze
    private_constant :TTCF_FORMATS

    # 4-byte magics that count as TrueType when scanning either a top-level
    # SFNT signature or an inner font in a ttcf collection. Apple ships both
    # the canonical 0x00010000 magic and the legacy ASCII "true" magic.
    TRUETYPE_MAGICS = [
      Constants::SFNT_TRUETYPE_MAGIC,
      Constants::SFNT_TRUE_MAGIC,
    ].freeze
    private_constant :TRUETYPE_MAGICS

    # Result of content-based format detection.
    #
    # For a ttcf-headed collection, `num_fonts` carries the parsed inner-font
    # count so callers can validate `font_index` without re-reading the
    # header. For non-collections (or for malformed/unrecognised inputs),
    # `num_fonts` is nil.
    DetectionResult = Struct.new(:format, :num_fonts)
    private_constant :DetectionResult

    # Sentinel for "could not identify this file" — returned by every
    # detection path that gives up, so each one doesn't allocate a fresh
    # `DetectionResult.new(nil, nil)`.
    UNRECOGNISED = DetectionResult.new(nil, nil).freeze
    private_constant :UNRECOGNISED

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
      detection = detect(path)

      resolved_mode = mode || env_mode || LoadingModes::FULL
      resolved_lazy = if lazy.nil?
                        env_lazy.nil? ? false : env_lazy
                      else
                        lazy
                      end
      LoadingModes.validate_mode!(resolved_mode)

      case detection.format
      when :pfa, :pfb
        Type1Font.from_file(path, mode: resolved_mode)
      when *SFNT_FONT_CLASSES.keys
        SFNT_FONT_CLASSES.fetch(detection.format)
          .from_file(path, mode: resolved_mode, lazy: resolved_lazy)
      when *TTCF_FORMATS
        load_from_collection(path, detection, font_index, mode: resolved_mode)
      when :dfont
        load_dfont(path, font_index, resolved_mode, resolved_lazy)
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
    def self.collection?(path)
      COLLECTION_CLASSES.key?(detect(path).format)
    end

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
    # EOF, unrecognised inner SFNT versions) returns `nil`.
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
    def self.detect_format(path)
      detect(path).format
    end

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
      format = detect(path).format

      case format
      when *COLLECTION_CLASSES.keys
        COLLECTION_CLASSES.fetch(format).from_file(path)
      else
        # Lenient fallback: a dfont whose resource-data offset isn't the
        # canonical 256 fails the strict magic test in {.detect} but may
        # still be structurally valid. Try the structural check before
        # giving up.
        File.open(path, "rb") do |io|
          return DfontCollection.from_file(path) if Parsers::DfontParser.dfont?(io)
        end
        raise InvalidFontError,
              "File is not a collection (TTC/OTC/dfont). Use FontLoader.load instead."
      end
    end

    # Run content-based detection once and return the full result. This is
    # the single source of truth for the file's format and, for ttcf
    # collections, the parsed `num_fonts`. Consumers use the returned struct
    # instead of re-scanning the file.
    #
    # @param path [String]
    # @return [DetectionResult]
    # @raise [Errno::ENOENT] if the file does not exist
    # @api private
    def self.detect(path)
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      File.open(path, "rb") do |io|
        header = io.read(PFA_PROBE_LENGTH)
        return UNRECOGNISED if header.nil? || header.empty?

        type1 = type1_format_from_header(header)
        return DetectionResult.new(type1, nil) if type1

        return UNRECOGNISED if header.bytesize < 4

        sfnt_detection(header.byteslice(0, 4), io)
      end
    end

    # Identify the Type 1 sub-format (`:pfa` or `:pfb`) from a probe of the
    # file's leading bytes. Returns nil if the bytes don't match Type 1.
    #
    # @param header [String] First ~100 bytes of the file (binary)
    # @return [Symbol, nil]
    # @api private
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

    # Map a 4-byte SFNT-style signature to a DetectionResult. For `ttcf`
    # files, scans the inner fonts (and carries `num_fonts` through); for
    # dfont magic, delegates to {Parsers::DfontParser.dfont?} for structural
    # validation.
    #
    # @param signature [String] 4-byte binary signature
    # @param io [IO] open IO positioned anywhere (will be seeked as needed)
    # @return [DetectionResult]
    # @api private
    def self.sfnt_detection(signature, io)
      case signature
      when Constants::TTC_TAG
        scan_collection(io)
      when *TRUETYPE_MAGICS
        DetectionResult.new(:ttf, nil)
      when Constants::SFNT_OTTO_MAGIC
        DetectionResult.new(:otf, nil)
      when Constants::WOFF_MAGIC
        DetectionResult.new(:woff, nil)
      when Constants::WOFF2_MAGIC
        DetectionResult.new(:woff2, nil)
      when Constants::DFONT_RESOURCE_HEADER
        io.rewind
        DetectionResult.new(Parsers::DfontParser.dfont?(io) ? :dfont : nil, nil)
      else
        UNRECOGNISED
      end
    end

    # Scan a ttcf-headed file: read num_fonts, the offset table, and every
    # inner SFNT magic. All comparisons are bytes-domain against
    # `Constants::SFNT_*_MAGIC`, so detection is the single authority on
    # what counts as a valid inner SFNT and no caller has to re-validate.
    #
    # Returns a DetectionResult with `:ttc` or `:otc` and `num_fonts` set
    # when every inner font has a recognised magic; returns `UNRECOGNISED`
    # for any truncation, unreadable offset, or unknown inner magic —
    # those collections are not loadable and callers should reject them.
    #
    # @param io [IO] open IO on a `ttcf`-headed file
    # @return [DetectionResult]
    # @api private
    def self.scan_collection(io)
      io.seek(8) # skip tag (4) + version (4)

      num_fonts_bytes = io.read(4)
      return UNRECOGNISED if num_fonts_bytes.nil? || num_fonts_bytes.bytesize < 4

      num_fonts = num_fonts_bytes.unpack1("N")
      return UNRECOGNISED if num_fonts.zero?

      offset_bytes = io.read(4 * num_fonts)
      return UNRECOGNISED if offset_bytes.nil? || offset_bytes.bytesize < 4 * num_fonts

      offsets = offset_bytes.unpack("N#{num_fonts}")

      has_otf = false
      offsets.each do |offset|
        io.seek(offset)
        sfnt = io.read(4)
        return UNRECOGNISED if sfnt.nil? || sfnt.bytesize < 4

        case sfnt
        when Constants::SFNT_OTTO_MAGIC
          has_otf = true
        when *TRUETYPE_MAGICS
          next
        else
          return UNRECOGNISED
        end
      end

      DetectionResult.new(has_otf ? :otc : :ttc, num_fonts)
    end

    # Get mode from environment variable
    #
    # @return [Symbol, nil] Mode from FONTISAN_MODE or nil
    # @api private
    def self.env_mode
      env_value = ENV["FONTISAN_MODE"]
      return nil unless env_value

      mode = env_value.to_sym
      LoadingModes.valid_mode?(mode) ? mode : nil
    end

    # Get lazy setting from environment variable
    #
    # @return [Boolean, nil] Lazy setting from FONTISAN_LAZY or nil if not set
    # @api private
    def self.env_lazy
      env_value = ENV["FONTISAN_LAZY"]
      return nil unless env_value

      env_value.downcase == "true"
    end

    # Load an inner font from a TTC/OTC collection using the already-parsed
    # DetectionResult. `num_fonts` is known, so no header re-read; the
    # collection class is a direct lookup in {COLLECTION_CLASSES}.
    #
    # @param path [String] Path to the collection file
    # @param detection [DetectionResult] Result from {.detect}
    # @param font_index [Integer] Index of font to extract
    # @param mode [Symbol] Loading mode (:metadata or :full)
    # @return [TrueTypeFont, OpenTypeFont]
    # @raise [InvalidFontError] if font_index is out of range
    # @api private
    def self.load_from_collection(path, detection, font_index, mode:)
      if font_index >= detection.num_fonts
        raise InvalidFontError,
              "Font index #{font_index} out of range (collection has #{detection.num_fonts} fonts)"
      end

      collection = COLLECTION_CLASSES.fetch(detection.format).from_file(path)
      File.open(path, "rb") { |io| collection.font(font_index, io, mode: mode) }
    end

    # Open a dfont file and extract the requested inner font. Owns the
    # file-open boundary so {.load}'s top-level dispatch stays IO-free and
    # symmetric with the other format arms.
    #
    # @param path [String] Path to dfont file
    # @param font_index [Integer] Font index in suitcase
    # @param mode [Symbol] Loading mode
    # @param lazy [Boolean] Lazy loading flag
    # @return [TrueTypeFont, OpenTypeFont]
    # @api private
    def self.load_dfont(path, font_index, mode, lazy)
      File.open(path, "rb") do |io|
        extract_and_load_dfont(io, font_index, mode, lazy)
      end
    end

    # Extract and load font from dfont resource fork
    #
    # @param io [IO] Open file handle
    # @param font_index [Integer] Font index in suitcase
    # @param mode [Symbol] Loading mode
    # @param lazy [Boolean] Lazy loading flag
    # @return [TrueTypeFont, OpenTypeFont] Loaded font
    # @api private
    def self.extract_and_load_dfont(io, font_index, mode, lazy)
      sfnt_data = Parsers::DfontParser.extract_sfnt(io, index: font_index)
      sfnt_io = StringIO.new(sfnt_data)

      signature = sfnt_io.read(4)
      sfnt_io.rewind

      klass = case signature
              when *TRUETYPE_MAGICS
                TrueTypeFont
              when Constants::SFNT_OTTO_MAGIC
                OpenTypeFont
              else
                raise InvalidFontError,
                      "Invalid SFNT data in dfont resource (signature: #{signature.inspect})"
              end

      build_sfnt_font(klass, sfnt_io, mode, lazy)
    end

    # Read an SFNT font from an IO using the given class and apply the
    # loading-mode / lazy-load configuration. Used by {.extract_and_load_dfont}
    # to keep the TT and OT branches free of duplication.
    #
    # @param klass [Class] TrueTypeFont or OpenTypeFont
    # @param sfnt_io [IO] IO positioned at the start of the SFNT data
    # @param mode [Symbol] Loading mode
    # @param lazy [Boolean] If true, defer table reads
    # @return [TrueTypeFont, OpenTypeFont]
    # @api private
    def self.build_sfnt_font(klass, sfnt_io, mode, lazy)
      klass.read(sfnt_io).tap do |font|
        font.initialize_storage
        font.loading_mode = mode
        font.lazy_load_enabled = lazy
        font.read_table_data(sfnt_io) unless lazy
      end
    end

    # All internal helpers — declared in one place so it's obvious at a
    # glance what's public surface (load, collection?, detect_format,
    # load_collection) vs. private machinery.
    private_class_method :detect,
                         :type1_format_from_header,
                         :sfnt_detection,
                         :scan_collection,
                         :env_mode,
                         :env_lazy,
                         :load_from_collection,
                         :load_dfont,
                         :extract_and_load_dfont,
                         :build_sfnt_font
  end
end
