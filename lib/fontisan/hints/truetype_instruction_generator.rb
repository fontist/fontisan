# frozen_string_literal: true

module Fontisan
  module Hints
    # Generates TrueType instruction bytecode from PostScript hint parameters
    #
    # This class is the inverse of TrueTypeInstructionAnalyzer - it takes
    # PostScript hint parameters and generates equivalent TrueType prep/fpgm
    # programs and CVT values.
    #
    # TrueType Instruction Opcodes:
    # - NPUSHB (0x40): Push n bytes
    # - NPUSHW (0x41): Push n words (16-bit)
    # - PUSHB[n] (0xB0-0xB7): Push 1-8 bytes
    # - PUSHW[n] (0xB8-0xBF): Push 1-8 words
    # - SSW (0x1F): Set Single Width
    # - SSWCI (0x1E): Set Single Width Cut-In
    # - SCVTCI (0x1D): Set CVT Cut-In
    # - WCVTP (0x44): Write CVT in Pixels
    # - WCVTF (0x70): Write CVT in FUnits
    #
    # @example Generate TrueType programs
    #   generator = TrueTypeInstructionGenerator.new
    #   programs = generator.generate({
    #     blue_scale: 0.039625,
    #     std_hw: 80,
    #     std_vw: 90
    #   })
    #   programs[:prep] # => Binary prep program
    #   programs[:fpgm] # => Binary fpgm program (usually empty)
    #   programs[:cvt]  # => Array of CVT values
    class TrueTypeInstructionGenerator
      # TrueType instruction opcodes
      NPUSHB = 0x40  # Push n bytes
      NPUSHW = 0x41  # Push n words (16-bit)
      PUSHB_BASE = 0xB0  # PUSHB[0] through PUSHB[7]
      PUSHW_BASE = 0xB8  # PUSHW[0] through PUSHW[7]
      SSW = 0x1F     # Set Single Width
      SSWCI = 0x1E   # Set Single Width Cut-In
      SCVTCI = 0x1D  # Set CVT Cut-In
      WCVTP = 0x44   # Write CVT in Pixels
      WCVTF = 0x70   # Write CVT in FUnits

      # Size thresholds for instruction selection
      MAX_PUSHB_INLINE = 8  # Maximum bytes for PUSHB[n]
      MAX_PUSHW_INLINE = 8  # Maximum words for PUSHW[n]
      BYTE_MAX = 255        # Maximum value for byte
      WORD_MAX = 65535      # Maximum value for word

      # Generate TrueType programs and CVT from PostScript parameters
      #
      # @param ps_params [Hash] PostScript hint parameters
      # @option ps_params [Float] :blue_scale Blue scale value (0.0-1.0)
      # @option ps_params [Integer] :std_hw Standard horizontal width
      # @option ps_params [Integer] :std_vw Standard vertical width
      # @option ps_params [Array<Integer>] :stem_snap_h Horizontal stem snap values
      # @option ps_params [Array<Integer>] :stem_snap_v Vertical stem snap values
      # @option ps_params [Array<Integer>] :blue_values Blue zone values
      # @option ps_params [Array<Integer>] :other_blues Other blue zone values
      # @return [Hash] Hash with :prep, :fpgm, and :cvt keys
      def generate(ps_params)
        # Normalize keys to symbols
        ps_params = normalize_keys(ps_params)

        {
          fpgm: generate_fpgm(ps_params),
          prep: generate_prep(ps_params),
          cvt: generate_cvt(ps_params)
        }
      end

      # Generate prep (Control Value Program) from PostScript parameters
      #
      # The prep program sets up global hint parameters:
      # - CVT Cut-In (from blue_scale)
      # - Single Width Cut-In (from std_hw/std_vw)
      # - Single Width (from std_hw or std_vw)
      #
      # @param ps_params [Hash] PostScript parameters
      # @return [String] Binary instruction bytes
      def generate_prep(ps_params)
        instructions = []

        # Set CVT Cut-In from blue_scale if present
        if ps_params[:blue_scale]
          cvt_cut_in = calculate_cvt_cut_in(ps_params[:blue_scale])
          instructions.concat(push_value(cvt_cut_in))
          instructions << SCVTCI
        end

        # Set Single Width Cut-In if we have stem widths
        if ps_params[:std_hw] || ps_params[:std_vw]
          sw_cut_in = calculate_sw_cut_in(ps_params)
          instructions.concat(push_value(sw_cut_in))
          instructions << SSWCI
        end

        # Set Single Width (prefer horizontal, fall back to vertical)
        single_width = ps_params[:std_hw] || ps_params[:std_vw]
        if single_width
          instructions.concat(push_value(single_width))
          instructions << SSW
        end

        instructions.pack("C*")
      end

      # Generate fpgm (Font Program) from PostScript parameters
      #
      # For converted fonts, fpgm is typically empty as font-level
      # functions are not needed for basic hint conversion.
      #
      # @param _ps_params [Hash] PostScript parameters (unused)
      # @return [String] Binary instruction bytes (empty for converted fonts)
      def generate_fpgm(_ps_params)
        # For converted fonts, fpgm is typically empty
        # Advanced implementations might generate function definitions here
        "".b
      end

      # Generate CVT (Control Value Table) from PostScript parameters
      #
      # CVT entries are derived from:
      # - stem_snap_h/stem_snap_v: Stem widths
      # - blue_values/other_blues: Alignment zones
      # - std_hw/std_vw: Standard widths
      #
      # Duplicates are removed and values sorted for optimal CVT organization.
      #
      # @param ps_params [Hash] PostScript parameters
      # @return [Array<Integer>] Array of 16-bit signed integers
      def generate_cvt(ps_params)
        cvt = []

        # Add standard widths to CVT
        cvt << ps_params[:std_hw] if ps_params[:std_hw]
        cvt << ps_params[:std_vw] if ps_params[:std_vw]

        # Add stem snap values
        if ps_params[:stem_snap_h]
          cvt.concat(ps_params[:stem_snap_h])
        end

        if ps_params[:stem_snap_v]
          cvt.concat(ps_params[:stem_snap_v])
        end

        # Add blue zone values (as pairs: bottom, top)
        if ps_params[:blue_values]
          cvt.concat(ps_params[:blue_values])
        end

        if ps_params[:other_blues]
          cvt.concat(ps_params[:other_blues])
        end

        # Remove duplicates and sort for optimal CVT organization
        cvt.uniq.sort
      end

      private

      # Normalize hash keys to symbols
      #
      # @param hash [Hash] Input hash with string or symbol keys
      # @return [Hash] Hash with symbol keys
      def normalize_keys(hash)
        return hash unless hash.is_a?(Hash)
        return hash if hash.empty? || hash.keys.first.is_a?(Symbol)

        hash.transform_keys(&:to_sym)
      end

      # Calculate CVT Cut-In from PostScript blue_scale
      #
      # Blue scale controls the threshold at which alignment zones apply.
      # We convert this to TrueType's CVT Cut-In value.
      #
      # @param blue_scale [Float] PostScript blue scale (0.0-1.0)
      # @return [Integer] CVT Cut-In value in pixels
      def calculate_cvt_cut_in(blue_scale)
        # blue_scale of 0.039625 (common default) maps to ~17px cut-in
        # Linear scaling: 0.039625 -> 17, 0.0 -> 0, 1.0 -> 428
        (blue_scale * 428).round.clamp(0, 255)
      end

      # Calculate Single Width Cut-In from stem widths
      #
      # The cut-in determines when to apply single-width rounding.
      # We use 9 pixels as a sensible default.
      #
      # @param _ps_params [Hash] PostScript parameters (for future use)
      # @return [Integer] Single Width Cut-In in pixels
      def calculate_sw_cut_in(_ps_params)
        9 # Standard value: 9 pixels
      end

      # Push a single value onto the TrueType stack
      #
      # Selects the most efficient instruction based on value size.
      #
      # @param value [Integer] Value to push
      # @return [Array<Integer>] Instruction bytes
      def push_value(value)
        if value <= BYTE_MAX
          push_bytes([value])
        else
          push_words([value])
        end
      end

      # Push byte values using most efficient instruction
      #
      # Uses PUSHB[n] for 1-8 values, NPUSHB for more.
      #
      # @param values [Array<Integer>] Byte values (0-255)
      # @return [Array<Integer>] Instruction bytes
      def push_bytes(values)
        return [] if values.empty?

        # Validate all values fit in bytes
        unless values.all? { |v| v >= 0 && v <= BYTE_MAX }
          raise ArgumentError, "Values must be in range 0-255 for PUSHB"
        end

        count = values.size

        if count <= MAX_PUSHB_INLINE
          # Use PUSHB[n-1] for 1-8 values
          [PUSHB_BASE + count - 1] + values
        else
          # Use NPUSHB for more than 8 values
          [NPUSHB, count] + values
        end
      end

      # Push word values using most efficient instruction
      #
      # Uses PUSHW[n] for 1-8 values, NPUSHW for more.
      # Words are encoded big-endian (high byte first).
      #
      # @param values [Array<Integer>] Word values (0-65535)
      # @return [Array<Integer>] Instruction bytes
      def push_words(values)
        return [] if values.empty?

        # Validate all values fit in words
        unless values.all? { |v| v >= 0 && v <= WORD_MAX }
          raise ArgumentError, "Values must be in range 0-65535 for PUSHW"
        end

        count = values.size
        # Convert words to big-endian byte pairs
        word_bytes = values.flat_map { |v| [(v >> 8) & 0xFF, v & 0xFF] }

        if count <= MAX_PUSHW_INLINE
          # Use PUSHW[n-1] for 1-8 values
          [PUSHW_BASE + count - 1] + word_bytes
        else
          # Use NPUSHW for more than 8 values
          [NPUSHW, count] + word_bytes
        end
      end
    end
  end
end