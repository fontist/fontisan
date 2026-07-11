# frozen_string_literal: true

require "stringio"

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `GSUB` (Glyph Substitution) table from
      # ligature substitution rules extracted from features.fea via
      # {FeatureCompiler}.
      #
      # Emits a minimal but valid GSUB with:
      #
      #   - ScriptList: DFLT script, default language system
      #   - FeatureList: one feature record per ligature feature tag
      #     (e.g. "liga", "dlig", "clig")
      #   - LookupList: one LigatureSubst lookup per feature tag
      #
      # Each `sub A B C by ABC;` rule becomes a LigatureSet on the
      # first glyph (A), with a Ligature record pointing at ABC and
      # component count 2 (B, C).
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/gsub
      module Gsub
        SCRIPT_DFLT = "DFLT"
        LANGSYS_DEFAULT = 0

        # Build GSUB table bytes from parsed feature rules.
        #
        # @param parsed [FeatureCompiler::ParsedFeatures]
        # @param name_to_gid [Hash{String=>Integer}]
        # @return [String, nil] GSUB bytes, or nil if no ligature rules
        def self.build(parsed:, name_to_gid:)
          features = ligature_features(parsed, name_to_gid)
          return nil if features.empty?

          lookups = features.values
          build_gsub_table(features.keys, lookups)
        end

        # Resolve ligature rules to per-feature lookup data.
        #
        # @param parsed [FeatureCompiler::ParsedFeatures]
        # @param name_to_gid [Hash{String=>Integer}]
        # @return [Hash{String=>Array}] feature_tag → lookup data
        def self.ligature_features(parsed, name_to_gid)
          parsed.ligatures.keys.each_with_object({}) do |tag, h|
            rules = parsed.ligatures_for(tag)
            sets = build_ligature_sets(rules, name_to_gid)
            h[tag] = sets unless sets.empty?
          end
        end

        # Build ligature sets keyed by the first glyph in each sequence.
        #
        # @param rules [Array<Hash>] {sequence:, result:}
        # @param name_to_gid [Hash]
        # @return [Hash{Integer=>Array}] gid → [{result_gid, components: [gids]}]
        def self.build_ligature_sets(rules, name_to_gid)
          sets = Hash.new { |h, k| h[k] = [] }
          rules.each do |rule|
            seq_gids = rule[:sequence].map { |n| name_to_gid[n] }
            result_gid = name_to_gid[rule[:result]]
            next unless seq_gids.all? && result_gid

            first = seq_gids.first
            components = seq_gids[1..]
            sets[first] << { result_gid: result_gid, components: components }
          end
          sets
        end

        # ---------- GSUB binary assembly ----------

        # Build the complete GSUB table.
        #
        # @param tags [Array<String>] feature tags in lookup order
        # @param lookups [Array<Hash>] one lookup per tag
        # @return [String]
        def self.build_gsub_table(tags, lookups)
          io = StringIO.new(+"")
          # Header: version (uint32 0x00010000), scriptListOffset,
          # featureListOffset, lookupListOffset (each uint16)
          header_size = 2 + 2 + 2 + 4 # version(4) + 3×uint16

          # Serialize each list independently, then compute offsets.
          script_list = build_script_list(tags.size)
          feature_list = build_feature_list(tags)
          lookup_list = build_lookup_list(lookups)

          script_list_offset = header_size
          feature_list_offset = script_list_offset + script_list.bytesize
          lookup_list_offset = feature_list_offset + feature_list.bytesize

          io << [0x00010000].pack("N")
          io << [script_list_offset].pack("n")
          io << [feature_list_offset].pack("n")
          io << [lookup_list_offset].pack("n")
          io << script_list
          io << feature_list
          io << lookup_list
          io.string
        end

        # ScriptList: one script (DFLT) with a default LangSys that
        # references all features (featureIndex 0..count-1).
        def self.build_script_list(feature_count)
          io = +""
          io << [1].pack("n") # scriptCount = 1

          # ScriptRecord: tag(4) + scriptOffset(2)
          # Script table starts right after the ScriptList header:
          #   scriptCount(2) + ScriptRecord(6) = 8
          script_offset = 8
          io << SCRIPT_DFLT
          io << [script_offset].pack("n")

          # Script table: defaultLangSysOffset(2) + langSysCount(2) = 4
          # LangSys follows immediately
          default_langsys_offset = script_offset + 4
          io << [default_langsys_offset].pack("n")
          io << [0].pack("n") # langSysCount

          # LangSys: lookupOrder(2)=0, requiredFeatureIndex(2)=0xFFFF,
          # featureIndexCount(2), featureIndices[]
          io << [0].pack("n")
          io << [0xFFFF].pack("n")
          io << [feature_count].pack("n")
          feature_count.times { |i| io << [i].pack("n") }

          io
        end

        # FeatureList: one FeatureRecord per tag. Each points to a
        # Feature table with one lookup index (the lookup for that tag).
        def self.build_feature_list(tags)
          io = +""
          io << [tags.size].pack("n") # featureCount

          # FeatureRecords: tag(4) + featureOffset(2)
          records_size = tags.size * 6
          header_size = 2 + records_size

          feature_records = +""
          feature_tables = +""
          tags.each_with_index do |tag, idx|
            feature_records << tag.ljust(4, " ")[0, 4]
            feature_records << [header_size + (idx * 4)].pack("n")

            feature_tables << [0].pack("n") # featureParams (null)
            feature_tables << [1].pack("n") # lookupIndexCount
            feature_tables << [idx].pack("n") # lookupIndex (1:1 feature→lookup)
          end

          io << feature_records
          io << feature_tables
          io
        end

        # LookupList: one lookup per feature tag. Each lookup is a
        # LigatureSubst (type 4) lookup.
        def self.build_lookup_list(lookups)
          io = +""
          count = lookups.size
          io << [count].pack("n") # lookupCount

          # Serialize each lookup first, then compute offsets relative
          # to the start of the LookupList.
          serialized = lookups.map { |sets| build_ligature_lookup(sets) }
          offset_table_size = 2 + (count * 2)
          pos = offset_table_size
          offsets = serialized.map do |s|
            o = pos
            pos += s.bytesize
            o
          end

          offsets.each { |o| io << [o].pack("n") }
          serialized.each { |s| io << s }

          io
        end

        # Build a single LigatureSubst lookup (type 4, format 1).
        def self.build_ligature_lookup(sets)
          io = +""
          # Lookup table: lookupType(2)=4, lookupFlag(2)=0, subTableCount(2)=1
          io << [4].pack("n")
          io << [0].pack("n")
          io << [1].pack("n")

          # Subtable offset (relative to start of Lookup table)
          lookup_header_size = 6
          io << [lookup_header_size].pack("n")

          # LigatureSubstFormat1: format(2)=1, coverageOffset(2),
          # ligatureSetCount(2), ligatureSetOffsets[]
          first_glyphs = sets.keys.sort
          set_count = first_glyphs.size
          subst_header_size = 2 + 2 + 2 + (set_count * 2)

          # Serialize each LigatureSet to compute offsets
          serialized_sets = first_glyphs.map { |gid| sets[gid] }.map { |s| build_ligature_set(s) }
          coverage = build_coverage(first_glyphs)

          pos = subst_header_size
          set_offsets = serialized_sets.map do |s|
            o = pos
            pos += s.bytesize
            o
          end
          coverage_offset = pos

          io << [1].pack("n") # substFormat = 1
          io << [coverage_offset].pack("n")
          io << [set_count].pack("n")
          set_offsets.each { |o| io << [o].pack("n") }
          serialized_sets.each { |s| io << s }
          io << coverage

          io
        end

        # Build a LigatureSet for one first glyph.
        # @param ligatures [Array<Hash>] {result_gid:, components:}
        def self.build_ligature_set(ligatures)
          io = +""
          count = ligatures.size
          io << [count].pack("n")

          # Serialize each Ligature record
          serialized = ligatures.map { |lig| build_ligature(lig) }
          pos = 2 + (count * 2)
          offsets = serialized.map do |s|
            o = pos
            pos += s.bytesize
            o
          end

          offsets.each { |o| io << [o].pack("n") }
          serialized.each { |s| io << s }
          io
        end

        # Build a single Ligature record.
        # @param lig [Hash] {result_gid:, components: [gids]}
        def self.build_ligature(lig)
          io = +""
          io << [lig[:result_gid]].pack("n")
          io << [lig[:components].size + 1].pack("n") # componentCount includes first
          lig[:components].each { |gid| io << [gid].pack("n") }
          io
        end

        # Build a Coverage table (format 1 = glyph list).
        # @param glyphs [Array<Integer>] sorted glyph IDs
        def self.build_coverage(glyphs)
          io = +""
          io << [1].pack("n") # coverageFormat = 1
          io << [glyphs.size].pack("n")
          glyphs.each { |gid| io << [gid].pack("n") }
          io
        end
      end
    end
  end
end
