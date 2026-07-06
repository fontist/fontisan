# frozen_string_literal: true

require "stringio"

module Fontisan
  # WOFF2 font collection (spec section 4.2).
  #
  # Wraps a WOFF2 collection file (flavor='ttcf') and exposes the same
  # interface as `TrueTypeCollection`/`OpenTypeCollection` so collection
  # consumers don't need to know which container format they're holding.
  #
  # Unlike TTC/OTC (which subclass `BaseCollection` for BinData parsing),
  # WOFF2 collections are decoded eagerly via `Woff2::CollectionDecoder`
  # because the per-font tables require Brotli decompression +
  # glyf/loca reconstruction before they can be returned.
  class Woff2Collection
    include Collection::SharedLogic

    # @return [String] Source WOFF2 binary
    attr_reader :data

    # @param data [String] WOFF2 collection binary
    def initialize(data)
      @data = data.force_encoding(Encoding::BINARY)
    end

    # Load a WOFF2 collection from a file path.
    #
    # @param path [String]
    # @return [Woff2Collection]
    def self.from_file(path)
      new(File.binread(path))
    end

    # Number of fonts in the collection.
    #
    # @return [Integer]
    def num_fonts
      decoded.length
    end
    alias font_count num_fonts

    # Per-font synthetic offsets. WOFF2 collections don't have byte offsets
    # like TTC (each font is reconstructed in memory); the index is the
    # only identifier. Returned for compatibility with `BaseCollection`'s
    # interface.
    #
    # @return [Array<Integer>] 0..num_fonts-1
    def font_offsets
      (0...num_fonts).to_a
    end

    # Extract every font in the collection.
    #
    # @param _io [IO, nil] Ignored — WOFF2 collections decode in memory.
    # @return [Array<TrueTypeFont, OpenTypeFont>]
    def extract_fonts(_io = nil)
      decoded.map { |entry| build_font(entry) }
    end

    # Get a single font by index.
    #
    # @param index [Integer] 0-based font index
    # @param _io [IO, nil] Ignored.
    # @param _mode [Symbol] Ignored — full mode only (WOFF2 collections are
    #   decoded eagerly).
    # @return [TrueTypeFont, OpenTypeFont, nil] nil if index out of range
    def font(index, _io = nil, _mode: LoadingModes::FULL)
      return nil if index >= num_fonts

      build_font(decoded[index])
    end

    # Whether this object represents a font collection. WOFF2 collections
    # are always collections.
    #
    # @return [Boolean]
    def collection? = true

    # Collections have no single SFNT table directory.
    #
    # @return [Array<String>] empty
    def table_names = []

    # Validate format correctness.
    #
    # @return [Boolean]
    def valid?
      flavor = @data[4, 4].unpack1("N")
      flavor == Woff2::CollectionDecoder::TTC_FLAVOR
    rescue StandardError
      false
    end

    # High-level pipeline format identifier. Owned by the collection class
    # so the conversion pipeline can dispatch without case statements.
    #
    # @return [Symbol] :woff2_collection
    def format = :woff2_collection

    private

    # Lazily decoded collection entries (one Hash per font).
    def decoded
      @decoded ||= Woff2::CollectionDecoder.new(@data).decode
    end

    # Build a TrueTypeFont or OpenTypeFont from a decoded font entry.
    # Constructs an in-memory SFNT binary from the per-table data and
    # loads it through the normal font reader path.
    def build_font(entry)
      sfnt = SfntBuilder.build(flavor: entry[:flavor], tables: entry[:tables])
      sfnt_io = StringIO.new(sfnt)
      font_class = truetype_flavor?(entry[:flavor]) ? TrueTypeFont : OpenTypeFont
      font = font_class.read(sfnt_io)
      font.initialize_storage
      font.read_table_data(StringIO.new(sfnt))
      font
    end

    def truetype_flavor?(flavor)
      [Constants::SFNT_VERSION_TRUETYPE, 0x00010000].include?(flavor)
    end
  end
end
