# frozen_string_literal: true

require_relative "charstring_parser"
require_relative "charstring_builder"
require_relative "index_builder"

module Fontisan
  module Tables
    class Cff
      # Rebuilds CharStrings INDEX with modified CharStrings
      #
      # CharStringRebuilder provides high-level interface for modifying
      # CharStrings in a CFF font. It extracts all CharStrings from the source
      # INDEX, allows modifications through a callback, and rebuilds the INDEX
      # with updated CharString data.
      #
      # Use Cases:
      # - Per-glyph hint injection
      # - CharString optimization
      # - Subroutine insertion
      # - Any operation requiring CharString modification
      #
      # @example Inject hints into specific glyphs
      #   rebuilder = CharStringRebuilder.new(charstrings_index)
      #   rebuilder.modify_charstring(42) do |operations|
      #     # Insert hint operations at beginning
      #     hint_ops = [
      #       { type: :operator, name: :hstem, operands: [10, 20] }
      #     ]
      #     hint_ops + operations
      #   end
      #   new_index_data = rebuilder.rebuild
      class CharStringRebuilder
        # @return [CharstringsIndex] Source CharStrings INDEX
        attr_reader :source_index

        # @return [Hash] Modified CharString data by glyph index
        attr_reader :modifications

        # Initialize rebuilder with source CharStrings INDEX
        #
        # @param source_index [CharstringsIndex] Source CharStrings INDEX
        # @param stem_count [Integer] Number of stem hints (for parsing hintmask)
        def initialize(source_index, stem_count: 0)
          @source_index = source_index
          @stem_count = stem_count
          @modifications = {}
        end

        # Modify a CharString by glyph index
        #
        # The block receives the parsed operations for the glyph and should
        # return modified operations.
        #
        # @param glyph_index [Integer] Glyph index (0 = .notdef)
        # @yield [operations] Block to modify operations
        # @yieldparam operations [Array<Hash>] Parsed operations
        # @yieldreturn [Array<Hash>] Modified operations
        def modify_charstring(glyph_index, &block)
          # Get original CharString data
          original_data = @source_index[glyph_index]
          return unless original_data

          # Parse to operations
          parser = CharStringParser.new(original_data, stem_count: @stem_count)
          operations = parser.parse

          # Apply modification
          modified_operations = block.call(operations)

          # Build new CharString
          new_data = CharStringBuilder.build_from_operations(modified_operations)

          # Store modification
          @modifications[glyph_index] = new_data
        end

        # Rebuild CharStrings INDEX with modifications
        #
        # Creates new INDEX with modified CharStrings, keeping unmodified
        # CharStrings unchanged.
        #
        # @return [String] Binary CharStrings INDEX data
        def rebuild
          # Collect all CharString data (modified and unmodified)
          charstrings = []

          (0...@source_index.count).each do |i|
            if @modifications.key?(i)
              # Use modified CharString
              charstrings << @modifications[i]
            else
              # Use original CharString
              charstrings << @source_index[i]
            end
          end

          # Build INDEX
          IndexBuilder.build(charstrings)
        end

        # Batch modify multiple CharStrings
        #
        # More efficient than calling modify_charstring multiple times.
        #
        # @param glyph_indices [Array<Integer>] Glyph indices to modify
        # @yield [glyph_index, operations] Block to modify each glyph
        # @yieldparam glyph_index [Integer] Current glyph index
        # @yieldparam operations [Array<Hash>] Parsed operations
        # @yieldreturn [Array<Hash>] Modified operations
        def batch_modify(glyph_indices, &block)
          glyph_indices.each do |glyph_index|
            modify_charstring(glyph_index) do |operations|
              block.call(glyph_index, operations)
            end
          end
        end

        # Modify all CharStrings
        #
        # Applies the same modification to every glyph.
        #
        # @yield [glyph_index, operations] Block to modify each glyph
        # @yieldparam glyph_index [Integer] Current glyph index
        # @yieldparam operations [Array<Hash>] Parsed operations
        # @yieldreturn [Array<Hash>] Modified operations
        def modify_all(&block)
          (0...@source_index.count).each do |i|
            modify_charstring(i) do |operations|
              block.call(i, operations)
            end
          end
        end

        # Get CharString data (modified or original)
        #
        # @param glyph_index [Integer] Glyph index
        # @return [String] CharString binary data
        def charstring_data(glyph_index)
          @modifications[glyph_index] || @source_index[glyph_index]
        end

        # Check if glyph has been modified
        #
        # @param glyph_index [Integer] Glyph index
        # @return [Boolean] True if modified
        def modified?(glyph_index)
          @modifications.key?(glyph_index)
        end

        # Get count of modified glyphs
        #
        # @return [Integer] Number of modified glyphs
        def modification_count
          @modifications.size
        end

        # Clear all modifications
        def clear_modifications
          @modifications.clear
        end

        # Update stem count (needed for hintmask parsing)
        #
        # @param count [Integer] Number of stem hints
        def stem_count=(count)
          @stem_count = count
        end
      end
    end
  end
end