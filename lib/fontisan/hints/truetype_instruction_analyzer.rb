# frozen_string_literal: true

module Fontisan
  module Hints
    # Analyzes TrueType bytecode instructions to extract hint parameters
    #
    # This analyzer parses fpgm (Font Program) and prep (Control Value Program)
    # bytecode to extract semantic hint information that can be converted to
    # PostScript Private dict parameters.
    #
    # **Key Extracted Parameters:**
    #
    # - Blue zones (alignment zones for baseline, x-height, cap-height)
    # - Stem widths (from CVT setup in prep)
    # - Delta base and shift values
    # - Twilight zone setup
    #
    # @example Analyze prep program
    #   analyzer = TrueTypeInstructionAnalyzer.new
    #   params = analyzer.analyze_prep(prep_bytecode, cvt_values)
    class TrueTypeInstructionAnalyzer
      # TrueType instruction opcodes relevant for hint extraction
      NPUSHB = 0x40   # Push N bytes
      NPUSHW = 0x41   # Push N words
      PUSHB = (0xB0..0xB7).to_a  # Push 1-8 bytes
      PUSHW = (0xB8..0xBF).to_a  # Push 1-8 words
      SVTCA_Y = 0x00  # Set freedom and projection vectors to Y-axis
      SVTCA_X = 0x01  # Set freedom and projection vectors to X-axis
      RCVT = 0x45     # Read CVT
      WCVTP = 0x44    # Write CVT (in Pixels)
      WCVTF = 0x70    # Write CVT (in FUnits)
      MDAP = [0x2E, 0x2F].freeze  # Move Direct Absolute Point
      SCVTCI = 0x1D   # Set Control Value Table Cut In
      SSWCI = 0x1E    # Set Single Width Cut In
      SSW = 0x1F      # Set Single Width

      # Analyze prep program to extract hint parameters
      #
      # @param prep [String] Control value program bytecode
      # @param cvt [Array<Integer>] Control values
      # @return [Hash] Extracted hint parameters
      def analyze_prep(prep, cvt = [])
        return {} if prep.nil? && (cvt.nil? || cvt.empty?)

        params = {}

        # Parse prep bytecode if present
        if prep && !prep.empty?
          bytes = prep.bytes
          stack = []
          i = 0

          while i < bytes.length
            opcode = bytes[i]

            case opcode
            when NPUSHB
              # Push N bytes
              i += 1
              count = bytes[i]
              i += 1
              count.times do
                stack.push(bytes[i])
                i += 1
              end
              next

            when NPUSHW
              # Push N words (16-bit values)
              i += 1
              count = bytes[i]
              i += 1
              count.times do
                value = (bytes[i] << 8) | bytes[i + 1]
                # Convert to signed
                value = value - 65536 if value > 32767
                stack.push(value)
                i += 2
              end
              next

            when *PUSHB
              # Push 1-8 bytes
              count = opcode - 0xB0 + 1
              i += 1
              count.times do
                stack.push(bytes[i])
                i += 1
              end
              next

            when *PUSHW
              # Push 1-8 words
              count = opcode - 0xB8 + 1
              i += 1
              count.times do
                value = (bytes[i] << 8) | bytes[i + 1]
                value = value - 65536 if value > 32767
                stack.push(value)
                i += 2
              end
              next

            when WCVTP, WCVTF
              # Write to CVT - this shows which CVT indices are being set up
              # Pattern: value cvt_index WCVTP (stack top to bottom)
              if stack.length >= 2
                value = stack.pop
                cvt_index = stack.pop
                # Track CVT modifications (useful for understanding setup)
              end

            when SSW
              # Set Single Width - used for stem width control
              if stack.length >= 1
                width = stack.pop
                params[:single_width] = width unless params[:single_width]
              end

            when SSWCI
              # Set Single Width Cut In
              if stack.length >= 1
                params[:single_width_cut_in] = stack.pop
              end

            when SCVTCI
              # Set CVT Cut In
              if stack.length >= 1
                params[:cvt_cut_in] = stack.pop
              end
            end

            i += 1
          end
        end

        # Extract blue zones from CVT analysis (always do this if CVT is present)
        if cvt && !cvt.empty?
          params.merge!(extract_blue_zones_from_cvt(cvt))
        end

        params
      rescue StandardError => e
        warn "Error analyzing prep program: #{e.message}"
        {}
      end

      # Analyze Font Program (fpgm) for complexity indicators
      #
      # The fpgm contains font-level function definitions. While we don't
      # fully decompile it, we can extract useful metadata about hint complexity.
      #
      # @param fpgm [String] Binary fpgm data
      # @return [Hash] Analysis results with complexity indicators
      def analyze_fpgm(fpgm)
        return {} if fpgm.nil? || fpgm.empty?

        size = fpgm.bytesize

        # Estimate complexity based on size
        complexity = if size < 100
                       :simple
                     elsif size < 200
                       :moderate
                     else
                       :complex
                     end

        {
          fpgm_size: size,
          has_functions: size > 0,
          complexity: complexity,
        }
      rescue StandardError
        # Return empty hash on any error
        {}
      end

      # Extract blue zones from CVT values using heuristics
      #
      # Blue zones in PostScript define alignment constraints for
      # baseline, x-height, cap-height, ascender, and descender.
      # TrueType doesn't have explicit blue zones, but we can derive
      # them from CVT values using common patterns.
      #
      # Heuristics:
      # - Negative values near -250 to -200: Descender zones
      # - Values near 0: Baseline zones
      # - Values near 500-550: X-height zones
      # - Values near 700-750: Cap-height zones
      # - For large UPM (>2000): Scale thresholds proportionally
      #
      # @param cvt [Array<Integer>] Control Value Table entries
      # @return [Hash] Extracted blue zone parameters
      def extract_blue_zones_from_cvt(cvt)
        return {} if cvt.nil? || cvt.empty?

        zones = {}

        # Detect scale from maximum absolute value
        max_value = cvt.map(&:abs).max
        scale_factor = max_value > 1000 ? (max_value / 1000.0) : 1.0

        # Scaled thresholds
        descender_min = (-300 * scale_factor).to_i
        descender_max = (-150 * scale_factor).to_i
        baseline_range = (50 * scale_factor).to_i
        xheight_min = (450 * scale_factor).to_i
        xheight_max = (600 * scale_factor).to_i
        capheight_min = (650 * scale_factor).to_i
        capheight_max = (1500 * scale_factor).to_i  # Wider range for large UPM

        # Group CVT values by typical alignment zones
        descender_values = cvt.select { |v| v < descender_max && v > descender_min }
        baseline_values = cvt.select { |v| v >= -baseline_range && v <= baseline_range }
        xheight_values = cvt.select { |v| v >= xheight_min && v <= xheight_max }
        capheight_values = cvt.select { |v| v >= capheight_min && v <= capheight_max }

        # Build blue_values (baseline and top zones)
        blue_values = []

        # Add baseline zone if detected
        if baseline_values.any?
          min_baseline = baseline_values.min
          max_baseline = baseline_values.max
          blue_values << min_baseline << max_baseline
        end

        # Add cap-height zone if detected (or any top zone for large UPM)
        if capheight_values.any?
          min_cap = capheight_values.min
          max_cap = capheight_values.max
          blue_values << min_cap << max_cap
        end

        zones[:blue_values] = blue_values unless blue_values.empty?

        # Build other_blues (descender zones)
        if descender_values.any?
          min_desc = descender_values.min
          max_desc = descender_values.max
          zones[:other_blues] = [min_desc, max_desc]
        end

        zones
      end

      private

      # Estimate complexity of bytecode program
      #
      # @param bytes [Array<Integer>] Bytecode
      # @return [Symbol] Complexity level (:simple, :moderate, :complex)
      def estimate_complexity(bytes)
        return :simple if bytes.length < 50
        return :moderate if bytes.length < 200
        :complex
      end
    end
  end
end
