# frozen_string_literal: true

module Fontisan
  module Tables
    # GPOS (Glyph Positioning) table parser
    # Parses OpenType GPOS table to extract scripts and features
    class Gpos < Binary::BaseRecord
      uint16 :major_version
      uint16 :minor_version
      uint16 :script_list_offset
      uint16 :feature_list_offset
      uint16 :lookup_list_offset
      rest :table_data

      # Get all script tags supported by this font
      # @return [Array<String>] Array of 4-character script tags
      def scripts
        return [] if script_list_offset.zero?

        script_list_data = table_data[(script_list_offset - 10)..]
        return [] if script_list_data.nil? || script_list_data.empty?

        script_list = LayoutCommon::ScriptList.read(script_list_data)
        script_list.script_tags
      rescue StandardError
        []
      end

      # Get all feature tags for a given script
      # @param script_tag [String] 4-character script tag (e.g., 'latn')
      # @return [Array<String>] Array of 4-character feature tags
      def features(script_tag: "latn")
        return [] if script_list_offset.zero? || feature_list_offset.zero?

        # Get feature indices from the script's LangSys
        feature_indices = feature_indices_for_script(script_tag)
        return [] if feature_indices.empty?

        # Get feature list
        feature_list_data = table_data[(feature_list_offset - 10)..]
        return [] if feature_list_data.nil? || feature_list_data.empty?

        feature_list = LayoutCommon::FeatureList.read(feature_list_data)

        # Collect features referenced by the script
        features = []
        feature_indices.each do |idx|
          next if idx >= feature_list.feature_count

          features << feature_list.feature_records[idx].feature_tag
        end

        features.uniq
      rescue StandardError
        []
      end

      # Read direct PairPos (lookup type 2) value1.xAdvance in font units.
      # The returned Enumerable supports pairs[[left_glyph_id, right_glyph_id]];
      # unmatched pairs return zero. Use glyph_count: font.table("maxp").num_glyphs.to_i
      # to enumerate class-based pairs, including implicit class zero, with to_h.
      # Selects the script's default language system, with no script fallback.
      # First matching subtables take precedence; distinct lookups are summed.
      # This reads raw pair data: extension/contextual lookups, lookup-flag glyph
      # filtering, device corrections and variations require a shaping engine.
      # @return [Enumerable] nonzero glyph-ID pairs and signed advances
      # @raise [ParseError] malformed selected positioning data
      def kern_pairs(script_tag: "latn", feature_tag: "kern", glyph_count: nil)
        KerningPairs.new(self, script_tag: script_tag, feature_tag: feature_tag,
                               glyph_count: glyph_count)
      end

      private

      # Get feature indices for a given script
      # @param script_tag [String] 4-character script tag
      # @return [Array<Integer>] Array of feature indices
      def feature_indices_for_script(script_tag)
        return [] if script_list_offset.zero?

        script_list_data = table_data[(script_list_offset - 10)..]
        return [] if script_list_data.nil? || script_list_data.empty?

        script_list = LayoutCommon::ScriptList.read(script_list_data)

        # Find the script record
        script_record = script_list.script_records.find do |rec|
          rec.script_tag == script_tag
        end
        return [] unless script_record

        # Parse the script table at the offset
        script_offset = script_record.script_offset
        script_data = script_list_data[script_offset..]
        return [] if script_data.nil? || script_data.empty?

        script = LayoutCommon::Script.read(script_data)

        # Get the default LangSys if it exists
        feature_indices = []
        if script.default_lang_sys_offset != 0
          lang_sys_data = script_data[script.default_lang_sys_offset..]
          if lang_sys_data && !lang_sys_data.empty?
            lang_sys = LayoutCommon::LangSys.read(lang_sys_data)
            feature_indices.concat(lang_sys.feature_indices)
          end
        end

        # Also collect from all LangSys records
        script.lang_sys_records.each do |lang_sys_rec|
          lang_sys_data = script_data[lang_sys_rec.lang_sys_offset..]
          next if lang_sys_data.nil? || lang_sys_data.empty?

          lang_sys = LayoutCommon::LangSys.read(lang_sys_data)
          feature_indices.concat(lang_sys.feature_indices)
        end

        feature_indices.uniq
      rescue StandardError
        []
      end
    end
  end
end

require "fontisan/tables/gpos/kerning_pairs"
