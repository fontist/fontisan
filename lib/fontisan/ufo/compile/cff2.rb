# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType CFF2 table from UFO glyphs.
      #
      # CFF2 is simpler than CFF1: no Name INDEX, String INDEX, Encoding,
      # or Charset. The Top DICT references CharStrings and a Font DICT
      # INDEX (which wraps at least one Font DICT pointing to a Private
      # DICT).
      #
      # Layout (static font, single Font DICT, empty Private DICT):
      #
      #   Header (5 bytes)
      #   Top DICT (variable — offsets to CharStrings + Font DICT INDEX)
      #   Global Subr INDEX (4 bytes — empty)
      #   CharStrings INDEX (variable)
      #   Font DICT INDEX (variable — wraps one Font DICT)
      #     Font DICT: DICT with Private operator [0, 0] (empty Private)
      #
      # The Top DICT offsets depend on the Top DICT's own size — a
      # circular dependency resolved with fixed-point iteration (the
      # same pattern as the CFF1 builder).
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cff2
      module Cff2
        # CFF2 Top DICT operator encodings.
        CHARSTRINGS_OPERATOR = 17 # 0x11
        VARIATION_STORE_OPERATOR = 24 # 0x18
        FONT_DICT_INDEX_OPERATOR = [12, 36].freeze # 0x0C24
        PRIVATE_OPERATOR = 18 # 0x12

        # @param font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] in gid order
        # @param variation_store [String, nil] ItemVariationStore bytes
        #   for variable CFF2 fonts. When present, embedded between the
        #   GlobalSubr INDEX and CharStrings INDEX, and referenced from
        #   the Top DICT via operator 24.
        # @return [String] CFF2 table bytes
        def self.build(_font, glyphs:, variation_store: nil)
          charstrings = glyphs.map { |g| charstring_for(g) }
          global_subr_index = empty_global_subr_index
          font_dict = build_font_dict(private_size: 0, private_offset: 0)
          font_dict_index = Tables::Cff2::IndexBuilder.build([font_dict])
          vs_bytes = variation_store&.b

          # Fixed-point iteration: encode Top DICT, compute offsets, repeat.
          top_dict = encode_top_dict(
            charstrings_offset: 0, font_dict_index_offset: 0,
            variation_store_offset: vs_bytes ? 0 : nil
          )
          layout = compute_layout(top_dict:, charstrings:, global_subr_index:,
                                  font_dict_index:, variation_store: vs_bytes)

          10.times do
            top_dict = encode_top_dict(
              charstrings_offset: layout[:charstrings_offset],
              font_dict_index_offset: layout[:font_dict_index_offset],
              variation_store_offset: layout[:variation_store_offset],
            )
            next_layout = compute_layout(top_dict:, charstrings:, global_subr_index:,
                                         font_dict_index:, variation_store: vs_bytes)
            break if same_offsets?(layout, next_layout)

            layout = next_layout
          end

          assemble(layout:)
        end

        # ---------- charstring per-glyph ----------

        def self.charstring_for(glyph)
          return empty_charstring(glyph.width.to_i) if glyph.contours.empty?

          builder = Tables::Cff::CharStringBuilder.new
          builder.build(glyph.to_outline, width: glyph.width.to_i)
        rescue StandardError
          empty_charstring(glyph.width.to_i)
        end

        def self.empty_charstring(width)
          builder = Tables::Cff::CharStringBuilder.new
          builder.build_empty(width: width.zero? ? nil : width)
        end

        # ---------- DICT encoding ----------

        # Encode the Top DICT with offsets to CharStrings, Font DICT INDEX,
        # and optionally VariationStore.
        def self.encode_top_dict(charstrings_offset:, font_dict_index_offset:,
                                 variation_store_offset: nil)
          io = +""
          io << Tables::Cff2::DictEncoder.encode_entry(
            [charstrings_offset], CHARSTRINGS_OPERATOR
          )
          io << Tables::Cff2::DictEncoder.encode_entry(
            [font_dict_index_offset], FONT_DICT_INDEX_OPERATOR
          )
          if variation_store_offset
            io << Tables::Cff2::DictEncoder.encode_entry(
              [variation_store_offset], VARIATION_STORE_OPERATOR
            )
          end
          io
        end

        # Encode a Font DICT: just the Private operator [size, offset].
        def self.build_font_dict(private_size:, private_offset:)
          Tables::Cff2::DictEncoder.encode_entry(
            [private_size, private_offset], PRIVATE_OPERATOR
          )
        end

        # ---------- layout ----------

        # Compute byte offsets for each section. The Top DICT's size
        # determines where the Global Subr INDEX starts, which cascades
        # to all subsequent offsets. When a VariationStore is present,
        # it sits between the GlobalSubr INDEX and the CharStrings INDEX.
        def self.compute_layout(top_dict:, charstrings:, global_subr_index:,
                                font_dict_index:, variation_store: nil)
          charstrings_index = Tables::Cff2::IndexBuilder.build(charstrings)

          header_size = Tables::Cff2::Header::HEADER_SIZE
          global_subr_offset = header_size + top_dict.bytesize
          post_global_subr = global_subr_offset + global_subr_index.bytesize

          if variation_store
            variation_store_offset = post_global_subr
            charstrings_offset = variation_store_offset + variation_store.bytesize
          else
            variation_store_offset = nil
            charstrings_offset = post_global_subr
          end
          font_dict_index_offset = charstrings_offset + charstrings_index.bytesize

          {
            top_dict: top_dict,
            charstrings_index: charstrings_index,
            global_subr_index: global_subr_index,
            font_dict_index: font_dict_index,
            variation_store: variation_store,
            variation_store_offset: variation_store_offset,
            charstrings_offset: charstrings_offset,
            font_dict_index_offset: font_dict_index_offset,
          }
        end

        def self.same_offsets?(a, b)
          a[:charstrings_offset] == b[:charstrings_offset] &&
            a[:font_dict_index_offset] == b[:font_dict_index_offset] &&
            a[:variation_store_offset] == b[:variation_store_offset]
        end

        def self.empty_global_subr_index
          Tables::Cff2::IndexBuilder.build([])
        end

        # ---------- assembly ----------

        def self.assemble(layout:)
          io = +""
          io << Tables::Cff2::Header.build(top_dict_size: layout[:top_dict].bytesize)
          io << layout[:top_dict]
          io << layout[:global_subr_index]
          io << layout[:variation_store] if layout[:variation_store]
          io << layout[:charstrings_index]
          io << layout[:font_dict_index]
          io
        end

        private_class_method :charstring_for, :empty_charstring,
                             :encode_top_dict, :build_font_dict,
                             :compute_layout, :same_offsets?,
                             :empty_global_subr_index, :assemble
      end
    end
  end
end
