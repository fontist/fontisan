# frozen_string_literal: true

require_relative "../../binary/base_record"

module Fontisan
  module Tables
    class Cff
      # CFF Header structure
      #
      # The CFF header appears at the beginning of the CFF table and contains
      # basic version and structural information about the CFF data.
      #
      # Structure (4 bytes minimum):
      # - uint8: major version (always 1 for CFF, 2 for CFF2)
      # - uint8: minor version (always 0)
      # - uint8: hdr_size (header size in bytes, typically 4)
      # - uint8: off_size (offset size used throughout CFF, 1-4 bytes)
      #
      # Reference: CFF specification section 4 "Header"
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
      #
      # @example Reading a CFF header
      #   data = File.binread("font.otf", 4, cff_offset)
      #   header = Fontisan::Tables::Cff::Header.read(data)
      #   puts header.major  # => 1
      #   puts header.minor  # => 0
      #   puts header.off_size  # => 4
      class Header < Binary::BaseRecord
        # Major version number (1 for CFF, 2 for CFF2)
        uint8 :major

        # Minor version number (always 0)
        uint8 :minor

        # Header size in bytes (typically 4, but can be larger for extensions)
        uint8 :hdr_size

        # Offset size used throughout the CFF table
        # Valid values are 1, 2, 3, or 4 bytes
        #
        # This determines how offsets are encoded in INDEX structures and
        # other parts of the CFF table.
        uint8 :off_size

        # Check if this is a valid CFF version 1.0 header
        #
        # @return [Boolean] True if major version is 1 and minor is 0
        def cff?
          major == 1 && minor.zero?
        end

        # Check if this is a CFF2 header (variable CFF fonts)
        #
        # @return [Boolean] True if major version is 2
        def cff2?
          major == 2
        end

        # Get the version as a string
        #
        # @return [String] Version in "major.minor" format
        def version
          "#{major}.#{minor}"
        end

        # Validate that the header has correct values
        #
        # @return [Boolean] True if header is valid
        def valid?
          # Major version must be 1 or 2
          return false unless [1, 2].include?(major)

          # Minor version must be 0
          return false unless minor.zero?

          # Header size must be at least 4 bytes
          return false unless hdr_size >= 4

          # Offset size must be between 1 and 4
          return false unless (1..4).cover?(off_size)

          true
        end

        # Validate header and raise error if invalid
        #
        # @raise [Fontisan::CorruptedTableError] If header is invalid
        def validate!
          return if valid?

          message = "Invalid CFF header: " \
                    "version=#{version}, " \
                    "hdr_size=#{hdr_size}, " \
                    "off_size=#{off_size}"
          error = Fontisan::CorruptedTableError.new(message)
          error.set_backtrace(caller)
          Kernel.raise(error)
        end
      end
    end
  end
end
