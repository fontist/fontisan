# frozen_string_literal: true

require "json"

module Fontisan
  module Cldr
    # Builds the per-language codepoint index from a cached CLDR JSON
    # archive and persists it as a YAML file for future Index loads.
    #
    # Walks every `main/<lang>/characters.json` file under the cached
    # archive, extracts `exemplarCharacters` (plus auxiliary and index
    # sets when present), parses each via {UnicodeSetParser}, and unions
    # the result into a single codepoint set per language.
    module IndexBuilder
      class << self
        # Build + persist the languages index for a cached version.
        # @param version [String]
        # @return [Index]
        def build(version)
          entries = collect_from_cache(version)
          CacheManager.index_dir(version).mkpath
          index = Index.new(entries)
          index.save(CacheManager.languages_index_path(version))
          index
        end

        # Pure: build an Index from a hash of `language => exemplar_string`.
        # @param exemplars_by_lang [Hash{String=>String}]
        # @return [Index]
        def build_from_exemplars(exemplars_by_lang)
          entries = exemplars_by_lang.transform_values do |set_str|
            set_str.nil? ? Set.new : Set.new(UnicodeSetParser.call(set_str))
          end
          Index.new(entries)
        end

        private

        def collect_from_cache(version)
          main_dir = CacheManager.characters_main_dir(version)
          return {} unless main_dir.exist?

          main_dir.children.select(&:directory?).each_with_object({}) do |lang_dir, hash|
            file = lang_dir.join("characters.json")
            next unless file.exist?

            lang = lang_dir.basename.to_s
            hash[lang] = parse_language_file(file)
          end
        end

        def parse_language_file(file)
          data = JSON.parse(file.read)
          lang_key = data.dig("main", "locale") ||
            data["main"]&.keys&.first
          return Set.new unless lang_key

          chars_node = data.dig("main", lang_key, "characters") || {}
          sets = %w[exemplarCharacters auxiliary exemplarCharactersIndex
                    exemplarCharactersPunctuation].filter_map do |field|
            chars_node[field]
          end
          sets.inject(Set.new) do |acc, set_str|
            acc | Set.new(UnicodeSetParser.call(set_str))
          rescue UnicodeSetParser::ParseError
            acc
          end
        end
      end
    end
  end
end
