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
      # @return [Symbol] One of :ttf, :otf, :ttc, :otc, :woff, :woff2, :svg
      def detect_format
        # Check for SVG first (from file extension even if font failed to load)
        return :svg if @file_path.end_with?(".svg")

        return :unknown unless @font

        # Use is_a? for proper class checking
        case @font
        when Fontisan::TrueTypeCollection
          :ttc
        when Fontisan::OpenTypeCollection
          :otc
        when Fontisan::TrueTypeFont
          if @file_path.end_with?(".woff")
            :woff
          elsif @file_path.end_with?(".woff2")
            :woff2
          else
            :ttf
          end
        when Fontisan::OpenTypeFont
          if @file_path.end_with?(".woff")
            :woff
          elsif @file_path.end_with?(".woff2")
            :woff2
          else
            :otf
          end
        else
          :unknown
        end
      end

      # Detect variation type
      #
      # @return [Symbol] One of :static, :gvar, :cff2
      def detect_variation
        return :static unless @font

        # Collections don't have has_table? method
        # Return :static for collections (variation detection would need to load first font)
        return :static if collection?

        # Check for variable font tables
        if @font.has_table?("fvar")
          # Variable font detected - check variation type
          if @font.has_table?("gvar")
            :gvar # TrueType variable font
          elsif @font.has_table?("CFF2")
            :cff2 # OpenType variable font (CFF2)
          else
            :static # Has fvar but no variation data (shouldn't happen)
          end
        else
          :static
        end
      end

      # Detect font capabilities
      #
      # @return [Hash] Capabilities hash
      def detect_capabilities
        return default_capabilities unless @font

        # Check if this is a collection
        is_collection = collection?

        font_to_check = if is_collection
                          # Collections don't have fonts method, need to load first font
                          nil # Will handle in API usage
                        else
                          @font
                        end

        # For collections, return basic capabilities
        if is_collection
          return {
            outline: :unknown, # Would need to load first font to know
            variation: false,  # Would need to load first font to know
            collection: true,
            tables: [],
          }
        end

        return default_capabilities unless font_to_check

        {
          outline: detect_outline_type(font_to_check),
          variation: detect_variation != :static,
          collection: false,
          tables: available_tables(font_to_check),
        }
      end

      # Check if font is a collection
      #
      # @return [Boolean] True if collection (TTC/OTC)
      def collection?
        @font.is_a?(Fontisan::TrueTypeCollection) ||
          @font.is_a?(Fontisan::OpenTypeCollection)
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

      # Detect outline type
      #
      # @param font [Font] Font object
      # @return [Symbol] :truetype or :cff
      def detect_outline_type(font)
        if font.has_table?("glyf") || font.has_table?("gvar")
          :truetype
        elsif font.has_table?("CFF ") || font.has_table?("CFF2")
          :cff
        else
          :unknown
        end
      end

      # Get available tables
      #
      # @param font [Font] Font object
      # @return [Array<String>] List of table tags
      def available_tables(font)
        return [] unless font.respond_to?(:table_names)

        font.table_names
      rescue StandardError
        []
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
