# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `SVG ` table for SVG-in-OpenType color glyphs.
      #
      # Layout:
      #   Header (10 bytes):
      #     uint16 version (= 0)
      #     Offset32 documentListOffset (= 10, immediately after header)
      #     uint32 reserved (= 0)
      #
      #   Document List:
      #     uint16 numEntries
      #     DocumentRecord[numEntries]:
      #       uint16 startGlyphID
      #       uint16 endGlyphID
      #       Offset32 svgDocOffset (from start of SVG table)
      #       uint32 svgDocLength
      #
      #   SVG Documents (raw XML, optionally gzipped)
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/svg
      module SvgTable
        VERSION = 0
        HEADER_SIZE = 10
        DOCUMENT_RECORD_SIZE = 12

        # @param entries [Array<Hash>] each with :start_gid (Integer),
        #   :end_gid (Integer), :svg (String — raw SVG XML)
        # @return [String, nil] SVG table bytes, or nil if no entries
        def self.build(entries:)
          return nil if entries.nil? || entries.empty?

          num_entries = entries.size
          doc_list_size = 2 + (num_entries * DOCUMENT_RECORD_SIZE)
          doc_data_offset = HEADER_SIZE + doc_list_size

          header = [VERSION, HEADER_SIZE, 0].pack("nNN")

          records = +""
          docs = +""
          offset = doc_data_offset
          entries.each do |entry|
            svg_bytes = entry[:svg].b
            records << [entry[:start_gid], entry[:end_gid],
                        offset, svg_bytes.bytesize].pack("nnNN")
            docs << svg_bytes
            offset += svg_bytes.bytesize
          end

          doc_list = [num_entries].pack("n") + records

          header + doc_list + docs
        end
      end
    end
  end
end
