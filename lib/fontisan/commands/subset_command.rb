# frozen_string_literal: true

require "fileutils"

module Fontisan
  module Commands
    # Command for subsetting fonts
    #
    # This command provides CLI access to font subsetting functionality.
    # It supports multiple input methods for specifying glyphs:
    # - Text input: Subset to characters in a text string
    # - Glyph IDs: Subset to specific glyph IDs
    # - Unicode codepoints: Subset to specific Unicode values
    #
    # The command also supports various subsetting options:
    # - Profile selection (pdf, web, minimal)
    # - Glyph ID retention
    # - Hint dropping
    # - Name dropping
    #
    # @example Subset to text characters
    #   command = SubsetCommand.new('font.ttf',
    #     text: 'Hello World',
    #     output: 'subset.ttf',
    #     profile: 'pdf'
    #   )
    #   command.run
    #
    # @example Subset to specific glyphs
    #   command = SubsetCommand.new('font.ttf',
    #     glyphs: [0, 1, 65, 66, 67],
    #     output: 'subset.ttf'
    #   )
    #   command.run
    class SubsetCommand < BaseCommand
      ROUTED_PROFILES = %w[pdf web minimal].freeze

      # Initialize subset command
      #
      # @param font_path [String] Path to input font file
      # @param options [Hash] Command options
      # @option options [String] :text Text to subset
      # @option options [Array<Integer>] :glyphs Glyph IDs to subset
      # @option options [Array<Integer>] :unicode Unicode codepoints to subset
      # @option options [String] :output Output file path (required)
      # @option options [String] :profile Subsetting profile (pdf, web, minimal)
      # @option options [Boolean] :retain_gids Retain original glyph IDs
      # @option options [Boolean] :drop_hints Drop hinting instructions
      # @option options [Boolean] :drop_names Drop glyph names
      # @option options [Boolean] :unicode_ranges Prune OS/2 Unicode ranges
      def initialize(font_path, options = {})
        super(font_path, options)
        @output_path = options[:output]
        validate_options!
      end

      # Execute the subset command
      #
      # @return [Hash] Result information with output path and glyph count
      # @raise [ArgumentError] If options are invalid
      # @raise [Fontisan::SubsettingError] If subsetting fails
      def run
        # Determine glyph IDs to subset
        glyph_ids = determine_glyph_ids

        # Build subsetting options
        subset_options = build_subset_options

        # Create builder and perform subsetting
        builder = Subset::Builder.new(font, glyph_ids, subset_options)
        subset_binary = builder.build

        # Write output file (create parent directories if needed)
        FileUtils.mkdir_p(File.dirname(@output_path))
        File.binwrite(@output_path, subset_binary)

        # Return result
        {
          input: font_path,
          output: @output_path,
          original_glyphs: font.table("maxp").num_glyphs,
          subset_glyphs: builder.mapping.size,
          profile: subset_options.profile,
          size: subset_binary.bytesize,
        }
      rescue Fontisan::SubsettingError => e
        raise Fontisan::SubsettingError,
              "Subsetting failed: #{e.message}"
      end

      # Execute through the engine selection (the CLI entry): a tier other
      # than Ruby subsets by text or Unicode codepoints with a profile the
      # engine knows, and writes the bytes {#run} writes. Glyph-id input,
      # retained GIDs, dropped hints or names, disabled Unicode-range pruning
      # and verbose output run {#run} on the Ruby tier.
      #
      # @return [Hash] same as {#run}
      def run_routed
        gate = routed_gate
        return run unless gate && Engine.resolve(:subset, font_path.to_s, gate) != :ruby

        determine_glyph_ids # same errors as the Ruby path when nothing matches
        bytes = Reference.subset(font_path, **gate)
        FileUtils.mkdir_p(File.dirname(@output_path))
        File.binwrite(@output_path, bytes)
        routed_result(bytes, gate[:profile])
      end

      private

      # Reference.subset keywords for a plain request; nil otherwise.
      def routed_gate
        profile = options[:profile] || "pdf"
        return nil if options[:glyphs] || options[:retain_gids] || options[:drop_hints] ||
          options[:drop_names] || options[:unicode_ranges] == false || options[:verbose]
        return nil unless ROUTED_PROFILES.include?(profile)

        input = options[:text] ? { text: options[:text] } : { unicodes: parse_unicode(options[:unicode]) }
        input.merge(profile: profile)
      end

      def routed_result(bytes, profile)
        subset = FontLoader.load(@output_path)
        {
          input: font_path,
          output: @output_path,
          original_glyphs: font.table("maxp").num_glyphs,
          subset_glyphs: subset.table("maxp").num_glyphs,
          profile: profile,
          size: bytes.bytesize,
        }
      end

      # Validate command options
      #
      # @raise [ArgumentError] If options are invalid
      def validate_options!
        # Must have output path
        unless @output_path
          raise ArgumentError, "Output path is required (--output)"
        end

        # Must have at least one input method
        unless options[:text] || options[:glyphs] || options[:unicode]
          raise ArgumentError,
                "Must specify --text, --glyphs, or --unicode"
        end

        # Can only use one input method
        input_methods = [
          options[:text],
          options[:glyphs],
          options[:unicode],
        ].compact.size

        if input_methods > 1
          raise ArgumentError,
                "Can only specify one of --text, --glyphs, or --unicode"
        end
      end

      # Determine glyph IDs to subset based on input options
      #
      # @return [Array<Integer>] Array of glyph IDs
      # @raise [ArgumentError] If input is invalid
      def determine_glyph_ids
        if options[:text]
          glyph_ids_from_text(options[:text])
        elsif options[:glyphs]
          parse_glyph_ids(options[:glyphs])
        elsif options[:unicode]
          glyph_ids_from_unicode(options[:unicode])
        else
          raise ArgumentError, "No input specified"
        end
      end

      # Convert text to glyph IDs
      #
      # @param text [String] Input text
      # @return [Array<Integer>] Array of glyph IDs
      def glyph_ids_from_text(text)
        cmap = font.table("cmap")
        raise Fontisan::MissingTableError, "Font has no cmap table" unless cmap

        mappings = cmap.unicode_mappings
        glyph_ids = Set.new

        text.each_char do |char|
          codepoint = char.ord
          glyph_id = mappings[codepoint]

          if glyph_id
            glyph_ids.add(glyph_id)
          elsif options[:verbose]
            warn "Warning: Character '#{char}' (U+#{codepoint.to_s(16).upcase}) not found in font"
          end
        end

        if glyph_ids.empty?
          raise ArgumentError, "No characters from text found in font"
        end

        glyph_ids.to_a.sort
      end

      # Convert Unicode codepoints to glyph IDs
      #
      # @param unicode_input [String, Array<Integer>] Unicode codepoints
      # @return [Array<Integer>] Array of glyph IDs
      def glyph_ids_from_unicode(unicode_input)
        cmap = font.table("cmap")
        raise Fontisan::MissingTableError, "Font has no cmap table" unless cmap

        mappings = cmap.unicode_mappings
        codepoints = parse_unicode(unicode_input)
        glyph_ids = Set.new

        codepoints.each do |codepoint|
          glyph_id = mappings[codepoint]

          if glyph_id
            glyph_ids.add(glyph_id)
          elsif options[:verbose]
            warn "Warning: U+#{codepoint.to_s(16).upcase} not found in font"
          end
        end

        if glyph_ids.empty?
          raise ArgumentError, "No Unicode codepoints found in font"
        end

        glyph_ids.to_a.sort
      end

      # Parse glyph IDs from input
      #
      # @param glyph_input [String, Array<Integer>] Glyph IDs
      # @return [Array<Integer>] Array of glyph IDs
      def parse_glyph_ids(glyph_input)
        if glyph_input.is_a?(Array)
          glyph_input.map(&:to_i)
        elsif glyph_input.is_a?(String)
          # Parse comma-separated or space-separated list
          glyph_input.split(/[,\s]+/).map(&:to_i)
        else
          raise ArgumentError, "Invalid glyph input: #{glyph_input.inspect}"
        end
      end

      # Parse Unicode codepoints from input
      #
      # @param unicode_input [String, Array<Integer>] Unicode codepoints
      # @return [Array<Integer>] Array of codepoints
      def parse_unicode(unicode_input)
        if unicode_input.is_a?(Array)
          unicode_input.map(&:to_i)
        elsif unicode_input.is_a?(String)
          # Parse comma-separated list with optional U+ prefix
          unicode_input.split(/[,\s]+/).map do |s|
            s = s.sub(/^U\+/i, "")
            s.to_i(16)
          end
        else
          raise ArgumentError, "Invalid Unicode input: #{unicode_input.inspect}"
        end
      end

      # Build subsetting options from command options
      #
      # @return [Subset::Options] Subsetting options
      def build_subset_options
        Subset::Options.new(
          profile: options[:profile] || "pdf",
          retain_gids: options[:retain_gids] || false,
          drop_hints: options[:drop_hints] || false,
          drop_names: options[:drop_names] || false,
          unicode_ranges: options[:unicode_ranges].nil? || options[:unicode_ranges],
          include_notdef: true,
          include_null: false,
        )
      end
    end
  end
end
