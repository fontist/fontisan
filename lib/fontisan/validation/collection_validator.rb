# frozen_string_literal: true

require_relative "../error"

module Fontisan
  module Validation
    # CollectionValidator validates font compatibility for collection formats
    #
    # Main responsibility: Enforce format-specific compatibility rules for
    # TTC, OTC, and dfont collections according to OpenType spec and Apple standards.
    #
    # Rules:
    # - TTC: TrueType fonts ONLY (per OpenType spec)
    # - OTC: CFF fonts required, mixed TTF+OTF allowed (Fontisan extension)
    # - dfont: Any SFNT fonts (TTF, OTF, or mixed)
    # - All: Web fonts (WOFF/WOFF2) are NEVER allowed in collections
    #
    # @example Validate TTC compatibility
    #   validator = CollectionValidator.new
    #   validator.validate!([font1, font2], :ttc)
    #
    # @example Check compatibility without raising
    #   validator = CollectionValidator.new
    #   result = validator.compatible?([font1, font2], :otc)
    class CollectionValidator
      # Validate fonts are compatible with collection format
      #
      # @param fonts [Array<TrueTypeFont, OpenTypeFont>] Fonts to validate
      # @param format [Symbol] Collection format (:ttc, :otc, or :dfont)
      # @return [Boolean] true if valid
      # @raise [Error] if validation fails
      def validate!(fonts, format)
        validate_not_empty!(fonts)
        validate_format!(format)

        case format
        when :ttc
          validate_ttc!(fonts)
        when :otc
          validate_otc!(fonts)
        when :dfont
          validate_dfont!(fonts)
        else
          raise Error, "Unknown collection format: #{format}"
        end

        true
      end

      # Check if fonts are compatible with format (without raising)
      #
      # @param fonts [Array] Fonts to check
      # @param format [Symbol] Collection format
      # @return [Boolean] true if compatible
      def compatible?(fonts, format)
        validate!(fonts, format)
        true
      rescue Error
        false
      end

      # Get compatibility issues for fonts and format
      #
      # @param fonts [Array] Fonts to check
      # @param format [Symbol] Collection format
      # @return [Array<String>] Array of issue descriptions (empty if compatible)
      def compatibility_issues(fonts, format)
        issues = []

        return ["Font array cannot be empty"] if fonts.nil? || fonts.empty?
        return ["Invalid format: #{format}"] unless %i[ttc otc
                                                       dfont].include?(format)

        case format
        when :ttc
          issues.concat(ttc_issues(fonts))
        when :otc
          issues.concat(otc_issues(fonts))
        when :dfont
          issues.concat(dfont_issues(fonts))
        end

        issues
      end

      private

      # Validate fonts array is not empty
      #
      # @param fonts [Array] Fonts
      # @raise [ArgumentError] if empty or nil
      def validate_not_empty!(fonts)
        if fonts.nil? || fonts.empty?
          raise ArgumentError, "Font array cannot be empty"
        end
      end

      # Validate format is supported
      #
      # @param format [Symbol] Format
      # @raise [ArgumentError] if invalid
      def validate_format!(format)
        unless %i[ttc otc dfont].include?(format)
          raise ArgumentError,
                "Invalid format: #{format}. Must be :ttc, :otc, or :dfont"
        end
      end

      # Validate TTC compatibility
      #
      # Per OpenType spec: TTC = TrueType outlines ONLY
      # "CFF rasterizer does not currently support TTC files"
      #
      # @param fonts [Array] Fonts
      # @raise [Error] if incompatible
      def validate_ttc!(fonts)
        fonts.each_with_index do |font, index|
          # Check for web fonts
          if web_font?(font)
            raise Error,
                  "Font #{index} is a web font (WOFF/WOFF2). " \
                  "Web fonts cannot be packed into collections."
          end

          # Check for TrueType outline format
          unless truetype_font?(font)
            raise Error,
                  "Font #{index} is not TrueType. " \
                  "TTC requires TrueType fonts only (per OpenType spec)."
          end
        end
      end

      # Validate OTC compatibility
      #
      # Per OpenType 1.8: OTC for CFF collections
      # Fontisan extension: Also allows mixed TTF+OTF for flexibility
      #
      # @param fonts [Array] Fonts
      # @raise [Error] if incompatible
      def validate_otc!(fonts)
        has_cff = false

        fonts.each_with_index do |font, index|
          # Check for web fonts
          if web_font?(font)
            raise Error,
                  "Font #{index} is a web font (WOFF/WOFF2). " \
                  "Web fonts cannot be packed into collections."
          end

          # Track if any font has CFF
          has_cff = true if cff_font?(font)
        end

        # OTC should have at least one CFF font
        unless has_cff
          raise Error,
                "OTC requires at least one CFF/OpenType font. " \
                "All fonts are TrueType - use TTC instead."
        end
      end

      # Validate dfont compatibility
      #
      # Apple dfont suitcase: Any SFNT fonts OK (TTF, OTF, or mixed)
      # dfont stores complete Mac resources (FOND, NFNT, sfnt)
      #
      # @param fonts [Array] Fonts
      # @raise [Error] if incompatible
      def validate_dfont!(fonts)
        fonts.each_with_index do |font, index|
          # Only check for web fonts - dfont accepts any SFNT
          if web_font?(font)
            raise Error,
                  "Font #{index} is a web font (WOFF/WOFF2). " \
                  "Web fonts cannot be packed into dfont."
          end
        end
      end

      # Get TTC compatibility issues
      #
      # @param fonts [Array] Fonts
      # @return [Array<String>] Issues
      def ttc_issues(fonts)
        issues = []

        fonts.each_with_index do |font, index|
          if web_font?(font)
            issues << "Font #{index} is WOFF/WOFF2 (not allowed in collections)"
          elsif !truetype_font?(font)
            issues << "Font #{index} is not TrueType (TTC requires TrueType only)"
          end
        end

        issues
      end

      # Get OTC compatibility issues
      #
      # @param fonts [Array] Fonts
      # @return [Array<String>] Issues
      def otc_issues(fonts)
        issues = []
        has_cff = false

        fonts.each_with_index do |font, index|
          if web_font?(font)
            issues << "Font #{index} is WOFF/WOFF2 (not allowed in collections)"
          end
          has_cff = true if cff_font?(font)
        end

        unless has_cff
          issues << "OTC requires at least one CFF font (all fonts are TrueType)"
        end

        issues
      end

      # Get dfont compatibility issues
      #
      # @param fonts [Array] Fonts
      # @return [Array<String>] Issues
      def dfont_issues(fonts)
        issues = []

        fonts.each_with_index do |font, index|
          if web_font?(font)
            issues << "Font #{index} is WOFF/WOFF2 (not allowed in dfont)"
          end
        end

        issues
      end

      # Check if font is a web font
      #
      # @param font [Object] Font object
      # @return [Boolean] true if WOFF or WOFF2
      def web_font?(font)
        font.class.name.include?("Woff")
      end

      # Check if font is TrueType
      #
      # @param font [Object] Font object
      # @return [Boolean] true if TrueType
      def truetype_font?(font)
        return false unless font.respond_to?(:has_table?)

        font.has_table?("glyf")
      end

      # Check if font is CFF/OpenType
      #
      # @param font [Object] Font object
      # @return [Boolean] true if CFF
      def cff_font?(font)
        return false unless font.respond_to?(:has_table?)

        font.has_table?("CFF ") || font.has_table?("CFF2")
      end
    end
  end
end
