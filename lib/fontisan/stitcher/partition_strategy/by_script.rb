# frozen_string_literal: true

module Fontisan
  class Stitcher
    module PartitionStrategy
      # Partition codepoints by Unicode script property.
      #
      # Each non-empty script becomes one or more partitions. Scripts
      # that overflow +cap+ are chunked (Han has 80k+ codepoints) —
      # chunks are named +:script_<name>_a+, +:script_<name>_b+, etc.,
      # matching ByPlane's sub-split convention.
      #
      # Codepoints whose script is unknown (unassigned blocks) fall
      # into +:script_other+. Codepoints in the +Common+ script
      # (digits, punctuation shared across scripts) and +Inherited+
      # script (combining marks) get their own buckets — they're
      # typically useful as standalone subfonts.
      #
      # The script data is derived from {ByBlock::BLOCKS}: each Unicode
      # block maps to exactly one primary script (with a few exceptions
      # that we resolve explicitly). This keeps the data DRY — the
      # authoritative block list lives in one place.
      class ByScript < Base
        # Maps each Unicode block label to its primary script.
        # Block labels match ByBlock::BLOCKS keys.
        #
        # Special scripts:
        #   - +:common+ — shared across scripts (digits, punctuation)
        #   - +:inherited+ — combining marks that inherit the base char's script
        #   - +:other+ — fallback for unlisted blocks
        SCRIPT_OF_BLOCK = {
          # Latin family
          "Basic_Latin" => :common,
          "Latin-1_Supplement" => :latin,
          "Latin_Extended-A" => :latin,
          "Latin_Extended-B" => :latin,
          "Latin_Extended-C" => :latin,
          "Latin_Extended-D" => :latin,
          "Latin_Extended-E" => :latin,
          "Latin_Extended-F" => :latin,
          "Latin_Extended_Additional" => :latin,
          "Phonetic_Extensions" => :latin,
          "Phonetic_Extensions_Supplement" => :latin,
          "Modifier_Tone_Letters" => :latin,
          "Spacing_Modifier_Letters" => :common,
          "Combining_Diacritical_Marks" => :inherited,
          "Combining_Diacritical_Marks_Extended" => :inherited,
          "Combining_Diacritical_Marks_Supplement" => :inherited,
          "Combining_Diacritical_Marks_for_Symbols" => :inherited,
          "Combining_Half_Marks" => :inherited,

          # Greek
          "Greek_and_Coptic" => :greek,
          "Greek_Extended" => :greek,

          # Cyrillic
          "Cyrillic" => :cyrillic,
          "Cyrillic_Supplement" => :cyrillic,
          "Cyrillic_Extended-A" => :cyrillic,
          "Cyrillic_Extended-B" => :cyrillic,
          "Cyrillic_Extended-C" => :cyrillic,
          "Cyrillic_Extended-D" => :cyrillic,

          # Middle Eastern
          "Armenian" => :armenian,
          "Hebrew" => :hebrew,
          "Arabic" => :arabic,
          "Arabic_Supplement" => :arabic,
          "Arabic_Extended-A" => :arabic,
          "Arabic_Extended-B" => :arabic,
          "Arabic_Extended-C" => :arabic,
          "Arabic_Extended-D" => :arabic,
          "Arabic_Presentation_Forms-A" => :arabic,
          "Arabic_Presentation_Forms-B" => :arabic,
          "Syriac" => :syriac,
          "Syriac_Supplement" => :syriac,
          "Thaana" => :thaana,
          "Samaritan" => :samaritan,
          "Mandaic" => :mandaic,

          # Indic
          "Devanagari" => :devanagari,
          "Devanagari_Extended" => :devanagari,
          "Bengali" => :bengali,
          "Gurmukhi" => :gurmukhi,
          "Gujarati" => :gujarati,
          "Oriya" => :oriya,
          "Tamil" => :tamil,
          "Tamil_Supplement" => :tamil,
          "Telugu" => :telugu,
          "Kannada" => :kannada,
          "Malayalam" => :malayalam,
          "Sinhala" => :sinhala,
          "Sinhala_Archaic_Numbers" => :sinhala,
          "Vedic_Extensions" => :inherited,

          # Southeast Asian
          "Thai" => :thai,
          "Lao" => :lao,
          "Tibetan" => :tibetan,
          "Myanmar" => :myanmar,
          "Myanmar_Extended-A" => :myanmar,
          "Myanmar_Extended-B" => :myanmar,
          "Myanmar_Extended-C" => :myanmar,
          "Khmer" => :khmer,
          "Khmer_Symbols" => :khmer,
          "Tagalog" => :tagalog,
          "Hanunoo" => :hanunoo,
          "Buhid" => :buhid,
          "Tagbanwa" => :tagbanwa,

          # Hangul
          "Hangul_Jamo" => :hangul,
          "Hangul_Compatibility_Jamo" => :hangul,
          "Hangul_Jamo_Extended-A" => :hangul,
          "Hangul_Jamo_Extended-B" => :hangul,
          "Hangul_Syllables" => :hangul,

          # CJK — Han + native Japanese / Korean
          "CJK_Unified_Ideographs" => :han,
          "CJK_Unified_Ideographs_Extension_A" => :han,
          "CJK_Unified_Ideographs_Extension_B" => :han,
          "CJK_Unified_Ideographs_Extension_C" => :han,
          "CJK_Unified_Ideographs_Extension_D" => :han,
          "CJK_Unified_Ideographs_Extension-E" => :han,
          "CJK_Unified_Ideographs_Extension-F" => :han,
          "CJK_Unified_Ideographs_Extension_G" => :han,
          "CJK_Unified_Ideographs_Extension_H" => :han,
          "CJK_Unified_Ideographs_Extension_I" => :han,
          "CJK_Compatibility_Ideographs" => :han,
          "CJK_Compatibility_Ideographs_Supplement" => :han,
          "CJK_Radicals_Supplement" => :han,
          "Kangxi_Radicals" => :han,
          "CJK_Symbols_and_Punctuation" => :common,
          "CJK_Compatibility" => :han,
          "CJK_Compatibility_Forms" => :common,
          "CJK_Strokes" => :han,
          "Ideographic_Description_Characters" => :common,
          "Enclosed_CJK_Letters_and_Months" => :common,
          "Hiragana" => :hiragana,
          "Katakana" => :katakana,
          "Katakana_Phonetic_Extensions" => :katakana,
          "Kana_Supplement" => :hiragana,
          "Kana_Extended-A" => :hiragana,
          "Kana_Extended-B" => :hiragana,
          "Small_Kana_Extension" => :hiragana,
          "Halfwidth_and_Fullwidth_Forms" => :common,
          "Vertical_Forms" => :common,
          "Ideographic_Symbols_and_Punctuation" => :common,

          # Other scripts (single-block each)
          "Ethiopic" => :ethiopic,
          "Ethiopic_Supplement" => :ethiopic,
          "Ethiopic_Extended" => :ethiopic,
          "Ethiopic_Extended-A" => :ethiopic,
          "Ethiopian_Extended-B" => :ethiopic,
          "Cherokee" => :cherokee,
          "Cherokee_Supplement" => :cherokee,
          "Unified_Canadian_Aboriginal_Syllabics" => :canadian_aboriginal,
          "Unified_Canadian_Aboriginal_Syllabics_Extended" => :canadian_aboriginal,
          "Unified_Canadian_Aboriginal_Syllabics_Extended-A" => :canadian_aboriginal,
          "Ogham" => :ogham,
          "Runic" => :runic,
          "Glagolitic" => :glagolitic,
          "Glagolitic_Supplement" => :glagolitic,
          "Tifinagh" => :tifinagh,
          "Georgian" => :georgian,
          "Georgian_Supplement" => :georgian,
          "Georgian_Extended" => :georgian,
          "Mongolian" => :mongolian,
          "Mongolian_Supplement" => :mongolian,
          "Limbu" => :limbu,
          "Tai_Le" => :tai_le,
          "New_Tai_Lue" => :new_tai_lue,
          "Tai_Tham" => :tai_tham,
          "Tai_Viet" => :tai_viet,
          "Ol_Chiki" => :ol_chiki,
          "Bopomofo" => :bopomofo,
          "Bopomofo_Extended" => :bopomofo,
          "Yi_Syllables" => :yi,
          "Yi_Radicals" => :yi,
          "Vai" => :vai,
          "Bamum" => :bamum,
          "Bamum_Supplement" => :bamum,
          "Syloti_Nagri" => :syloti_nagri,
          "Phags-pa" => :phags_pa,
          "Saurashtra" => :saurashtra,
          "Kayah_Li" => :kayah_li,
          "Rejang" => :rejang,
          "Javanese" => :javanese,
          "Cham" => :cham,
          "Lepcha" => :lepcha,
          "Meetei_Mayek" => :meetei_mayek,
          "Meetei_Mayek_Extensions" => :meetei_mayek,
          "Lisu" => :lisu,
          "Lisu_Supplement" => :lisu,
          "Sundanese" => :sundanese,
          "Sundanese_Supplement" => :sundanese,
          "Batak" => :batak,
          "Buginese" => :buginese,
          "Ahom" => :ahom,
          "Dogra" => :dogra,
          "Tulu-Tigalari" => :tulu_tigalari,
          "Grantha" => :grantha,
          "Newa" => :newa,
          "Tirhuta" => :tirhuta,
          "Siddham" => :siddham,
          "Modi" => :modi,
          "Sharada" => :sharada,
          "Takri" => :takri,
          "Kaithi" => :kaithi,
          "Mahajani" => :mahajani,
          "Multani" => :multani,
          "Khudawadi" => :khudawadi,
          "Nandinagari" => :nandinagari,
          "Nushu" => :nushu,
          "Wancho" => :wancho,
          "Toto" => :toto,
          "Nag_Mundari" => :nag_mundari,

          # Numerals / symbols (Common)
          "Superscripts_and_Subscripts" => :common,
          "Number_Forms" => :common,
          "Currency_Symbols" => :common,
          "Letterlike_Symbols" => :common,
          "Arrows" => :common,
          "Mathematical_Operators" => :common,
          "Miscellaneous_Technical" => :common,
          "Control_Pictures" => :common,
          "Optical_Character_Recognition" => :common,
          "Enclosed_Alphanumerics" => :common,
          "Box_Drawing" => :common,
          "Block_Elements" => :common,
          "Geometric_Shapes" => :common,
          "Miscellaneous_Symbols" => :common,
          "Dingbats" => :common,
          "Miscellaneous_Mathematical_Symbols-A" => :common,
          "Miscellaneous_Mathematical_Symbols-B" => :common,
          "Supplemental_Arrows-A" => :common,
          "Supplemental_Arrows-B" => :common,
          "Supplemental_Arrows-C" => :common,
          "Supplemental_Mathematical_Operators" => :common,
          "Miscellaneous_Symbols_and_Arrows" => :common,
          "Braille_Patterns" => :braille,
          "General_Punctuation" => :common,
          "Supplemental_Punctuation" => :common,
          "Alphabetic_Presentation_Forms" => :common,
          "Specials" => :common,
          "Variation_Selectors" => :inherited,
          "Variation_Selectors_Supplement" => :inherited,
          "Tags" => :common,
        }.freeze

        # @param cp_map [Hash{Integer=>Object}] codepoint → donor label
        # @param cap [Integer] max codepoints per partition
        # @return [Blueprint]
        def call(cp_map, cap: DEFAULT_CAP)
          grouped = group_by_script(cp_map)
          partitions = []

          grouped.each do |script, entries|
            chunks(entries, cap).each_with_index do |chunk, idx|
              partitions << Partition.new(
                name: partition_name(script, idx),
                cps: chunk.map(&:first),
                donor_map: chunk.to_h,
              )
            end
          end

          Blueprint.new(partitions: partitions)
        end

        private

        def group_by_script(cp_map)
          cp_map.each_with_object(Hash.new do |h, k|
            h[k] = []
          end) do |(cp, label), h|
            script = script_of_codepoint(cp)
            h[script] << [cp, label]
          end
        end

        def script_of_codepoint(cp)
          block_label = ByBlock::BLOCKS.find do |_label, range|
            range.cover?(cp)
          end&.first
          return :other unless block_label

          SCRIPT_OF_BLOCK[block_label] || :other
        end

        def chunks(entries, cap)
          entries.each_slice(cap).to_a
        end

        # First partition per script has no suffix; subsequent ones
        # get _a, _b, ... matching ByPlane's sub-split convention.
        def partition_name(script, idx)
          return :"script_#{script}" if idx.zero?

          suffix = ("a".ord + idx - 1).chr
          :"script_#{script}_#{suffix}"
        end
      end
    end
  end
end
