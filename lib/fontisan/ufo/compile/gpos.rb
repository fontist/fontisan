# frozen_string_literal: true

require "stringio"

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `GPOS` (Glyph Positioning) table from UFO
      # kerning data. Emits a minimal but valid GPOS with:
      #
      #   - ScriptList: DFLT script, default language system
      #   - FeatureList: `kern` feature (feature tag "kern")
      #   - LookupList: one PairPos lookup (format 1, individual pairs)
      #
      # Each kerning pair from the UFO source becomes a PairPosRecord
      # with an x-advance adjustment on the first glyph.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/gpos
      module Gpos
        FEATURE_KERN = "kern"
        SCRIPT_DFLT = "DFLT"
        LANGSYS_DEFAULT = 0

        # ValueFormat flags (which fields are present in a ValueRecord)
        VALUE_X_PLACEMENT = 0x0001
        VALUE_Y_PLACEMENT = 0x0002
        VALUE_X_ADVANCE = 0x0004
        VALUE_Y_ADVANCE = 0x0008

        # @param font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] in gid order
        # @return [String, nil] GPOS table bytes, or nil if no kerning
        def self.build(font, glyphs:)
          pairs = collect_kerning_pairs(font, glyphs)
          return nil if pairs.empty?

          build_gpos_table(pairs)
        end

        # ---------- pair collection ----------

        # Collect kerning pairs from the UFO model. Each pair is
        # (gid1, gid2, x_advance_delta).
        # @return [Array<[Integer, Integer, Integer]>]
        def self.collect_kerning_pairs(font, glyphs)
          name_to_gid = {}
          glyphs.each_with_index { |g, gid| name_to_gid[g.name] = gid }

          pairs = []
          font.kerning.each_pair do |key, value|
            # UFO kerning key is "glyph1 glyph2" or a class name.
            # We only handle individual glyph pairs (not classes).
            names = key.split
            next unless names.size == 2

            gid1 = name_to_gid[names[0]]
            gid2 = name_to_gid[names[1]]
            next unless gid1 && gid2

            pairs << [gid1, gid2, value.to_i]
          end

          pairs.sort_by { |a| [a[0], a[1]] }
        end

        # ---------- GPOS binary assembly ----------

        def self.build_gpos_table(pairs)
          # Group pairs by first glyph (gid1)
          by_first = {}
          pairs.each do |gid1, gid2, delta|
            by_first[gid1] ||= []
            by_first[gid1] << [gid2, delta]
          end

          first_gids = by_first.keys.sort

          # --- Build subtables bottom-up ---

          # 1. PairSets (one per first glyph)
          pair_sets_data = {}
          pair_set_offsets = {}
          pair_sets_blob = +""

          first_gids.each do |gid1|
            pair_set_offsets[gid1] = pair_sets_blob.bytesize

            second_pairs = by_first[gid1].sort_by { |gid2, _| gid2 }
            data = [second_pairs.size].pack("n") # pairValueCount
            second_pairs.each do |gid2, delta|
              data << [gid2, delta, 0].pack("nnn") # secondGlyph + valRec1(xAdvance) + valRec2(0)
            end

            pair_sets_data[gid1] = data
            pair_sets_blob << data
          end

          # 2. Coverage table (Format 1: individual glyphs)
          coverage = build_coverage_format1(first_gids)

          # 3. PairPosFormat1 subtable
          value_format1 = VALUE_X_ADVANCE
          value_format2 = 0

          pairpos_header_size = 10 # format(2) + coverageOffset(2) + valueFormat1(2) + valueFormat2(2) + pairSetCount(2)
          pairset_array_size = first_gids.size * 2 # one uint16 offset per first glyph

          coverage_offset = pairpos_header_size + pairset_array_size
          pairset_base = coverage_offset + coverage.bytesize

          pairpos = +""
          pairpos << [1].pack("n") # posFormat = 1
          pairpos << [coverage_offset].pack("n") # coverageOffset
          pairpos << [value_format1].pack("n") # valueFormat1
          pairpos << [value_format2].pack("n") # valueFormat2
          pairpos << [first_gids.size].pack("n") # pairSetCount

          # PairSet offsets (relative to start of PairPos subtable)
          first_gids.each do |gid1|
            pairpos << [pairset_base + pair_set_offsets[gid1]].pack("n")
          end

          pairpos << coverage
          pairpos << pair_sets_blob

          # 4. Lookup table (type 2 = PairPos, flag 0)
          lookup_header = [
            2,   # lookupType = PairPos
            0,   # lookupFlag
            1,   # subTableCount
          ].pack("nnn")

          subtable_offset = lookup_header.bytesize + 2 # +2 for the offset array
          lookup = lookup_header + [subtable_offset].pack("n") + pairpos

          # 5. Assemble GPOS header + ScriptList + FeatureList + LookupList

          # ScriptList (minimal: DFLT script, default LangSys)
          script_list = build_script_list

          # FeatureList (minimal: kern feature)
          feature_list = build_feature_list

          # LookupList (minimal: one lookup)
          lookup_list_header = [1].pack("n") # lookupCount
          lookup_offset_in_list = lookup_list_header.bytesize + 2 # +2 for the offset
          lookup_list = lookup_list_header + [lookup_offset_in_list].pack("n") + lookup

          # GPOS header (version 1.0)
          header_size = 10 # version(4) + scriptListOffset(2) + featureListOffset(2) + lookupListOffset(2)
          script_list_offset = header_size
          feature_list_offset = script_list_offset + script_list.bytesize
          lookup_list_offset = feature_list_offset + feature_list.bytesize

          header = [
            0x00010000, # version 1.0
            script_list_offset,
            feature_list_offset,
            lookup_list_offset,
          ].pack("Nnnn")

          header + script_list + feature_list + lookup_list
        end

        # Coverage Format 1: list of individual glyph IDs.
        def self.build_coverage_format1(gids)
          [1, gids.size].pack("nn") + gids.pack("n*")
        end

        # ScriptList: DFLT script with a single default LangSys.
        # The LangSys references feature index 0 (kern).
        def self.build_script_list
          # ScriptList header: scriptCount(2)
          # ScriptRecord: scriptTag(4) + scriptOffset(2)
          # Script table: defaultLangSysOffset(2) + langSysCount(2) = 0
          # LangSys: lookupOrder(2)=0 + reqFeatureIndex(2)=0xFFFF + featureIndexCount(2)=1 + featureIndex(2)=0

          script_list_header_size = 2 + (4 + 2) # scriptCount + 1 ScriptRecord
          script_offset = script_list_header_size
          langsys_offset = script_offset + 4 # script table size (defaultLangSysOffset + langSysCount)

          script_list = +""
          script_list << [1].pack("n") # scriptCount
          script_list << SCRIPT_DFLT # scriptTag
          script_list << [script_offset].pack("n") # scriptOffset

          # Script table
          script_list << [langsys_offset - script_offset].pack("n") # defaultLangSysOffset (relative)
          script_list << [0].pack("n") # langSysCount

          # Default LangSys
          script_list << [0].pack("n") # lookupOrder (reserved)
          script_list << [0xFFFF].pack("n") # reqFeatureIndex (none)
          script_list << [1].pack("n") # featureIndexCount
          script_list << [0].pack("n") # featureIndex[0] = kern

          script_list
        end

        # FeatureList: one feature record (kern) referencing lookup 0.
        def self.build_feature_list
          # FeatureList header: featureCount(2)
          # FeatureRecord: featureTag(4) + featureOffset(2)
          # Feature table: featureParams(2)=0 + lookupIndexCount(2)=1 + lookupIndex(2)=0

          feature_list_header_size = 2 + (4 + 2) # featureCount + 1 FeatureRecord
          feature_offset = feature_list_header_size

          feature_list = +""
          feature_list << [1].pack("n") # featureCount
          feature_list << FEATURE_KERN # featureTag
          feature_list << [feature_offset].pack("n") # featureOffset

          # Feature table
          feature_list << [0].pack("n") # featureParams (null)
          feature_list << [1].pack("n") # lookupIndexCount
          feature_list << [0].pack("n") # lookupIndex[0]

          feature_list
        end

        private_class_method :build_gpos_table, :build_coverage_format1,
                             :build_script_list, :build_feature_list
      end
    end
  end
end
