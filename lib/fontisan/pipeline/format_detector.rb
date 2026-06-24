# frozen_string_literal: true

require_relative "../font_loader"

module Fontisan
  module Pipeline
    # Detects font format and capabilities
    #
    # This class analyzes font files to determine:
    # - Format: TTF, OTF, TTC, OTC, WOFF, WOFF2, SVG
    # - Variation type: static, gvar (TrueType variable), CFF2 (OpenType variable)
    # - Capabilities: outline type, variation support, collection support
    #
    # Used by the universal transformation pipeline to determine conversion
    # strategies and validate compatibility.
    #
    # @example Detecting a font's format
    #   detector = FormatDetector.new("font.ttf")
    #   info = detector.detect
    #   puts info[:format]        # => :ttf
    #   puts info[:variation_type] # => :gvar
    #   puts info[:capabilities][:outline] # => :truetype
    class FormatDetector
      # @return [String] Path to font file
      attr_reader :file_path

      # @return [TrueTypeFont, OpenTypeFont, TrueTypeCollection, OpenTypeCollection, nil] Loaded font
      attr_reader :font

      # Initialize detector
      #
      # @param file_path [String] Path to font file
      def initialize(file_path)
        @file_path = file_path
        @font = nil
      end

      # Detect format and capabilities
      #
      # @return [Hash] Detection results with :format, :variation_type, :capabilities
      def detect
        load_font

        {
          format: detect_format,
          variation_type: detect_variation,
          capabilities: detect_capabilities,
        }
      end

      # Detect font format
      #
      # Delegates to the loaded font object's own `#format` method.
      # Each font class (TrueTypeFont, OpenTypeFont, WoffFont, Woff2Font,
      # Type1Font, *Collection) is the single source of truth for its
      # format identifier. This keeps FormatDetector closed for modification
      # when new font classes are added (OCP): no case statement to edit.
      #
      # @return [Symbol] One of :ttf, :otf, :ttc, :otc, :woff, :woff2,
      #   :type1, :dfont, or :unknown
      def detect_format
        # SVG fonts are an export-only target; no font object exists yet.
        return :svg if @file_path.end_with?(".svg")

        return :unknown unless @font

        @font.format
      end

      # Detect variation type
      #
      # Delegates to the loaded font object's own `#variation_type` method.
      # Each font class is the single source of truth for its variation
      # profile, so this method needs no class-specific branching.
      #
      # @return [Symbol] :static, :gvar (TrueType variable), or :cff2
      def detect_variation
        return :static unless @font

        @font.variation_type
      end

      # Detect font capabilities
      #
      # Aggregates four pieces of self-knowledge owned by the font class:
      # outline representation, variation support, collection status, and
      # the table directory. Each is exposed as a method on the font object
      # so this method stays free of class-specific branching.
      #
      # @return [Hash] Capabilities hash
      def detect_capabilities
        return default_capabilities unless @font

        {
          outline: @font.outline_type,
          variation: @font.variation_type != :static,
          collection: @font.collection?,
          tables: @font.table_names,
        }
      end

      # Check if font is a collection
      #
      # @return [Boolean] True if the loaded object is a font collection
      def collection?
        return false unless @font

        @font.collection?
      end

      # Check if font is variable
      #
      # @return [Boolean] True if variable font
      def variable?
        detect_variation != :static
      end

      # Check if format is compatible with target
      #
      # @param target_format [Symbol] Target format (:ttf, :otf, etc.)
      # @return [Boolean] True if conversion is possible
      def compatible_with?(target_format)
        current_format = detect_format
        variation_type = detect_variation

        # Same format is always compatible
        return true if current_format == target_format

        # Collection formats
        if %i[ttc otc].include?(current_format)
          return %i[ttc otc].include?(target_format)
        end

        # Variable font constraints
        if variation_type == :static
          # Static fonts can convert to any format
          true
        else
          case variation_type
          when :gvar
            # TrueType variable can convert to TrueType formats
            %i[ttf ttc woff woff2].include?(target_format)
          when :cff2
            # OpenType variable can convert to OpenType formats
            %i[otf otc woff woff2].include?(target_format)
          end
        end
      end

      private

      # Load font from file
      def load_font
        # Check if it's a collection first
        @font = if FontLoader.collection?(@file_path)
                  FontLoader.load_collection(@file_path)
                else
                  FontLoader.load(@file_path, mode: :full)
                end
      rescue StandardError => e
        warn "Failed to load font: #{e.message}"
        @font = nil
      end

      # Default capabilities when font cannot be loaded
      #
      # @return [Hash] Default capabilities
      def default_capabilities
        {
          outline: :unknown,
          variation: false,
          collection: false,
          tables: [],
        }
      end
    end
  end
end
