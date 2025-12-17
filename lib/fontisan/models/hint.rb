# frozen_string_literal: true

module Fontisan
  module Models
    # Universal hint representation supporting both TrueType and PostScript hints
    #
    # Hints are instructions that improve font rendering at small sizes by
    # providing information about how to align features to the pixel grid.
    # This model provides a format-agnostic representation that can be
    # converted between TrueType instructions and PostScript hint operators.
    #
    # **Hint Types:**
    #
    # - `:stem` - Vertical or horizontal stem hints (PostScript hstem/vstem)
    # - `:stem3` - Multiple stem hints (PostScript hstem3/vstem3)
    # - `:flex` - Flex hints for smooth curves (PostScript flex)
    # - `:counter` - Counter control hints (PostScript counter)
    # - `:hint_replacement` - Hint replacement (PostScript hintmask)
    # - `:delta` - Delta hints for pixel-level adjustments (TrueType DELTA)
    # - `:interpolate` - Interpolation hints (TrueType IUP)
    # - `:shift` - Shift hints (TrueType SHP)
    # - `:align` - Alignment hints (TrueType ALIGNRP)
    #
    # @example Creating a stem hint
    #   hint = Fontisan::Models::Hint.new(
    #     type: :stem,
    #     data: { position: 100, width: 50, orientation: :vertical }
    #   )
    #
    # @example Converting to TrueType
    #   tt_instructions = hint.to_truetype
    #
    # @example Converting to PostScript
    #   ps_operators = hint.to_postscript
    class Hint
      # @return [Symbol] Hint type
      attr_reader :type

      # @return [Hash] Hint-specific data
      attr_reader :data

      # @return [Symbol] Source format (:truetype or :postscript)
      attr_reader :source_format

      # Initialize a new hint
      #
      # @param type [Symbol] Hint type
      # @param data [Hash] Hint-specific data
      # @param source_format [Symbol] Source format (optional)
      def initialize(type:, data:, source_format: nil)
        @type = type
        @data = data
        @source_format = source_format
      end

      # Convert hint to TrueType instruction format
      #
      # @return [Array<Integer>] TrueType instruction bytes
      def to_truetype
        case type
        when :stem
          convert_stem_to_truetype
        when :flex
          convert_flex_to_truetype
        when :counter
          convert_counter_to_truetype
        when :delta
          # Already in TrueType format
          data[:instructions] || []
        when :interpolate
          # IUP instruction
          [0x30] # IUP[y], or [0x31] for IUP[x]
        when :shift
          # SHP instruction
          data[:instructions] || []
        when :align
          # ALIGNRP instruction
          [0x3C]
        else
          # Unknown hint type - return empty
          []
        end
      end

      # Convert hint to PostScript hint format
      #
      # @return [Hash] PostScript hint operators and arguments
      def to_postscript
        case type
        when :stem
          convert_stem_to_postscript
        when :stem3
          convert_stem3_to_postscript
        when :flex
          convert_flex_to_postscript
        when :counter
          convert_counter_to_postscript
        when :hint_replacement
          # Hintmask operator
          { operator: :hintmask, args: data[:mask] || [] }
        when :delta, :interpolate, :shift, :align
          # TrueType-specific hints don't have direct PS equivalents
          # Return approximation using stem hints
          approximate_as_postscript
        else
          # Unknown hint type
          {}
        end
      end

      # Check if hint is compatible with target format
      #
      # @param format [Symbol] Target format (:truetype or :postscript)
      # @return [Boolean] True if compatible
      def compatible_with?(format)
        case format
        when :truetype
          # Most PostScript hints can be converted to TrueType
          %i[stem flex counter delta interpolate shift align].include?(type)
        when :postscript
          # Most TrueType hints can be approximated in PostScript
          %i[stem stem3 flex counter hint_replacement].include?(type)
        else
          false
        end
      end

      private

      # Convert stem hint to TrueType instructions
      def convert_stem_to_truetype
        position = data[:position] || 0
        width = data[:width] || 0
        orientation = data[:orientation] || :vertical

        # TrueType uses MDAP (Move Direct Absolute Point) and MDRP (Move Direct Relative Point)
        # to control stem positioning
        instructions = []

        if orientation == :vertical
          # Vertical stem: use Y-axis instructions
          instructions << 0x2E # MDAP[rnd] - mark reference point
          instructions << 0xC0 # MDRP[min,rnd,black] - move relative point
        else
          # Horizontal stem: use X-axis instructions
          instructions << 0x2F # MDAP[rnd]
          instructions << 0xC0 # MDRP[min,rnd,black]
        end

        instructions
      end

      # Convert flex hint to TrueType instructions
      def convert_flex_to_truetype
        # Flex hints ensure smooth curves
        # TrueType approximates with smooth curve flags on contour points
        # Return empty as this is handled at the contour level
        []
      end

      # Convert counter hint to TrueType instructions
      def convert_counter_to_truetype
        # Counter hints control interior space
        # TrueType uses control value program (CVT) for this
        # Return empty as this requires CVT table modification
        []
      end

      # Convert stem hint to PostScript operators
      def convert_stem_to_postscript
        position = data[:position] || 0
        width = data[:width] || 0
        orientation = data[:orientation] || :vertical

        operator = orientation == :vertical ? :vstem : :hstem

        {
          operator: operator,
          args: [position, width],
        }
      end

      # Convert stem3 hint to PostScript operators
      def convert_stem3_to_postscript
        stems = data[:stems] || []
        orientation = data[:orientation] || :vertical

        operator = orientation == :vertical ? :vstem3 : :hstem3

        # Flatten stem positions and widths
        args = stems.flat_map { |s| [s[:position], s[:width]] }

        {
          operator: operator,
          args: args,
        }
      end

      # Convert flex hint to PostScript operators
      def convert_flex_to_postscript
        points = data[:points] || []

        {
          operator: :flex,
          args: points.flat_map { |p| [p[:x], p[:y]] },
        }
      end

      # Convert counter hint to PostScript operators
      def convert_counter_to_postscript
        zones = data[:zones] || []

        {
          operator: :counter,
          args: zones,
        }
      end

      # Approximate TrueType-specific hints as PostScript stem hints
      def approximate_as_postscript
        # Best effort: create a stem hint from available data
        if data[:position] && data[:width]
          {
            operator: :vstem,
            args: [data[:position], data[:width]],
          }
        else
          {}
        end
      end
    end
  end
end
