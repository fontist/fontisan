# frozen_string_literal: true

require_relative "options"
require_relative "profile"
require_relative "glyph_mapping"
require_relative "table_subsetter"
require_relative "../font_writer"

module Fontisan
  module Subset
    # Main font subsetting engine
    #
    # The [`Builder`](lib/fontisan/subset/builder.rb) class orchestrates the entire
    # subsetting process:
    # 1. Validates input parameters
    # 2. Calculates glyph closure (including composite dependencies)
    # 3. Builds glyph ID mapping (old GID → new GID)
    # 4. Subsets each table according to the selected profile
    # 5. Assembles the final subset font binary
    #
    # The subsetting process ensures that .notdef (GID 0) is always included
    # as the first glyph, as required by the OpenType specification.
    #
    # @example Basic subsetting
    #   font = Fontisan::TrueTypeFont.from_file('font.ttf')
    #   builder = Fontisan::Subset::Builder.new(
    #     font,
    #     [0, 65, 66, 67],  # .notdef, A, B, C
    #     Options.new(profile: 'pdf')
    #   )
    #   subset_data = builder.build
    #
    # @example Subsetting with retain_gids
    #   options = Options.new(profile: 'pdf', retain_gids: true)
    #   builder = Fontisan::Subset::Builder.new(font, glyph_ids, options)
    #   subset_data = builder.build
    #
    # @example Web subsetting with dropped hints
    #   options = Options.new(profile: 'web', drop_hints: true, drop_names: true)
    #   builder = Fontisan::Subset::Builder.new(font, glyph_ids, options)
    #   subset_data = builder.build
    #
    # Reference: [`docs/ttfunk-feature-analysis.md:455-492`](docs/ttfunk-feature-analysis.md:455)
    class Builder
      # Font instance to subset
      # @return [TrueTypeFont, OpenTypeFont]
      attr_reader :font

      # Base set of glyph IDs requested for subsetting
      # @return [Array<Integer>]
      attr_reader :glyph_ids

      # Subsetting options
      # @return [Options]
      attr_reader :options

      # Complete set of glyph IDs after closure calculation
      # @return [Set<Integer>]
      attr_reader :closure

      # Glyph ID mapping (old GID → new GID)
      # @return [GlyphMapping]
      attr_reader :mapping

      # Initialize a new subsetting builder
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to subset
      # @param glyph_ids [Array<Integer>] Base glyph IDs to include
      # @param options [Options, Hash] Subsetting options
      # @raise [ArgumentError] If parameters are invalid
      #
      # @example
      #   builder = Builder.new(font, [0, 65, 66], Options.new(profile: 'pdf'))
      def initialize(font, glyph_ids, options = {})
        @font = font
        @glyph_ids = Array(glyph_ids)
        @options = options.is_a?(Options) ? options : Options.new(options)
        @closure = nil
        @mapping = nil
      end

      # Build the subset font
      #
      # This is the main entry point that performs the entire subsetting
      # workflow:
      # 1. Validates all input parameters
      # 2. Calculates the glyph closure (composite dependencies)
      # 3. Builds the glyph ID mapping
      # 4. Subsets all required tables
      # 5. Assembles the final font binary
      #
      # @return [String] Binary data of the subset font
      # @raise [ArgumentError] If validation fails
      # @raise [Fontisan::SubsettingError] If subsetting fails
      #
      # @example
      #   subset_binary = builder.build
      #   File.binwrite('subset.ttf', subset_binary)
      def build
        validate_input!
        calculate_closure
        build_mapping
        tables = subset_tables
        assemble_font(tables)
      end

      private

      # Validate input parameters
      #
      # Ensures that the font, glyph IDs, and options are all valid for
      # subsetting. Checks that required tables exist and that glyph IDs
      # are within valid range.
      #
      # @raise [ArgumentError] If validation fails
      def validate_input!
        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:table)
          raise ArgumentError, "Font must respond to :table method"
        end

        # Validate options
        options.validate!

        # Ensure we have at least one glyph ID
        if glyph_ids.empty?
          raise ArgumentError, "At least one glyph ID must be provided"
        end

        # Validate that required tables exist
        validate_required_tables!

        # Validate glyph IDs are within range
        validate_glyph_ids!
      end

      # Validate that required tables exist in the font
      #
      # @raise [Fontisan::MissingTableError] If required tables are missing
      def validate_required_tables!
        required = %w[head maxp]
        required.each do |tag|
          table = font.table(tag)
          next if table

          raise Fontisan::MissingTableError,
                "Required table '#{tag}' not found in font"
        end
      end

      # Validate that all glyph IDs are within valid range
      #
      # @raise [ArgumentError] If any glyph ID is invalid
      def validate_glyph_ids!
        maxp = font.table("maxp")
        num_glyphs = maxp.num_glyphs

        glyph_ids.each do |gid|
          if gid.nil? || gid.negative?
            raise ArgumentError, "Invalid glyph ID: #{gid.inspect}"
          end

          if gid >= num_glyphs
            raise ArgumentError,
                  "Glyph ID #{gid} exceeds font's glyph count " \
                  "(#{num_glyphs})"
          end
        end
      end

      # Calculate glyph closure
      #
      # Uses [`GlyphAccessor`](lib/fontisan/glyph_accessor.rb) to recursively
      # collect all glyphs needed, including component glyphs referenced by
      # composite glyphs. Always ensures GID 0 (.notdef) is included.
      #
      # The closure is stored in the `@closure` instance variable as a Set.
      def calculate_closure
        accessor = Fontisan::GlyphAccessor.new(font)

        # Ensure .notdef (GID 0) is included if specified in options
        base_gids = glyph_ids.dup
        base_gids.unshift(0) if options.include_notdef && !base_gids.include?(0)

        # Calculate closure using GlyphAccessor
        @closure = accessor.closure_for(base_gids)
      end

      # Build glyph mapping
      #
      # Creates a [`GlyphMapping`](lib/fontisan/subset/glyph_mapping.rb)
      # object that maps old glyph IDs to new glyph IDs. The mapping respects
      # the `retain_gids` option:
      # - Compact mode (retain_gids: false): Sequential renumbering
      # - Retain mode (retain_gids: true): Preserve original GIDs
      #
      # The mapping is stored in the `@mapping` instance variable.
      def build_mapping
        @mapping = GlyphMapping.new(
          closure.to_a,
          retain_gids: options.retain_gids,
        )
      end

      # Subset all tables according to profile
      #
      # For each table specified in the subsetting profile, performs
      # table-specific subsetting operations using [`TableSubsetter`](lib/fontisan/subset/table_subsetter.rb).
      # Tables not in the profile are excluded from the subset font.
      #
      # @return [Hash<String, String>] Hash of table tag => binary data
      # @raise [Fontisan::SubsettingError] If table subsetting fails
      def subset_tables
        profile_tables = Profile.for_name(options.profile)
        subset = {}

        # Create table subsetter
        subsetter = TableSubsetter.new(font, mapping, options)

        profile_tables.each do |tag|
          table = font.table(tag)
          next unless table

          begin
            subset[tag] = subsetter.subset_table(tag, table)
          rescue StandardError => e
            raise Fontisan::SubsettingError,
                  "Failed to subset table '#{tag}': #{e.message}"
          end
        end

        subset
      end

      # Assemble final font
      #
      # Builds the complete font binary from subset tables, including:
      # - Offset table (font directory)
      # - Table directory entries
      # - Table data
      # - Proper padding and checksums
      #
      # @param tables [Hash<String, String>] Table tag => binary data
      # @return [String] Complete font binary
      def assemble_font(tables)
        # Determine sfnt version based on font type
        sfnt_version = determine_sfnt_version(tables)

        # Use FontWriter to assemble the complete font
        FontWriter.write_font(tables, sfnt_version: sfnt_version)
      end

      # Determine the sfnt version for the font
      #
      # @param tables [Hash<String, String>] Table tag => binary data
      # @return [Integer] sfnt version number
      def determine_sfnt_version(tables)
        # If font has CFF or CFF2 table, use OpenType version
        if tables.key?("CFF ") || tables.key?("CFF2")
          0x4F54544F # 'OTTO' for OpenType/CFF
        else
          0x00010000 # 1.0 for TrueType
        end
      end
    end
  end
end
