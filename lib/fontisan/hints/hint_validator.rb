# frozen_string_literal: true

module Fontisan
  module Hints
    # Validates hint data for correctness and compatibility
    #
    # This validator ensures that hints are well-formed and compatible with
    # their target format. It performs multiple levels of validation:
    # - TrueType instruction bytecode validation
    # - PostScript hint parameter validation
    # - Stack neutrality verification
    # - Hint-outline compatibility checking
    #
    # @example Validate TrueType instructions
    #   validator = HintValidator.new
    #   result = validator.validate_truetype_instructions(prep_bytes)
    #   if result[:valid]
    #     puts "Valid TrueType instructions"
    #   else
    #     puts "Errors: #{result[:errors]}"
    #   end
    #
    # @example Validate PostScript hints
    #   validator = HintValidator.new
    #   result = validator.validate_postscript_hints(ps_dict)
    #   puts result[:warnings] if result[:warnings].any?
    class HintValidator
      # Maximum allowed values for PostScript hint parameters
      MAX_BLUE_VALUES = 14      # 7 pairs
      MAX_OTHER_BLUES = 10      # 5 pairs
      MAX_STEM_SNAP = 12        # Maximum stem snap entries

      # Validate TrueType instruction bytecode
      #
      # Checks for:
      # - Valid instruction opcodes
      # - Correct parameter counts
      # - Stack neutrality
      #
      # @param instructions [String] Binary instruction bytes
      # @return [Hash] Validation result with :valid, :errors, :warnings keys
      def validate_truetype_instructions(instructions)
        if instructions.nil? || instructions.empty?
          return { valid: true, errors: [],
                   warnings: [] }
        end

        errors = []
        warnings = []

        begin
          bytes = instructions.bytes
          stack_depth = 0
          index = 0

          while index < bytes.length
            opcode = bytes[index]
            index += 1

            case opcode
            when 0x40 # NPUSHB
              count = bytes[index]
              index += 1
              if index + count > bytes.length
                errors << "NPUSHB: Not enough bytes (need #{count}, have #{bytes.length - index})"
                break
              end
              stack_depth += count
              index += count

            when 0x41 # NPUSHW
              count = bytes[index]
              index += 1
              if index + (count * 2) > bytes.length
                errors << "NPUSHW: Not enough bytes (need #{count * 2}, have #{bytes.length - index})"
                break
              end
              stack_depth += count
              index += count * 2

            when 0xB0..0xB7 # PUSHB[0-7]
              count = opcode - 0xB0 + 1
              if index + count > bytes.length
                errors << "PUSHB[#{count - 1}]: Not enough bytes"
                break
              end
              stack_depth += count
              index += count

            when 0xB8..0xBF # PUSHW[0-7]
              count = opcode - 0xB8 + 1
              if index + (count * 2) > bytes.length
                errors << "PUSHW[#{count - 1}]: Not enough bytes"
                break
              end
              stack_depth += count
              index += count * 2

            when 0x1D, 0x1E, 0x1F # SCVTCI, SSWCI, SSW
              if stack_depth < 1
                errors << "#{opcode_name(opcode)}: Stack underflow"
              end
              stack_depth -= 1

            when 0x44, 0x70 # WCVTP, WCVTF
              if stack_depth < 2
                errors << "#{opcode_name(opcode)}: Stack underflow (need 2 values)"
              end
              stack_depth -= 2

            else
              warnings << "Unknown opcode: 0x#{opcode.to_s(16).upcase} at offset #{index - 1}"
            end
          end

          # Check stack neutrality
          if stack_depth != 0
            warnings << "Stack not neutral: #{stack_depth} value(s) remaining"
          end
        rescue StandardError => e
          errors << "Exception during validation: #{e.message}"
        end

        {
          valid: errors.empty?,
          errors: errors,
          warnings: warnings,
        }
      end

      # Validate PostScript hint parameters
      #
      # Checks for:
      # - Valid parameter ranges
      # - Proper pair counts for blue zones
      # - Sensible stem width values
      #
      # @param hints [Hash] PostScript hint parameters
      # @return [Hash] Validation result with :valid, :errors, :warnings keys
      def validate_postscript_hints(hints)
        errors = []
        warnings = []

        # Validate blue_values
        if hints[:blue_values]
          blue_values = hints[:blue_values]
          if blue_values.length > MAX_BLUE_VALUES
            errors << "blue_values exceeds maximum (#{MAX_BLUE_VALUES}): #{blue_values.length}"
          end
          if blue_values.length.odd?
            errors << "blue_values must be pairs (even count): #{blue_values.length}"
          end
        end

        # Validate other_blues
        if hints[:other_blues]
          other_blues = hints[:other_blues]
          if other_blues.length > MAX_OTHER_BLUES
            errors << "other_blues exceeds maximum (#{MAX_OTHER_BLUES}): #{other_blues.length}"
          end
          if other_blues.length.odd?
            errors << "other_blues must be pairs (even count): #{other_blues.length}"
          end
        end

        # Validate stem widths
        %i[std_hw std_vw].each do |key|
          if hints[key] && hints[key] <= 0
            errors << "#{key} must be positive: #{hints[key]}"
          end
        end

        # Validate stem snaps
        %i[stem_snap_h stem_snap_v].each do |key|
          if hints[key]
            if hints[key].length > MAX_STEM_SNAP
              errors << "#{key} exceeds maximum (#{MAX_STEM_SNAP}): #{hints[key].length}"
            end
            if hints[key].any? { |v| v <= 0 }
              warnings << "#{key} contains non-positive values"
            end
          end
        end

        # Validate blue_scale
        if hints[:blue_scale]
          if hints[:blue_scale] <= 0
            errors << "blue_scale must be positive: #{hints[:blue_scale]}"
          end
          if hints[:blue_scale] > 1.0
            warnings << "blue_scale unusually large (>1.0): #{hints[:blue_scale]}"
          end
        end

        # Validate language_group
        if hints[:language_group] && ![0, 1].include?(hints[:language_group])
          errors << "language_group must be 0 (Latin) or 1 (CJK): #{hints[:language_group]}"
        end

        {
          valid: errors.empty?,
          errors: errors,
          warnings: warnings,
        }
      end

      # Validate stack neutrality of instruction sequence
      #
      # Ensures the instruction sequence leaves the stack in the same state
      # as it started (net stack change of zero).
      #
      # @param instructions [String] Binary instruction bytes
      # @return [Hash] Result with :neutral, :stack_depth, :errors keys
      def validate_stack_neutrality(instructions)
        if instructions.nil? || instructions.empty?
          return { neutral: true, stack_depth: 0,
                   errors: [] }
        end

        errors = []
        stack_depth = 0
        bytes = instructions.bytes
        index = 0

        begin
          while index < bytes.length
            opcode = bytes[index]
            index += 1

            case opcode
            when 0x40 # NPUSHB
              count = bytes[index]
              index += 1 + count
              stack_depth += count

            when 0x41 # NPUSHW
              count = bytes[index]
              index += 1 + (count * 2)
              stack_depth += count

            when 0xB0..0xB7 # PUSHB[0-7]
              count = opcode - 0xB0 + 1
              index += count
              stack_depth += count

            when 0xB8..0xBF # PUSHW[0-7]
              count = opcode - 0xB8 + 1
              index += count * 2
              stack_depth += count

            when 0x1D, 0x1E, 0x1F # SCVTCI, SSWCI, SSW
              stack_depth -= 1

            when 0x44, 0x70 # WCVTP, WCVTF
              stack_depth -= 2
            end
          end
        rescue StandardError => e
          errors << "Error analyzing stack: #{e.message}"
        end

        {
          neutral: stack_depth.zero?,
          stack_depth: stack_depth,
          errors: errors,
        }
      end

      private

      # Get human-readable name for opcode
      #
      # @param opcode [Integer] Instruction opcode
      # @return [String] Opcode name
      def opcode_name(opcode)
        case opcode
        when 0x1D then "SCVTCI"
        when 0x1E then "SSWCI"
        when 0x1F then "SSW"
        when 0x44 then "WCVTP"
        when 0x70 then "WCVTF"
        else "0x#{opcode.to_s(16).upcase}"
        end
      end
    end
  end
end
