# frozen_string_literal: true

require "json"

module Fontisan
  module Models
    # Container for all font hint data
    #
    # This model holds complete hint information from a font including
    # font-level programs, control values, and per-glyph hints. It provides
    # a format-agnostic representation that can be converted between
    # TrueType and PostScript formats.
    #
    # @example Creating a HintSet
    #   hint_set = HintSet.new(
    #     format: :truetype,
    #     font_program: fpgm_data,
    #     control_value_program: prep_data
    #   )
    class HintSet
      # @return [String] Hint format (:truetype or :postscript)
      attr_accessor :format

      # TrueType font-level hint data
      # @return [String] Font program (fpgm table) - bytecode executed once
      attr_accessor :font_program

      # @return [String] Control value program (prep table) - initialization code
      attr_accessor :control_value_program

      # @return [Array<Integer>] Control values (cvt table) - metrics for hinting
      attr_accessor :control_values

      # PostScript font-level hint data
      # @return [String] CFF Private dict hint data (BlueValues, StdHW, etc.) as JSON
      attr_accessor :private_dict_hints

      # @return [Integer] Number of glyphs with hints
      attr_accessor :hinted_glyph_count

      # @return [Boolean] Whether hints are present
      attr_accessor :has_hints

      # Initialize a new HintSet
      #
      # @param format [String, Symbol] Hint format (:truetype or :postscript)
      # @param font_program [String] Font program bytecode
      # @param control_value_program [String] Control value program bytecode
      # @param control_values [Array<Integer>] Control values
      # @param private_dict_hints [String] Private dict hints as JSON
      # @param hinted_glyph_count [Integer] Number of hinted glyphs
      # @param has_hints [Boolean] Whether hints are present
      def initialize(format: nil, font_program: "", control_value_program: "",
                     control_values: [], private_dict_hints: "{}",
                     hinted_glyph_count: 0, has_hints: false)
        @format = format.to_s if format
        @font_program = font_program || ""
        @control_value_program = control_value_program || ""
        @control_values = control_values || []
        @private_dict_hints = private_dict_hints || "{}"
        @glyph_hints = "{}"
        @hinted_glyph_count = hinted_glyph_count
        @has_hints = has_hints
      end

      # Add hints for a specific glyph
      #
      # @param glyph_id [Integer, String] Glyph identifier
      # @param hints [Array<Hint>] Hints for the glyph
      def add_glyph_hints(glyph_id, hints)
        return if hints.nil? || hints.empty?

        glyph_hints_hash = parse_glyph_hints
        # Convert Hint objects to hashes for storage
        hints_data = hints.map do |h|
          {
            type: h.type,
            data: h.data,
            source_format: h.source_format
          }
        end
        glyph_hints_hash[glyph_id.to_s] = hints_data
        @glyph_hints = glyph_hints_hash.to_json
        @hinted_glyph_count = glyph_hints_hash.keys.length
        @has_hints = true
      end

      # Get hints for a specific glyph
      #
      # @param glyph_id [Integer, String] Glyph identifier
      # @return [Array<Hint>] Hints for the glyph
      def get_glyph_hints(glyph_id)
        glyph_hints_hash = parse_glyph_hints
        hints_data = glyph_hints_hash[glyph_id.to_s]
        return [] unless hints_data

        # Reconstruct Hint objects from serialized data
        hints_data.map { |h| Hint.new(**h.transform_keys(&:to_sym)) }
      end

      # Get all glyph IDs with hints
      #
      # @return [Array<String>] Glyph identifiers
      def hinted_glyph_ids
        parse_glyph_hints.keys
      end

      # Check if empty (no hints)
      #
      # @return [Boolean] True if no hints present
      def empty?
        !has_hints &&
          (font_program.nil? || font_program.empty?) &&
          (control_value_program.nil? || control_value_program.empty?) &&
          (control_values.nil? || control_values.empty?) &&
          (private_dict_hints.nil? || private_dict_hints == "{}")
      end

      private

      # @return [String] Glyph hints as JSON
      attr_accessor :glyph_hints

      # Parse glyph hints JSON
      def parse_glyph_hints
        return {} if @glyph_hints.nil? || @glyph_hints.empty? || @glyph_hints == "{}"
        JSON.parse(@glyph_hints)
      rescue JSON::ParserError
        {}
      end
    end

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
        when :stem3
          convert_stem3_to_truetype
        when :flex
          convert_flex_to_truetype
        when :counter
          convert_counter_to_truetype
        when :hint_replacement
          convert_hintmask_to_truetype
        when :delta
          # Already in TrueType format
          data[:instructions] || []
        when :interpolate
          # IUP instruction
          axis = data[:axis] || :y
          axis == :x ? [0x31] : [0x30]  # IUP[x] or IUP[y]
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
      rescue StandardError => e
        warn "Error converting hint type #{type} to TrueType: #{e.message}"
        []
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
      rescue StandardError => e
        warn "Error converting hint type #{type} to PostScript: #{e.message}"
        {}
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

      # Convert stem3 hint to TrueType instructions
      def convert_stem3_to_truetype
        stems = data[:stems] || []
        orientation = data[:orientation] || :vertical

        # Generate MDAP/MDRP pairs for each stem
        instructions = []

        stems.each do |stem|
          if orientation == :vertical
            # Vertical stem: use Y-axis instructions
            instructions << 0x2E # MDAP[rnd] - mark reference point
            instructions << 0xC0 # MDRP[min,rnd,black] - move relative point
          else
            # Horizontal stem: use X-axis instructions
            instructions << 0x2F # MDAP[rnd]
            instructions << 0xC0 # MDRP[min,rnd,black]
          end
        end

        instructions
      end

      # Convert hintmask hint to TrueType instructions
      def convert_hintmask_to_truetype
        # Hintmask controls which hints are active at runtime
        # TrueType doesn't have a direct equivalent
        # We can use conditional instructions, but it's complex
        # For now, return empty and let the main stems handle hinting
        # TODO: Implement conditional instruction generation if needed
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
