# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `MATH` table for mathematical formula layout.
      #
      # The MATH table provides constants and glyph info for rendering
      # equations in math-aware environments (Word, LibreOffice, TeX).
      #
      # Layout:
      #   Header (10 bytes):
      #     uint16 version (= 1)
      #     Offset32 mathConstantsOffset
      #     Offset32 mathGlyphInfoOffset
      #     Offset32 mathVariantsOffset
      #
      #   MathConstants: 57 layout constants (int16 + bool each)
      #   MathGlyphInfo: italic correction, top accent, extension
      #   MathVariants: glyph assembly for stretched delimiters
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/math
      module MathTable
        VERSION = 1
        HEADER_SIZE = 10

        # @param constants [Hash, nil] math layout constants
        # @param glyph_info [Hash, nil] per-glyph math data
        # @param variants [Hash, nil] stretched delimiter data
        # @return [String, nil] MATH table bytes, or nil if no data
        def self.build(constants: nil, glyph_info: nil, variants: nil)
          return nil unless constants || glyph_info || variants

          constants_bytes = constants ? build_constants(constants) : nil
          glyph_info_bytes = glyph_info ? build_glyph_info(glyph_info) : nil
          variants_bytes = variants ? build_variants(variants) : nil

          constants_off = constants_bytes ? HEADER_SIZE : 0
          gi_off = glyph_info_bytes ? constants_off + (constants_bytes&.bytesize || 0) : 0
          if gi_off.zero? && glyph_info_bytes
            gi_off = HEADER_SIZE + (constants_bytes&.bytesize || 0)
          end
          variants_off = variants_bytes ? gi_off + (glyph_info_bytes&.bytesize || 0) : 0
          if variants_off.zero? && variants_bytes
            variants_off = HEADER_SIZE + (constants_bytes&.bytesize || 0) + (glyph_info_bytes&.bytesize || 0)
          end

          io = +""
          io << [0x00010000, constants_off, gi_off, variants_off].pack("Nnnn")
          io << constants_bytes if constants_bytes
          io << glyph_info_bytes if glyph_info_bytes
          io << variants_bytes if variants_bytes
          io
        end

        # Build the MathConstants subtable (57 constants).
        # Each constant is int16 (or int32 for larger ranges).
        def self.build_constants(constants)
          io = +""
          # The 57 constants are a fixed sequence. We pack what's
          # provided and use 0 (default) for missing ones.
          constant_names.each do |name|
            value = constants[name] || constants[name.to_s] || 0
            io << [value.to_i].pack("s>")
          end
          io
        end

        def self.constant_names
          %i[
            scriptPercentScaleDown
            scriptScriptPercentScaleDown
            delimitedSubFormulaMinHeight
            displayOperatorMinHeight
            mathLeading
            axisHeight
            accentBaseHeight
            flattenedAccentBaseHeight
            subscriptShiftDown
            subscriptTopMax
            subscriptBaselineDropMin
            superscriptShiftUp
            superscriptShiftUpCramped
            superscriptBottomMin
            superscriptBaselineDropMax
            subSuperscriptGapMin
            superscriptBottomMaxWithSubscript
            spaceAfterScript
            upperLimitGapMin
            upperLimitBaselineRiseMin
            lowerLimitGapMin
            lowerLimitBaselineDropMin
            stackTopShiftUp
            stackTopDisplayStyleShiftUp
            stackBottomShiftDown
            stackBottomDisplayStyleShiftDown
            stackGapMin
            stackDisplayStyleGapMin
            stretchStackTopShiftUp
            stretchStackBottomShiftDown
            fractionNumeratorShiftUp
            fractionNumeratorDisplayStyleShiftUp
            fractionDenominatorShiftDown
            fractionDenominatorDisplayStyleShiftDown
            fractionNumeratorGapMin
            fractionNumDisplayStyleGapMin
            fractionRuleThickness
            fractionDenominatorGapMin
            fractionDenomDisplayStyleGapMin
            skewedFractionHorizontalGap
            skewedFractionVerticalGap
            overbarVerticalGap
            overbarRuleThickness
            overbarExtraAscender
            underbarVerticalGap
            underbarRuleThickness
            underbarExtraDescender
            radicalVerticalGap
            radicalDisplayStyleVerticalGap
            radicalRuleThickness
            radicalExtraAscender
            radicalKernBeforeDegree
            radicalKernAfterDegree
            radicalDegreeBottomRaisePercent
          ].freeze
        end

        def self.build_glyph_info(_info)
          # Minimal: just the header with offsets (all empty for now)
          [0, 0, 0, 0].pack("NNNN")
        end

        def self.build_variants(_variants)
          # Minimal: just the header with offset (empty for now)
          [0, 0, 0, 0].pack("NNNN")
        end

        private_class_method :build_constants, :constant_names,
                             :build_glyph_info, :build_variants
      end
    end
  end
end
