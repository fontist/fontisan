# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff
      # Recalculates CFF table offsets after structure modifications
      #
      # When the Private DICT size changes (e.g., adding hint parameters),
      # all offsets in the CFF table must be recalculated. This class
      # computes new offsets based on section sizes.
      #
      # CFF Structure (sequential layout):
      # - Header (fixed size)
      # - Name INDEX
      # - Top DICT INDEX (contains offsets to CharStrings and Private DICT)
      # - String INDEX
      # - Global Subr INDEX
      # - CharStrings INDEX
      # - Private DICT (variable size)
      # - Local Subr INDEX (optional, within Private DICT)
      #
      # Key offsets to recalculate:
      # - charstrings: Offset from CFF start to CharStrings INDEX
      # - private: [size, offset] in Top DICT pointing to Private DICT
      class OffsetRecalculator
        # Calculate offsets for all CFF sections
        #
        # @param sections [Hash] Hash of section_name => binary_data
        # @return [Hash] Hash of offset information
        def self.calculate_offsets(sections)
          offsets = {}
          pos = 0

          # Track position through CFF structure
          pos += sections[:header].bytesize
          pos += sections[:name_index].bytesize

          # Top DICT INDEX starts here
          offsets[:top_dict_start] = pos
          pos += sections[:top_dict_index].bytesize

          pos += sections[:string_index].bytesize
          pos += sections[:global_subr_index].bytesize

          # CharStrings INDEX offset (referenced in Top DICT)
          offsets[:charstrings] = pos
          pos += sections[:charstrings_index].bytesize

          # Private DICT offset and size (referenced in Top DICT)
          offsets[:private] = pos
          offsets[:private_size] = sections[:private_dict].bytesize

          offsets
        end

        # Update Top DICT with new offsets
        #
        # @param top_dict [Hash] Top DICT data
        # @param offsets [Hash] Calculated offsets
        # @return [Hash] Updated Top DICT
        def self.update_top_dict(top_dict, offsets)
          updated = top_dict.dup
          updated[:charstrings] = offsets[:charstrings]
          updated[:private] = [offsets[:private_size], offsets[:private]]
          updated
        end
      end
    end
  end
end
