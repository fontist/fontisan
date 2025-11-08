# frozen_string_literal: true

module Fontisan
  module Tables
    # Common structures shared between GSUB and GPOS tables
    module LayoutCommon
      # ScriptRecord structure
      class ScriptRecord < Binary::BaseRecord
        string :script_tag, length: 4
        uint16 :script_offset
      end

      # ScriptList table
      class ScriptList < Binary::BaseRecord
        uint16 :script_count
        array :script_records, type: ScriptRecord,
                               initial_length: -> { script_count }

        def script_tags
          script_records.map(&:script_tag)
        end
      end

      # LangSysRecord structure
      class LangSysRecord < Binary::BaseRecord
        string :lang_sys_tag, length: 4
        uint16 :lang_sys_offset
      end

      # Script table
      class Script < Binary::BaseRecord
        uint16 :default_lang_sys_offset
        uint16 :lang_sys_count
        array :lang_sys_records, type: LangSysRecord,
                                 initial_length: -> { lang_sys_count }
      end

      # LangSys table
      class LangSys < Binary::BaseRecord
        uint16 :lookup_order_offset # Reserved, set to NULL
        uint16 :required_feature_index
        uint16 :feature_index_count
        array :feature_indices, type: :uint16,
                                initial_length: -> { feature_index_count }
      end

      # FeatureRecord structure
      class FeatureRecord < Binary::BaseRecord
        string :feature_tag, length: 4
        uint16 :feature_offset
      end

      # FeatureList table
      class FeatureList < Binary::BaseRecord
        uint16 :feature_count
        array :feature_records, type: FeatureRecord,
                                initial_length: -> { feature_count }

        def feature_tags
          feature_records.map(&:feature_tag)
        end
      end

      # Feature table
      class Feature < Binary::BaseRecord
        uint16 :feature_params_offset # Reserved, set to NULL
        uint16 :lookup_index_count
        array :lookup_list_indices, type: :uint16,
                                    initial_length: -> { lookup_index_count }
      end
    end
  end
end
