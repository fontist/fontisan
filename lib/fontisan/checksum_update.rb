# frozen_string_literal: true

require_relative "utilities/checksum_calculator"

module Fontisan
  # Shared module for updating checksum adjustment in font files
  #
  # This module provides methods to update the checksumAdjustment field in the
  # head table of SFNT fonts (TTF, OTF, WOFF). It supports both file-based
  # and IO-based operations to avoid Windows file locking issues.
  #
  # @api private
  module ChecksumUpdate
    # Update checksumAdjustment field in head table using an open IO object
    #
    # This method updates the checksumAdjustment field in the head table by:
    # 1. Rewinding to the beginning of the file
    # 2. Calculating the file checksum
    # 3. Computing the adjustment value
    # 4. Writing it to offset 8 within the head table
    #
    # @param io [IO] Open IO object positioned appropriately (will be rewound)
    # @param head_offset [Integer] Offset to the head table in the file
    # @return [void]
    #
    # @example Update checksum while file is open
    #   File.open("font.ttf", "r+b") do |io|
    #     update_checksum_adjustment_in_io(io, head_offset)
    #   end
    def update_checksum_adjustment_in_io(io, head_offset)
      # Rewind to calculate checksum from the beginning
      io.rewind

      # Calculate checksum directly from IO
      checksum = Utilities::ChecksumCalculator.calculate_checksum_from_io(io)

      # Calculate adjustment
      adjustment = Utilities::ChecksumCalculator.calculate_adjustment(checksum)

      # Write adjustment to head table (offset 8 within head table)
      io.seek(head_offset + 8)
      io.write([adjustment].pack("N"))
    end

    # Update checksumAdjustment field in head table
    #
    # This is a convenience method that opens the file and delegates to
    # update_checksum_adjustment_in_io. For better Windows compatibility
    # when using Tempfiles, use update_checksum_adjustment_in_io directly
    # while the file handle is still open.
    #
    # @param path [String] Path to the font file
    # @param head_offset [Integer] Offset to the head table in the file
    # @return [void]
    #
    # @example Update checksum in file
    #   update_checksum_adjustment_in_file("font.ttf", head_offset)
    def update_checksum_adjustment_in_file(path, head_offset)
      File.open(path, "r+b") do |io|
        update_checksum_adjustment_in_io(io, head_offset)
      end
    end
  end
end
