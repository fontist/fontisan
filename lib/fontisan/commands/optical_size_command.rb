# frozen_string_literal: true

require_relative "base_command"
require_relative "../models/optical_size_info"

module Fontisan
  module Commands
    # Command to extract optical size information from fonts
    #
    # Optical size information indicates the design size range for which a font
    # is optimized. This information can come from:
    # - OS/2 table version 5+ (usLowerOpticalPointSize, usUpperOpticalPointSize)
    # - GPOS 'size' feature (not yet implemented)
    class OpticalSizeCommand < BaseCommand
      # Execute the optical size extraction command
      #
      # @return [Models::OpticalSizeInfo] Optical size information
      def run
        result = Models::OpticalSizeInfo.new

        # Try OS/2 table first
        if font.has_table?(Constants::OS2_TAG)
          os2_table = font.table(Constants::OS2_TAG)

          if os2_table.has_optical_point_size?
            result.has_optical_size = true
            result.source = "os2"
            result.lower_point_size = os2_table.lower_optical_point_size
            result.upper_point_size = os2_table.upper_optical_point_size
            return result
          end
        end

        # No optical size information
        result.has_optical_size = false
        result.source = "none"
        result
      end
    end
  end
end
