# frozen_string_literal: true

require_relative "private_dict_writer"
require_relative "offset_recalculator"
require_relative "index_builder"
require_relative "dict_builder"
require_relative "charstring_rebuilder"
require_relative "hint_operation_injector"
require "stringio"

module Fontisan
  module Tables
    class Cff
      # Rebuilds CFF table with modifications
      #
      # This builder extracts sections from a source CFF table, applies
      # modifications (e.g., hint parameters to Private DICT), recalculates
      # offsets, and assembles a new CFF table.
      #
      # Process:
      # 1. Extract all CFF sections (header, indexes, dicts)
      # 2. Apply modifications to Private DICT
      # 3. Recalculate offsets (charstrings, private)
      # 4. Rebuild Top DICT INDEX with new offsets
      # 5. Reassemble all sections into new CFF table
      #
      # @example Rebuild with hints
      #   new_cff = TableBuilder.rebuild(source_cff, {
      #     private_dict_hints: { blue_values: [-15, 0], std_hw: 70 }
      #   })
      class TableBuilder
        # Rebuild CFF table with modifications
        #
        # @param source_cff [Cff] Source CFF table
        # @param modifications [Hash] Modifications to apply
        # @return [String] Binary CFF table data
        def self.rebuild(source_cff, modifications = {})
          new(source_cff).tap do |builder|
            builder.apply_modifications(modifications)
          end.serialize
        end

        # Initialize with source CFF
        #
        # @param source_cff [Cff] Source CFF table
        def initialize(source_cff)
          @source = source_cff
          @sections = extract_sections
        end

        # Apply modifications to CFF structure
        #
        # @param mods [Hash] Modifications hash
        def apply_modifications(mods)
          update_private_dict(mods[:private_dict_hints]) if mods[:private_dict_hints]
          update_charstrings(mods[:per_glyph_hints]) if mods[:per_glyph_hints]
        end

        # Serialize to binary CFF table
        #
        # @return [String] Binary CFF data
        def serialize
          # Calculate initial offsets
          offsets = OffsetRecalculator.calculate_offsets(@sections)
          top_dict = extract_top_dict_data
          updated = OffsetRecalculator.update_top_dict(top_dict, offsets)
          rebuild_top_dict_index(updated)

          # Recalculate after Top DICT rebuild (size may change)
          offsets = OffsetRecalculator.calculate_offsets(@sections)
          updated = OffsetRecalculator.update_top_dict(top_dict, offsets)
          rebuild_top_dict_index(updated)

          assemble
        end

        private

        # Extract all CFF sections from source
        #
        # @return [Hash] Hash of section_name => binary_data
        def extract_sections
          {
            header: extract_header,
            name_index: extract_index(@source.name_index),
            top_dict_index: extract_index(@source.top_dict_index),
            string_index: extract_index(@source.string_index),
            global_subr_index: extract_index(@source.global_subr_index),
            charstrings_index: extract_index(@source.charstrings_index(0)),
            private_dict: extract_private_dict,
          }
        end

        # Extract header bytes
        #
        # @return [String] Binary header data
        def extract_header
          @source.raw_data[0, @source.header.hdr_size]
        end

        # Extract INDEX as binary data
        #
        # @param index [Index] INDEX object
        # @return [String] Binary INDEX data
        def extract_index(index)
          return [0].pack("n") if index.nil? || index.count.zero?

          start = index.instance_variable_get(:@start_offset)
          io = StringIO.new(@source.raw_data)
          io.seek(start)

          count = io.read(2).unpack1("n")
          return [0].pack("n") if count.zero?

          off_size = io.read(1).unpack1("C")
          offset_array_size = (count + 1) * off_size

          # Read last offset to determine data size
          io.seek(start + 3 + count * off_size)
          last_offset = read_offset(io, off_size)
          data_size = last_offset - 1

          # Read entire INDEX
          io.seek(start)
          io.read(3 + offset_array_size + data_size)
        end

        # Extract Private DICT bytes
        #
        # @return [String] Binary Private DICT data
        def extract_private_dict
          priv_info = @source.top_dict(0).private
          return "".b unless priv_info

          size, offset = priv_info
          @source.raw_data[offset, size]
        end

        # Update Private DICT with hints
        #
        # @param hints [Hash] Hint parameters
        def update_private_dict(hints)
          source_priv = @source.private_dict(0)
          writer = PrivateDictWriter.new(source_priv)
          writer.update_hints(hints)
          @sections[:private_dict] = writer.serialize
        end

        # Update CharStrings with per-glyph hints
        #
        # @param per_glyph_hints [Hash] Hash of glyph_id => Array<Hint>
        def update_charstrings(per_glyph_hints)
          return if per_glyph_hints.nil? || per_glyph_hints.empty?

          # Create CharStringRebuilder
          charstrings_index = @source.charstrings_index(0)
          rebuilder = CharStringRebuilder.new(charstrings_index)

          # Inject hints for each glyph
          per_glyph_hints.each do |glyph_id, hints|
            injector = HintOperationInjector.new

            rebuilder.modify_charstring(glyph_id) do |operations|
              # Inject hint operations
              injector.inject(hints, operations)
            end
          end

          # Rebuild CharStrings INDEX
          @sections[:charstrings_index] = rebuilder.rebuild
        end

        # Extract Top DICT data as hash
        #
        # @return [Hash] Top DICT parameters
        def extract_top_dict_data
          @source.top_dict(0).to_h
        end

        # Rebuild Top DICT INDEX with updated data
        #
        # @param data [Hash] Top DICT parameters
        def rebuild_top_dict_index(data)
          dict_bytes = DictBuilder.build(data)
          @sections[:top_dict_index] = IndexBuilder.build([dict_bytes])
        end

        # Assemble all sections into CFF table
        #
        # @return [String] Binary CFF table
        def assemble
          output = StringIO.new("".b)
          output.write(@sections[:header])
          output.write(@sections[:name_index])
          output.write(@sections[:top_dict_index])
          output.write(@sections[:string_index])
          output.write(@sections[:global_subr_index])
          output.write(@sections[:charstrings_index])
          output.write(@sections[:private_dict])
          output.string
        end

        # Read offset of specified size
        #
        # @param io [IO] IO object
        # @param size [Integer] Offset size (1-4 bytes)
        # @return [Integer] Offset value
        def read_offset(io, size)
          case size
          when 1 then io.read(1).unpack1("C")
          when 2 then io.read(2).unpack1("n")
          when 3
            bytes = io.read(3).unpack("C*")
            (bytes[0] << 16) | (bytes[1] << 8) | bytes[2]
          when 4 then io.read(4).unpack1("N")
          end
        end
      end
    end
  end
end
