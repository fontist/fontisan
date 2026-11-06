# frozen_string_literal: true

module Fontisan
  # Bounds check of a plain sfnt (TrueType or OpenType) table directory, run
  # before a conversion reads it.
  #
  # fontisan-rs rejects a directory that runs past the end of the file, or a
  # table that does, with "invalid sfnt table directory". Without this check
  # the Ruby tier fails the same files with whatever BinData or the converters
  # raise: "End of file reached" for a truncated directory, and an internal
  # NoMethodError text for a bad table offset. This gives every tier one error
  # for the same input (fontist/fontisan#159).
  module SfntDirectory
    # Raised for a malformed directory; the converter adds its own prefix.
    class Malformed < Error; end

    MESSAGE = "Transformation failed: invalid sfnt table directory"
    HEADER_SIZE = 12
    ENTRY_SIZE = 16

    module_function

    # @param data [String] the whole file, binary
    # @raise [Malformed] when the directory or a table is out of range
    # @return [void]
    def check!(data)
      size = data.bytesize
      malformed! if size < HEADER_SIZE
      num_tables = data.byteslice(4, 2).unpack1("n")
      malformed! if HEADER_SIZE + (num_tables * ENTRY_SIZE) > size
      num_tables.times do |index|
        offset, length = data.byteslice(HEADER_SIZE + (index * ENTRY_SIZE) + 8, 8).unpack("NN")
        malformed! if offset + length > size
      end
    end

    def malformed!
      raise Malformed, MESSAGE
    end
  end
end
