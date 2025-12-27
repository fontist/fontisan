# frozen_string_literal: true

require_relative "../../models/hint"

module Fontisan
  module Tables
    class Cff
      # Injects hint operations into CharString operation lists
      #
      # HintOperationInjector converts abstract Hint objects into CFF CharString
      # operations and injects them at the appropriate position. It handles:
      # - Stem hints (hstem, vstem, hstemhm, vstemhm)
      # - Hint masks (hintmask with mask data)
      # - Counter masks (cntrmask with mask data)
      # - Stack management (hints are stack-neutral)
      #
      # **Position Rules:**
      # - Hints must appear BEFORE any path construction operators
      # - Width (if present) comes first
      # - Stem hints come before hintmask/cntrmask
      # - Once path construction begins, no more hints allowed
      #
      # **Stack Neutrality:**
      # - Hint operators consume their operands
      # - They don't leave anything on the stack
      # - Path construction starts with clean stack
      #
      # Reference: Type 2 CharString Format Section 4
      # Adobe Technical Note #5177
      #
      # @example Inject hints into a glyph
      #   injector = HintOperationInjector.new
      #   hints = [
      #     Hint.new(type: :stem, data: { position: 100, width: 50, orientation: :horizontal })
      #   ]
      #   modified_ops = injector.inject(hints, original_operations)
      class HintOperationInjector
        # Initialize injector
        def initialize
          @stem_count = 0
        end

        # Inject hint operations into operation list
        #
        # @param hints [Array<Models::Hint>] Hints to inject
        # @param operations [Array<Hash>] Original CharString operations
        # @return [Array<Hash>] Modified operations with hints injected
        def inject(hints, operations)
          return operations if hints.nil? || hints.empty?

          # Convert hints to operations
          hint_ops = convert_hints_to_operations(hints)
          return operations if hint_ops.empty?

          # Find injection point (before first path operator)
          inject_index = find_injection_point(operations)

          # Insert hint operations
          operations.dup.insert(inject_index, *hint_ops)
        end

        # Get stem count after injection (needed for hintmask)
        #
        # @return [Integer] Number of stem hints
        attr_reader :stem_count

        private

        # Convert Hint objects to CharString operations
        #
        # @param hints [Array<Models::Hint>] Hints to convert
        # @return [Array<Hash>] CharString operations
        def convert_hints_to_operations(hints)
          operations = []
          @stem_count = 0

          hints.each do |hint|
            ops = hint_to_operations(hint)
            operations.concat(ops)
          end

          operations
        end

        # Convert single Hint to operations
        #
        # @param hint [Models::Hint] Hint object
        # @return [Array<Hash>] CharString operations
        def hint_to_operations(hint)
          ps_hint = hint.to_postscript
          return [] if ps_hint.empty?

          case ps_hint[:operator]
          when :hstem, :vstem
            stem_operation(ps_hint)
          when :hstemhm, :vstemhm
            stem_operation(ps_hint)
          when :hintmask
            hintmask_operation(ps_hint)
          when :counter, :cntrmask
            # :counter from Hint model maps to :cntrmask in CharStrings
            cntrmask_operation(ps_hint)
          else
            []
          end
        end

        # Create stem hint operation
        #
        # @param ps_hint [Hash] PostScript hint with :operator and :args
        # @return [Array<Hash>] CharString operations
        def stem_operation(ps_hint)
          operator = ps_hint[:operator]
          args = ps_hint[:args] || []

          # Each pair of args is one stem
          @stem_count += args.length / 2

          [{
            type: :operator,
            name: operator,
            operands: args,
            hint_data: nil
          }]
        end

        # Create hintmask operation
        #
        # @param ps_hint [Hash] PostScript hint with :operator and :args (mask)
        # @return [Array<Hash>] CharString operations
        def hintmask_operation(ps_hint)
          mask_bytes = ps_hint[:args] || []

          # Convert mask array to binary string
          hint_data = if mask_bytes.is_a?(Array)
                        mask_bytes.pack("C*")
                      elsif mask_bytes.is_a?(String)
                        mask_bytes
                      else
                        ""
                      end

          [{
            type: :operator,
            name: :hintmask,
            operands: [],
            hint_data: hint_data
          }]
        end

        # Create cntrmask operation
        #
        # @param ps_hint [Hash] PostScript hint with :operator and :args (zones)
        # @return [Array<Hash>] CharString operations
        def cntrmask_operation(ps_hint)
          zones = ps_hint[:args] || []

          # Convert zones to binary string
          hint_data = if zones.is_a?(Array)
                        zones.pack("C*")
                      elsif zones.is_a?(String)
                        zones
                      else
                        ""
                      end

          [{
            type: :operator,
            name: :cntrmask,
            operands: [],
            hint_data: hint_data
          }]
        end

        # Find injection point for hints
        #
        # Hints must go before first path construction operator.
        # Path operators: moveto, lineto, curveto, etc.
        #
        # @param operations [Array<Hash>] CharString operations
        # @return [Integer] Index to insert hints
        def find_injection_point(operations)
          # Path construction operators
          path_operators = %i[
            rmoveto hmoveto vmoveto
            rlineto hlineto vlineto
            rrcurveto rcurveline rlinecurve
            vvcurveto hhcurveto vhcurveto hvcurveto
          ]

          # Find first path operator
          operations.each_with_index do |op, index|
            return index if path_operators.include?(op[:name])
          end

          # No path operators found - hints go before endchar
          operations.each_with_index do |op, index|
            return index if op[:name] == :endchar
          end

          # Empty or malformed - inject at start
          0
        end
      end
    end
  end
end