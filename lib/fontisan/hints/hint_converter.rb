# frozen_string_literal: true

require "json"
require_relative "../models/hint"

module Fontisan
  module Hints
    # Converts hints between TrueType and PostScript formats
    #
    # This converter handles bidirectional conversion of rendering hints,
    # translating between TrueType instruction-based hinting and PostScript
    # operator-based hinting while preserving intent where possible.
    #
    # **Conversion Strategy:**
    #
    # - TrueType → PostScript: Extract semantic meaning from instructions
    #   and convert to corresponding PostScript operators
    # - PostScript → TrueType: Analyze hint operators and generate
    #   equivalent TrueType instructions
    #
    # @example Convert TrueType hints to PostScript
    #   converter = HintConverter.new
    #   ps_hints = converter.to_postscript(tt_hints)
    #
    # @example Convert PostScript hints to TrueType
    #   converter = HintConverter.new
    #   tt_hints = converter.to_truetype(ps_hints)
    class HintConverter
      # Convert hints to PostScript format
      #
      # @param hints [Array<Hint>] Source hints (any format)
      # @return [Array<Hint>] Hints in PostScript format
      def to_postscript(hints)
        return [] if hints.nil? || hints.empty?

        hints.map do |hint|
          next hint if hint.source_format == :postscript

          convert_hint_to_postscript(hint)
        end.compact
      end

      # Convert hints to TrueType format
      #
      # @param hints [Array<Hint>] Source hints (any format)
      # @return [Array<Hint>] Hints in TrueType format
      def to_truetype(hints)
        return [] if hints.nil? || hints.empty?

        hints.map do |hint|
          next hint if hint.source_format == :truetype

          convert_hint_to_truetype(hint)
        end.compact
      end

      # Optimize hint set by removing redundant hints
      #
      # @param hints [Array<Hint>] Hints to optimize
      # @return [Array<Hint>] Optimized hints
      def optimize(hints)
        return [] if hints.nil? || hints.empty?

        # Remove duplicate hints
        unique_hints = hints.uniq { |h| [h.type, h.data] }

        # Remove conflicting hints (keep first)
        remove_conflicts(unique_hints)
      end

      # Convert entire HintSet between formats
      #
      # @param hint_set [Models::HintSet] Source hint set
      # @param target_format [Symbol] Target format (:truetype or :postscript)
      # @return [Models::HintSet] Converted hint set
      def convert_hint_set(hint_set, target_format)
        return hint_set if hint_set.format == target_format.to_s

        result = Models::HintSet.new(format: target_format.to_s)

        case target_format
        when :postscript
          # Convert font-level TT → PS
          if hint_set.font_program || hint_set.control_value_program ||
              hint_set.control_values&.any?
            ps_dict = convert_tt_programs_to_ps_dict(
              hint_set.font_program,
              hint_set.control_value_program,
              hint_set.control_values,
            )
            result.private_dict_hints = ps_dict.to_json
          end

          # Convert per-glyph hints
          hint_set.hinted_glyph_ids.each do |glyph_id|
            glyph_hints = hint_set.get_glyph_hints(glyph_id)
            ps_hints = to_postscript(glyph_hints)
            result.add_glyph_hints(glyph_id, ps_hints) unless ps_hints.empty?
          end

        when :truetype
          # Convert font-level PS → TT
          if hint_set.private_dict_hints && hint_set.private_dict_hints != "{}"
            tt_programs = convert_ps_dict_to_tt_programs(
              JSON.parse(hint_set.private_dict_hints),
            )
            result.font_program = tt_programs[:fpgm]
            result.control_value_program = tt_programs[:prep]
            result.control_values = tt_programs[:cvt]
          end

          # Convert per-glyph hints
          hint_set.hinted_glyph_ids.each do |glyph_id|
            glyph_hints = hint_set.get_glyph_hints(glyph_id)
            tt_hints = to_truetype(glyph_hints)
            result.add_glyph_hints(glyph_id, tt_hints) unless tt_hints.empty?
          end
        end

        result.has_hints = !result.empty?
        result
      end

      private

      # Convert a single hint to PostScript format
      #
      # @param hint [Hint] Source hint
      # @return [Hint, nil] Converted hint or nil if incompatible
      def convert_hint_to_postscript(hint)
        return nil unless hint.compatible_with?(:postscript)

        # Get PostScript representation from hint
        ps_data = hint.to_postscript

        # Create new hint with PostScript format
        Models::Hint.new(
          type: hint.type,
          data: ps_data,
          source_format: :postscript,
        )
      rescue StandardError => e
        warn "Failed to convert hint to PostScript: #{e.message}"
        nil
      end

      # Convert a single hint to TrueType format
      #
      # @param hint [Hint] Source hint
      # @return [Hint, nil] Converted hint or nil if incompatible
      def convert_hint_to_truetype(hint)
        return nil unless hint.compatible_with?(:truetype)

        # Get TrueType representation from hint
        tt_instructions = hint.to_truetype

        # Create new hint with TrueType format
        Models::Hint.new(
          type: hint.type,
          data: { instructions: tt_instructions },
          source_format: :truetype,
        )
      rescue StandardError => e
        warn "Failed to convert hint to TrueType: #{e.message}"
        nil
      end

      # Remove conflicting hints from set
      #
      # @param hints [Array<Hint>] Hints to check
      # @return [Array<Hint>] Non-conflicting hints
      def remove_conflicts(hints)
        non_conflicting = []

        hints.each do |hint|
          # Check if this hint conflicts with any already selected
          conflicts = non_conflicting.any? do |existing|
            hints_conflict?(hint, existing)
          end

          non_conflicting << hint unless conflicts
        end

        non_conflicting
      end

      # Check if two hints conflict
      #
      # @param hint1 [Hint] First hint
      # @param hint2 [Hint] Second hint
      # @return [Boolean] True if hints conflict
      def hints_conflict?(hint1, hint2)
        # Hints of different types don't conflict
        return false if hint1.type != hint2.type

        case hint1.type
        when :stem
          # Stem hints conflict if they overlap
          stems_overlap?(hint1.data, hint2.data)
        when :interpolate
          # Multiple interpolation hints on same axis conflict
          hint1.data[:axis] == hint2.data[:axis]
        else
          # Other hint types don't conflict
          false
        end
      end

      # Check if two stem hints overlap
      #
      # @param stem1 [Hash] First stem data
      # @param stem2 [Hash] Second stem data
      # @return [Boolean] True if stems overlap
      def stems_overlap?(stem1, stem2)
        # Must be same orientation to conflict
        return false if stem1[:orientation] != stem2[:orientation]

        pos1 = stem1[:position] || 0
        width1 = stem1[:width] || 0
        pos2 = stem2[:position] || 0
        width2 = stem2[:width] || 0

        # Check if ranges overlap
        end1 = pos1 + width1
        end2 = pos2 + width2

        pos1 < end2 && pos2 < end1
      end

      # Convert TrueType font programs to PostScript Private dict
      #
      # Analyzes TrueType fpgm, prep, and cvt to extract semantic intent
      # and generate corresponding PostScript hint parameters using the
      # TrueTypeInstructionAnalyzer.
      #
      # @param fpgm [String] Font program bytecode
      # @param prep [String] Control value program bytecode
      # @param cvt [Array<Integer>] Control values
      # @return [Hash] PostScript Private dict hint parameters
      def convert_tt_programs_to_ps_dict(fpgm, prep, cvt)
        hints = {}

        # Extract stem widths from CVT if present
        # CVT values typically contain standard widths at the beginning
        if cvt && !cvt.empty?
          # First CVT value often represents standard horizontal stem
          hints[:std_hw] = cvt[0].abs if cvt.length > 0
          # Second CVT value often represents standard vertical stem
          hints[:std_vw] = cvt[1].abs if cvt.length > 1
        end

        # Use the instruction analyzer to extract additional hint parameters
        analyzer = TrueTypeInstructionAnalyzer.new

        # Analyze prep program if present
        prep_hints = if prep && !prep.empty?
                       analyzer.analyze_prep(prep, cvt)
                     else
                       {}
                     end

        # Analyze fpgm program complexity
        fpgm_hints = if fpgm && !fpgm.empty?
                       analyzer.analyze_fpgm(fpgm)
                     else
                       {}
                     end

        # Extract blue zones from CVT if present
        blue_zones = if cvt && !cvt.empty?
                       analyzer.extract_blue_zones_from_cvt(cvt)
                     else
                       {}
                     end

        # Merge all extracted hints (prep_hints and fpgm_hints override stem widths if present)
        hints.merge!(prep_hints).merge!(fpgm_hints).merge!(blue_zones)

        # Provide default blue_values if none were detected
        # These are standard values that work for most Latin fonts
        hints[:blue_values] ||= [-20, 0, 706, 726]

        hints
      rescue StandardError => e
        warn "Error converting TT programs to PS dict: #{e.message}"
        {}
      end

      # Convert PostScript Private dict to TrueType font programs
      #
      # Generates TrueType control values and programs from PostScript
      # hint parameters using the TrueTypeInstructionGenerator.
      #
      # @param ps_dict [Hash] PostScript Private dict parameters
      # @return [Hash] TrueType programs ({ fpgm:, prep:, cvt: })
      def convert_ps_dict_to_tt_programs(ps_dict)
        # Use the instruction generator to create real TrueType programs
        generator = TrueTypeInstructionGenerator.new
        generator.generate(ps_dict)
      rescue StandardError => e
        warn "Error converting PS dict to TT programs: #{e.message}"
        { fpgm: "".b, prep: "".b, cvt: [] }
      end
    end
  end
end
