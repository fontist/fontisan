# frozen_string_literal: true

module Fontisan
  module Cldr
    # In-memory per-language codepoint lookup.
    #
    # Loads a YAML index of `{language: [codepoint, ...]}`. Each language's
    # codepoints are stored as a Set<Integer> for O(1) intersection checks.
    #
    # Used by {Cldr::Aggregator} to compute per-language coverage %.
    class Index
      include Enumerable

      # @param entries [Hash{String=>Set<Integer>, Array<Integer>}]
      def initialize(entries = {})
        @entries = entries.transform_values do |cps|
          cps.is_a?(Set) ? cps : Set.new(cps)
        end
      end

      # @return [Hash{String=>Set<Integer>}]
      attr_reader :entries

      def each(&)
        @entries.each(&)
      end

      def size
        @entries.size
      end

      def languages
        @entries.keys.sort
      end

      # @param language [String]
      # @return [Set<Integer>, nil]
      def lookup(language)
        @entries[language]
      end

      def include?(language)
        @entries.key?(language)
      end

      # Serialize to a YAML file.
      # @param path [String, Pathname]
      # @return [void]
      def save(path)
        File.open(path, "w") do |file|
          YAML.dump(@entries.transform_values(&:sort), file)
        end
      end

      # Load from a YAML file previously written by #save.
      # @param path [String, Pathname]
      # @return [Index]
      def self.load(path)
        hash = YAML.load_file(path)
        new(hash)
      end
    end
  end
end
