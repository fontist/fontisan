# frozen_string_literal: true

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
          source_format: :postscript
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
          source_format: :truetype
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
    end
  end
end
