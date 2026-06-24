# frozen_string_literal: true

require "stringio"

module Fontisan
  module Audit
    module Extractors
      # Hinting summary: TrueType bytecode counts + gasp policy + CFF stem
      # count, with derived `is_unhinted` and `hinting_format` fields.
      #
      # Returned fields:
      #   hinting: Models::Audit::Hinting instance, or nil for Type 1
      #
      # The fpgm/prep/cvt/gasp tables have no BinData classes yet — they
      # are read as raw bytes from `font.table_data`. Bytecode is one byte
      # per instruction; cvt is an array of FWord (int16), so the entry
      # count is bytesize / 2.
      class Hinting < Base
        # Raw CFF2 / CFF2 charstring operator bytes that declare stem hints.
        HSTEM    = 1
        VSTEM    = 3
        HSTEMHM  = 18
        VSTEMHM  = 23
        HINTMASK = 19
        CNTRMASK = 20

        def extract(context)
          font = context.font
          return { hinting: nil } unless sfnt?(font)

          { hinting: Models::Audit::Hinting.new(**gather(font)) }
        end

        protected

        def sfnt?(font)
          font.is_a?(SfntFont)
        end

        private

        def gather(font)
          tt = truetype_fields(font)
          cff = cff_fields(font)
          gasp = parse_gasp(font)

          derived = Models::Audit::Hinting.derive_flags(
            has_tt: tt[:has_fpgm] || tt[:has_prep] || tt[:has_cvt],
            has_cff: cff[:cff_has_private_dict],
            has_gasp: !gasp.empty?,
          )

          tt.merge(cff).merge(gasp_ranges: gasp).merge(derived)
        end

        def truetype_fields(font)
          {
            has_fpgm: font.has_table?(Constants::FPGM_TAG),
            fpgm_instruction_count: byte_count(font, Constants::FPGM_TAG),
            has_prep: font.has_table?(Constants::PREP_TAG),
            prep_instruction_count: byte_count(font, Constants::PREP_TAG),
            has_cvt: font.has_table?(Constants::CVT_TAG),
            cvt_entry_count: cvt_entry_count(font),
            has_cvar: font.has_table?(Constants::CVAR_TAG),
          }
        end

        def cff_fields(font)
          has_cff1 = font.has_table?(Constants::CFF_TAG)
          has_cff2 = font.has_table?(Constants::CFF2_TAG)
          has_private = has_cff1 || has_cff2

          {
            cff_has_private_dict: has_private,
            cff_hint_count: has_cff1 ? count_cff_stems(font) : nil,
          }
        end

        def byte_count(font, tag)
          return nil unless font.has_table?(tag)

          font.table_data[tag]&.bytesize
        end

        def cvt_entry_count(font)
          return nil unless font.has_table?(Constants::CVT_TAG)

          bytes = font.table_data[Constants::CVT_TAG]
          return nil unless bytes

          bytes.bytesize / 2
        end

        # Parse the gasp table from raw bytes. Format: uint16 version,
        # uint16 numRanges, then numRanges × (uint16 rangeMaxPPEM,
        # uint16 rangeFlags). Returns [] if gasp is absent or truncated.
        def parse_gasp(font)
          return [] unless font.has_table?(Constants::GASP_TAG)

          data = font.table_data[Constants::GASP_TAG]
          return [] unless data && data.bytesize >= 4

          _version, num_ranges = data.unpack("nn")
          ranges = []
          offset = 4
          num_ranges.times do
            break if offset + 4 > data.bytesize

            max_ppem, flags = data[offset, 4].unpack("nn")
            ranges << Models::Audit::GaspRange.from_flags(max_ppem, flags)
            offset += 4
          end
          ranges
        end

        def count_cff_stems(font)
          return nil unless font.has_table?(Constants::CFF_TAG)

          cff = font.table(Constants::CFF_TAG)
          return nil unless cff

          index = cff.charstrings_index(0)
          return nil unless index

          total = 0
          index.count.times do |glyph_index|
            data = index[glyph_index]
            next unless data

            total += count_stems_in_charstring(data)
          end
          total
        rescue CorruptedTableError
          nil
        end

        # Lightweight Type-2 CharString scanner that counts stem hints
        # without instantiating a full CharString (which needs a Private
        # DICT, global/local subrs, etc.). Operates purely on bytes.
        def count_stems_in_charstring(data)
          io = StringIO.new(data)
          stack = 0
          stems = 0

          until io.eof?
            byte = io.getbyte
            next if byte.nil?

            stack, stems = process_byte(io, byte, stack, stems)
          end

          stems
        end

        def process_byte(io, byte, stack, stems)
          if operator_byte?(byte)
            apply_operator(io, byte, stack, stems)
          else
            [consume_operand(io, byte, stack), stems]
          end
        end

        def operator_byte?(byte)
          byte <= 31 && byte != 28
        end

        def apply_operator(io, byte, stack, stems)
          case byte
          when 12
            io.getbyte
            [0, stems]
          when HSTEM, VSTEM, HSTEMHM, VSTEMHM
            [0, stems + stack / 2]
          when HINTMASK, CNTRMASK
            new_stems = stems + stack / 2
            io.read((new_stems + 7) / 8)
            [0, new_stems]
          else
            [0, stems]
          end
        end

        def consume_operand(io, byte, stack)
          case byte
          when 28
            io.read(2)
          when 255
            io.read(4)
          when 247..254
            io.getbyte
          end
          stack + 1
        end
      end
    end
  end
end
