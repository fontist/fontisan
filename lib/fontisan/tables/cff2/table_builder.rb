# frozen_string_literal: true

require_relative "../cff/table_builder"
require_relative "table_reader"
require_relative "private_dict_blend_handler"
require_relative "../cff/charstring_parser"
require_relative "../cff/charstring_builder"
require_relative "../cff/hint_operation_injector"
require_relative "../cff/dict_builder"
require "stringio"

module Fontisan
  module Tables
    class Cff2
      # Rebuilds CFF2 table with modifications while preserving variation data
      #
      # CFF2TableBuilder extends CFF TableBuilder to handle CFF2-specific
      # structures including Variable Store and blend operators in CharStrings.
      # It preserves variation data while applying hints to variable fonts.
      #
      # Key Principles:
      # - Variable Store is read-only and preserved unchanged
      # - Blend operators in CharStrings are maintained
      # - Blend in Private DICT is preserved
      # - Reuses Phase 1+2 infrastructure for CharString modification
      #
      # Reference: Adobe Technical Note #5177 (CFF2)
      #
      # @example Rebuild CFF2 with hints
      #   reader = CFF2TableReader.new(cff2_data)
      #   builder = CFF2TableBuilder.new(reader, hint_set)
      #   new_cff2 = builder.build
      class TableBuilder < Tables::Cff::TableBuilder
        # @return [CFF2TableReader] CFF2 table reader
        attr_reader :reader

        # @return [Hash, nil] Variable Store data
        attr_reader :variable_store

        # @return [Integer] Number of variation axes
        attr_reader :num_axes

        # Initialize builder with CFF2 table reader and hint set
        #
        # @param reader [CFF2TableReader] CFF2 table reader
        # @param hint_set [Object] Hint set with font-level and per-glyph hints
        def initialize(reader, hint_set = nil)
          @reader = reader
          @hint_set = hint_set

          # Read CFF2 structures
          @reader.read_header
          @reader.read_top_dict
          @variable_store = @reader.read_variable_store

          # Determine number of axes from Variable Store
          @num_axes = extract_num_axes

          # Don't call super - CFF2 has different structure
        end

        # Build CFF2 table with hints applied
        #
        # @return [String] Binary CFF2 table data
        def build
          # Check if we need to modify anything
          return @reader.data unless should_modify?

          # Extract and modify sections
          header_data = extract_header
          top_dict_hash = @reader.top_dict
          charstrings_data = extract_and_modify_charstrings
          private_dict_data = extract_and_modify_private_dict
          vstore_data = extract_variable_store

          # Rebuild CFF2 table
          rebuild_cff2_table(
            header: header_data,
            top_dict: top_dict_hash,
            charstrings: charstrings_data,
            private_dict: private_dict_data,
            vstore: vstore_data
          )
        end

        # Check if table has variation data
        #
        # @return [Boolean] True if Variable Store present
        def variable?
          !@variable_store.nil?
        end

        private

        # Extract number of variation axes from Variable Store
        #
        # @return [Integer] Number of axes
        def extract_num_axes
          return 0 unless @variable_store

          # Get from first region's axis count
          regions = @variable_store[:regions]
          return 0 if regions.nil? || regions.empty?

          regions.first[:axis_count] || 0
        end

        # Extract CharStrings offset from Top DICT
        #
        # CFF2 Top DICT operator 17 contains CharStrings offset.
        #
        # @return [Integer] CharStrings offset
        def extract_charstrings_offset
          top_dict = @reader.top_dict
          return nil unless top_dict

          # Operator 17 = CharStrings offset
          top_dict[17]
        end

        # Modify CharStrings with per-glyph hints
        #
        # Uses Phase 1 CharStringRebuilder and Phase 2 HintOperationInjector
        # to inject hints while preserving blend operators.
        #
        # @param charstrings_index [CharstringsIndex] Source CharStrings INDEX
        # @return [String] Modified CharStrings INDEX binary data
        def modify_charstrings(charstrings_index)
          return nil unless @hint_set

          # Get hinted glyph IDs from HintSet
          hinted_glyph_ids = @hint_set.hinted_glyph_ids
          return nil if hinted_glyph_ids.empty?

          # Create rebuilder with stem count
          stem_count = calculate_stem_count
          rebuilder = Cff::CharStringRebuilder.new(charstrings_index, stem_count: stem_count)

          # Modify each glyph with hints
          hinted_glyph_ids.each do |glyph_id|
            # Get hints for this glyph
            hints = @hint_set.get_glyph_hints(glyph_id)
            next if hints.nil? || hints.empty?

            # Convert glyph_id to integer if it's a string
            glyph_index = glyph_id.to_i

            rebuilder.modify_charstring(glyph_index) do |operations|
              # Inject hints while preserving blend operators
              injector = Cff::HintOperationInjector.new
              injector.inject(hints, operations)
            end
          end

          # Rebuild CharStrings INDEX
          rebuilder.rebuild
        end

        # Calculate stem count from font-level hints
        #
        # Stem count is needed for hintmask/cntrmask parsing.
        # Extracted from blue values and stem snap arrays.
        #
        # @return [Integer] Total stem count (hstem + vstem)
        def calculate_stem_count
          return 0 unless @hint_set

          # Get font-level hints (from private_dict_hints JSON)
          return 0 unless @hint_set.respond_to?(:private_dict_hints)

          begin
            font_hints = JSON.parse(@hint_set.private_dict_hints || "{}")
          rescue JSON::ParserError
            return 0
          end

          return 0 if font_hints.nil? || font_hints.empty?

          # Count stems from blue zones (hstem)
          hstem_count = 0
          blue_values = font_hints["blue_values"] || font_hints[:blue_values]
          if blue_values && blue_values.is_a?(Array)
            hstem_count = blue_values.size / 2
          end

          # Count stems from stem snap (vstem)
          vstem_count = 0
          stem_snap_h = font_hints["stem_snap_h"] || font_hints[:stem_snap_h]
          if stem_snap_h && stem_snap_h.is_a?(Array)
            vstem_count = stem_snap_h.size
          end

          hstem_count + vstem_count
        end

        # Check if font-level hints are present
        #
        # @return [Boolean] True if private_dict_hints are present
        def has_font_level_hints?
          return false unless @hint_set.respond_to?(:private_dict_hints)

          hints = JSON.parse(@hint_set.private_dict_hints || "{}")
          !hints.empty?
        rescue JSON::ParserError
          false
        end

        # Modify Private DICT with font-level hints
        #
        # Handles variable hint values using PrivateDictBlendHandler
        # while preserving existing blend operators.
        #
        # @return [Hash, nil] Modified Private DICT data
        def modify_private_dict
          # Read original Private DICT
          private_dict_info = extract_private_dict_info
          return nil unless private_dict_info

          size, offset = private_dict_info
          private_dict = @reader.read_private_dict(size, offset)

          # Create handler
          handler = PrivateDictBlendHandler.new(private_dict)

          # Get font-level hints
          font_hints = JSON.parse(@hint_set.private_dict_hints)

          # Rebuild with hints (preserving blend)
          handler.rebuild_with_hints(font_hints, num_axes: @num_axes)
        end

        # Extract Private DICT information from Top DICT
        #
        # @return [Array<Integer>, nil] [size, offset] or nil if not present
        def extract_private_dict_info
          # Extract from Top DICT (operator 18)
          private_info = @reader.top_dict[18]
          return nil unless private_info

          # Format: [size, offset]
          private_info
        end

        # Preserve Variable Store unchanged
        #
        # Variable Store is read-only for hint application.
        # We simply copy it to output without modification.
        #
        # @return [Hash, nil] Variable Store data
        def preserve_variable_store
          @variable_store
        end

        # Check if modification is needed
        #
        # @return [Boolean] True if hints should be applied
        def should_modify?
          return false unless @hint_set

          has_per_glyph = !@hint_set.hinted_glyph_ids.empty?
          has_font_level = has_font_level_hints?

          has_per_glyph || has_font_level
        end

        # Extract CFF2 header bytes
        #
        # @return [String] Binary header data
        def extract_header
          header_size = @reader.header[:header_size]
          @reader.data[0, header_size]
        end

        # Extract and optionally modify CharStrings
        #
        # @return [String] CharStrings INDEX binary data
        def extract_and_modify_charstrings
          charstrings_offset = extract_charstrings_offset
          return nil unless charstrings_offset

          charstrings_index = @reader.read_charstrings(charstrings_offset)

          if @hint_set && !@hint_set.hinted_glyph_ids.empty?
            modify_charstrings(charstrings_index)
          else
            # Return original CharStrings as binary
            extract_charstrings_binary(charstrings_offset)
          end
        end

        # Extract CharStrings INDEX as binary
        #
        # @param offset [Integer] CharStrings offset in table
        # @return [String] Binary CharStrings INDEX data
        def extract_charstrings_binary(offset)
          io = StringIO.new(@reader.data)
          io.seek(offset)

          # Read INDEX structure: count (2 bytes)
          count = io.read(2).unpack1("n")
          return [0].pack("n") if count.zero?

          # Read offSize (1 byte)
          off_size = io.read(1).unpack1("C")

          # Calculate INDEX size
          # count + offSize + (count+1)*offSize + data_size
          offset_array_size = (count + 1) * off_size

          # Read offset array to get data size
          offsets = []
          (count + 1).times do
            offset_bytes = io.read(off_size)
            case off_size
            when 1
              offsets << offset_bytes.unpack1("C")
            when 2
              offsets << offset_bytes.unpack1("n")
            when 3
              offsets << (offset_bytes.bytes[0] << 16 | offset_bytes.bytes[1] << 8 | offset_bytes.bytes[2])
            when 4
              offsets << offset_bytes.unpack1("N")
            end
          end

          data_size = offsets.last - 1 # Offsets are 1-based

          # Calculate total INDEX size
          index_size = 2 + 1 + offset_array_size + data_size

          # Reset and extract full INDEX
          io.seek(offset)
          io.read(index_size)
        end

        # Extract and optionally modify Private DICT
        #
        # @return [String, nil] Binary Private DICT data
        def extract_and_modify_private_dict
          if @hint_set && has_font_level_hints?
            # Modify and serialize
            modified_dict = modify_private_dict
            return nil unless modified_dict

            serialize_private_dict(modified_dict)
          else
            # Return original Private DICT
            private_dict_info = extract_private_dict_info
            return nil unless private_dict_info

            size, offset = private_dict_info
            @reader.data[offset, size]
          end
        end

        # Extract Variable Store as binary (unchanged)
        #
        # @return [String, nil] Binary Variable Store data
        def extract_variable_store
          return nil unless @variable_store

          vstore_offset = @reader.top_dict[24] # operator 24 = vstore
          return nil unless vstore_offset

          # Extract Variable Store bytes unchanged
          # For simplicity, extract from vstore_offset to end of table
          # In production, we'd parse structure to get exact size
          @reader.data[vstore_offset..-1]
        end

        # Rebuild complete CFF2 table
        #
        # @param header [String] CFF2 header
        # @param top_dict [Hash] Top DICT hash
        # @param charstrings [String] CharStrings INDEX
        # @param private_dict [String, nil] Private DICT
        # @param vstore [String, nil] Variable Store
        # @return [String] Complete CFF2 table binary
        def rebuild_cff2_table(header:, top_dict:, charstrings:, private_dict:, vstore:)
          output = StringIO.new("".b)

          # 1. Write Header
          output.write(header)

          # 2. Calculate offsets for all sections
          offsets = calculate_cff2_offsets(
            header_size: header.size,
            charstrings: charstrings,
            private_dict: private_dict,
            vstore: vstore
          )

          # 3. Build Top DICT with updated offsets
          updated_top_dict = update_top_dict_offsets(top_dict, offsets)
          top_dict_binary = serialize_top_dict(updated_top_dict)

          # Write Top DICT
          output.write(top_dict_binary)

          # 4. Write CharStrings
          output.write(charstrings) if charstrings

          # 5. Write Private DICT
          output.write(private_dict) if private_dict

          # 6. Write Variable Store (UNCHANGED)
          output.write(vstore) if vstore

          output.string
        end

        # Calculate offsets for CFF2 sections
        #
        # @param header_size [Integer] Header size
        # @param charstrings [String] CharStrings data
        # @param private_dict [String, nil] Private DICT data
        # @param vstore [String, nil] Variable Store data
        # @return [Hash] Section offsets
        def calculate_cff2_offsets(header_size:, charstrings:, private_dict:, vstore:)
          # Start after header
          offset = header_size

          # Top DICT offset (immediately after header)
          top_dict_offset = offset

          # Estimate Top DICT size (will be recalculated)
          # For now, use original Top DICT size from reader
          top_dict_size = estimate_top_dict_size

          offset += top_dict_size

          # CharStrings offset
          charstrings_offset = offset
          offset += charstrings&.size || 0

          # Private DICT offset
          private_dict_offset = offset
          private_dict_size = private_dict&.size || 0
          offset += private_dict_size

          # Variable Store offset
          vstore_offset = vstore ? offset : nil

          {
            top_dict: top_dict_offset,
            charstrings: charstrings_offset,
            private_dict: private_dict_offset,
            private_dict_size: private_dict_size,
            vstore: vstore_offset
          }
        end

        # Estimate Top DICT size
        #
        # @return [Integer] Estimated size
        def estimate_top_dict_size
          # Use original Top DICT size from reader as estimate
          # In CFF2, Top DICT size is in header
          top_dict_length = @reader.header[:top_dict_length]
          top_dict_length || 50 # Default estimate
        end

        # Update Top DICT with new offsets
        #
        # @param top_dict [Hash] Original Top DICT
        # @param offsets [Hash] Calculated offsets
        # @return [Hash] Updated Top DICT
        def update_top_dict_offsets(top_dict, offsets)
          updated = top_dict.dup

          # Update CharStrings offset (operator 17)
          updated[17] = offsets[:charstrings]

          # Update Private DICT [size, offset] (operator 18)
          if offsets[:private_dict_size]&.positive?
            updated[18] = [offsets[:private_dict_size], offsets[:private_dict]]
          end

          # Update Variable Store offset (operator 24)
          updated[24] = offsets[:vstore] if offsets[:vstore]

          updated
        end

        # Serialize Top DICT to binary
        #
        # @param dict [Hash] Top DICT hash with integer operator keys
        # @return [String] Binary DICT data
        def serialize_top_dict(dict)
          require_relative "../cff/dict_builder"

          # Convert integer operator keys to symbol keys for DictBuilder
          symbol_dict = convert_operators_to_symbols(dict)
          Cff::DictBuilder.build(symbol_dict)
        end

        # Serialize Private DICT to binary
        #
        # @param dict [Hash] Private DICT hash
        # @return [String] Binary DICT data
        def serialize_private_dict(dict)
          require_relative "../cff/dict_builder"

          # Convert integer operator keys to symbol keys for DictBuilder
          symbol_dict = convert_operators_to_symbols(dict)
          Cff::DictBuilder.build(symbol_dict)
        end

        # Convert integer operator keys to symbol keys
        #
        # @param dict [Hash] Dictionary with integer or string keys
        # @return [Hash] Dictionary with symbol keys
        def convert_operators_to_symbols(dict)
          # Operator mapping: integer => symbol
          operator_map = {
            0 => :version,
            1 => :notice,
            2 => :full_name,
            3 => :family_name,
            4 => :weight,
            5 => :font_bbox,
            6 => :blue_values,
            7 => :other_blues,
            8 => :family_blues,
            9 => :family_other_blues,
            10 => :std_hw,
            11 => :std_vw,
            15 => :charset,
            16 => :encoding,
            17 => :charstrings,
            18 => :private,
            19 => :subrs,
            20 => :default_width_x,
            21 => :nominal_width_x
          # Note: operator 24 (vstore) is CFF2-specific and handled separately
          }

          result = {}
          dict.each do |key, value|
            # Skip vstore (operator 24) - CFF2 specific, not in CFF DictBuilder
            next if key == 24 || key == :vstore

            # Convert string keys to symbols for DictBuilder
            if key.is_a?(String)
              symbol_key = key.to_sym
            elsif key.is_a?(Integer)
              symbol_key = operator_map[key] || key
            else
              symbol_key = key
            end

            result[symbol_key] = value
          end
          result
        end

        # Validate CFF2 structure
        #
        # @return [Array<String>] Validation errors (empty if valid)
        def validate
          errors = []

          errors << "Not a valid CFF2 table" unless @reader.header[:major_version] == 2

          if variable? && @num_axes.zero?
            errors << "CFF2 has Variable Store but no axes defined"
          end

          errors
        end
      end
    end
  end
end