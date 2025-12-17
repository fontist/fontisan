# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff2
      # Operand stack manager for CFF2 CharStrings
      #
      # This class manages the operand stack for CFF2 CharStrings, with special
      # handling for blend operations that mix base values and deltas.
      #
      # In CFF2, the blend operator takes operands in the format:
      #   [base1, delta1_axis1, delta1_axis2, ..., base2, delta2_axis1, ..., K, N]
      #
      # Where:
      #   - K = number of values to blend
      #   - N = number of variation axes
      #
      # The stack manager separates base values from deltas and applies blend
      # operations to produce final values based on variation coordinates.
      #
      # @example Managing a blend operation
      #   stack = OperandStack.new(num_axes: 2)
      #   stack.push(100, 10, 5)  # base=100, deltas=[10, 5]
      #   stack.push(200, 20, 10) # base=200, deltas=[20, 10]
      #   blended = stack.apply_blend(k: 2, coordinates: { "wght" => 0.5, "wdth" => 0.3 })
      #   # => [105.0, 206.0]  # base + (delta * scalar)
      class OperandStack
        # @return [Array<Numeric>] The operand stack
        attr_reader :stack

        # @return [Integer] Number of variation axes
        attr_reader :num_axes

        # @return [Array<Hash>] Blend values (base + deltas)
        attr_reader :blend_values

        # Initialize operand stack
        #
        # @param num_axes [Integer] Number of variation axes (default 0)
        def initialize(num_axes: 0)
          @stack = []
          @num_axes = num_axes
          @blend_values = []
        end

        # Push a value onto the stack
        #
        # @param values [Numeric] Values to push
        def push(*values)
          @stack.concat(values)
        end

        # Pop a value from the stack
        #
        # @return [Numeric, nil] Popped value or nil if empty
        def pop
          @stack.pop
        end

        # Pop multiple values from the stack
        #
        # @param count [Integer] Number of values to pop
        # @return [Array<Numeric>] Popped values
        def pop_many(count)
          return [] if count <= 0 || @stack.empty?

          @stack.pop(count)
        end

        # Shift a value from the front of the stack
        #
        # @return [Numeric, nil] Shifted value or nil if empty
        def shift
          @stack.shift
        end

        # Get the top value without popping
        #
        # @return [Numeric, nil] Top value or nil if empty
        def peek
          @stack.last
        end

        # Get stack size
        #
        # @return [Integer] Number of values on stack
        def size
          @stack.size
        end

        # Check if stack is empty
        #
        # @return [Boolean] True if empty
        def empty?
          @stack.empty?
        end

        # Clear the stack
        def clear
          @stack.clear
          @blend_values.clear
        end

        # Apply blend operation
        #
        # This pops K * (N + 1) + 2 operands from the stack, where:
        #   - K = number of values to blend
        #   - N = number of axes
        #   - Last 2 values are K and N themselves
        #
        # @param scalars [Array<Float>] Variation scalars for each axis
        # @return [Array<Float>] Blended values
        def apply_blend(scalars = [])
          # Pop N and K
          n = pop.to_i
          k = pop.to_i

          # Validate
          required_operands = k * (n + 1)
          if size < required_operands
            warn "Blend requires #{required_operands} operands, got #{size}"
            clear
            return []
          end

          # Extract operands (base + deltas for each value)
          blend_operands = pop_many(required_operands).reverse

          # Process each value to blend
          blended_values = []
          k.times do |i|
            offset = i * (n + 1)
            base = blend_operands[offset]
            deltas = blend_operands[offset + 1, n] || []

            # Apply blend: result = base + sum(delta[i] * scalar[i])
            blended = base.to_f
            deltas.each_with_index do |delta, axis_index|
              scalar = scalars[axis_index] || 0.0
              blended += delta.to_f * scalar
            end

            # Store blend info for debugging/inspection
            @blend_values << {
              base: base,
              deltas: deltas,
              blended: blended,
            }

            blended_values << blended
          end

          # Push blended values back onto stack
          push(*blended_values)

          blended_values
        end

        # Extract blend data without applying
        #
        # This is used when we need to store blend operations for later
        # application with specific coordinates.
        #
        # @return [Hash] Blend operation data
        def extract_blend_data
          # Pop N and K
          n = pop.to_i
          k = pop.to_i

          # Validate
          required_operands = k * (n + 1)
          if size < required_operands
            warn "Blend requires #{required_operands} operands, got #{size}"
            clear
            return nil
          end

          # Extract operands
          blend_operands = pop_many(required_operands).reverse

          # Parse into base + deltas structure
          blends = []
          k.times do |i|
            offset = i * (n + 1)
            base = blend_operands[offset]
            deltas = blend_operands[offset + 1, n] || []

            blends << {
              base: base,
              deltas: deltas,
            }

            # Push base value back (will be blended later)
            push(base)
          end

          {
            num_values: k,
            num_axes: n,
            blends: blends,
          }
        end

        # Get all values on the stack
        #
        # @return [Array<Numeric>] Stack contents
        def to_a
          @stack.dup
        end

        # Get string representation for debugging
        #
        # @return [String] Stack contents as string
        def inspect
          "#<OperandStack size=#{size} values=#{@stack.inspect}>"
        end

        # Get blend value history
        #
        # @return [Array<Hash>] Blend values that have been calculated
        def blend_history
          @blend_values.dup
        end

        # Reset blend history
        def reset_blend_history
          @blend_values.clear
        end
      end
    end
  end
end
