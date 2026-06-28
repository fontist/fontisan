# frozen_string_literal: true

require "fontisan/font_builder/tables/head"

module Fontisan
  module FontBuilder
    module Tables
      # Orchestrates per-table serialization. Each table class responds
      # to +#bytes(model)+; the Assembler writes them in canonical
      # order with proper offset + checksum bookkeeping.
      class Assembler
        SFNT_VERSION_TRUETYPE = 0x00010000

        TABLE_ORDER = {
          "head" => Tables::Head,
          # TODO.full/14 adds: hhea, maxp, os2, hmtx, cmap, post, loca, glyf, name
        }.freeze

        attr_reader :model, :format

        def initialize(model, format: :ttf)
          @model = model
          @format = format
        end

        def write(path)
          pathname = Pathname(path)
          pathname.dirname.mkpath

          blobs = TABLE_ORDER.transform_values { |klass| klass.new(model).bytes }

          File.open(pathname, "wb") do |io|
            write_offset_table(io, blobs)
            write_table_directory(io, blobs)
            blobs.each_value { |blob| io.write(blob) }
          end

          pathname
        end

        private

        def write_offset_table(io, blobs)
          num_tables = blobs.length
          search_range = largest_power_of_2_le(num_tables) * 16
          entry_selector = Math.log2(search_range / 16).to_i
          range_shift = num_tables * 16 - search_range

          io.write([SFNT_VERSION_TRUETYPE, num_tables, search_range,
                    entry_selector, range_shift].pack("Nnnnn"))
        end

        def write_table_directory(io, blobs)
          offset = 12 + 16 * blobs.length
          blobs.sort_by { |tag, _blob| tag }.each do |tag, blob|
            checksum = compute_checksum(blob)
            length = blob.bytesize
            io.write(tag.ljust(4)[0, 4])
            io.write([checksum, offset, length].pack("NNN"))
            offset += pad4(blob.bytesize)
          end
        end

        def compute_checksum(blob)
          padded = blob + ("\0" * ((4 - blob.bytesize % 4) % 4))
          sums = padded.unpack("N*")
          sums.sum & 0xFFFFFFFF
        end

        def pad4(size)
          size + ((4 - size % 4) % 4)
        end

        def largest_power_of_2_le(n)
          return 0 if n <= 0

          power = 1
          power *= 2 while power * 2 <= n
          power
        end
      end
    end
  end
end
