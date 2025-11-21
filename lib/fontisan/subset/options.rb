# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Subset
    # Subsetting configuration class
    #
    # This class defines all available options for font subsetting operations.
    # It provides sensible defaults for various subsetting scenarios and uses
    # Lutaml::Model for serialization support.
    #
    # @example Create default PDF subsetting options
    #   options = Fontisan::Subset::Options.new
    #   options.profile # => "pdf"
    #   options.drop_hints # => false
    #
    # @example Create custom web subsetting options
    #   options = Fontisan::Subset::Options.new(
    #     profile: "web",
    #     drop_hints: true,
    #     unicode_ranges: false
    #   )
    #
    # @example Retain original glyph IDs
    #   options = Fontisan::Subset::Options.new(retain_gids: true)
    class Options < Lutaml::Model::Serializable
      # Subsetting profile name (pdf, web, minimal, or custom)
      #
      # @return [String] the profile name
      attribute :profile, :string, default: -> { "pdf" }

      # Whether to drop hinting instructions
      #
      # Hinting improves text rendering at small sizes but increases file size.
      # Web fonts typically don't need hints due to modern rendering engines.
      #
      # @return [Boolean] true to drop hints, false to retain them
      attribute :drop_hints, :boolean, default: -> { false }

      # Whether to drop glyph names from the post table
      #
      # Glyph names are useful for debugging but not required for rendering.
      # Dropping them reduces file size.
      #
      # @return [Boolean] true to drop names, false to retain them
      attribute :drop_names, :boolean, default: -> { false }

      # Whether to prune OS/2 Unicode ranges
      #
      # Updates the OS/2 table's Unicode range bits to reflect only the
      # glyphs present in the subset.
      #
      # @return [Boolean] true to prune ranges, false to keep original
      attribute :unicode_ranges, :boolean, default: -> { true }

      # Whether to retain original glyph IDs
      #
      # When true, removed glyphs leave empty slots in the glyf table,
      # preserving original GID assignments. When false, glyphs are
      # compacted to eliminate gaps.
      #
      # @return [Boolean] true to retain GIDs, false to compact
      attribute :retain_gids, :boolean, default: -> { false }

      # Whether to include the .notdef glyph
      #
      # The .notdef glyph is displayed for missing characters. It is
      # typically required by font specifications.
      #
      # @return [Boolean] true to include .notdef, false to exclude
      attribute :include_notdef, :boolean, default: -> { true }

      # Whether to include the .null glyph
      #
      # The .null glyph (U+0000) is sometimes used for control purposes.
      #
      # @return [Boolean] true to include .null, false to exclude
      attribute :include_null, :boolean, default: -> { false }

      # OpenType features to retain in the subset
      #
      # An empty array means all features are retained. Specify feature
      # tags (e.g., ['liga', 'kern']) to keep only those features.
      #
      # @return [Array<String>] array of feature tags to retain
      attribute :features, :string, collection: true, default: -> { [] }

      # Script tags to retain in the subset
      #
      # An array containing "*" means all scripts are retained. Specify
      # script tags (e.g., ['latn', 'arab']) to keep only those scripts.
      #
      # @return [Array<String>] array of script tags to retain
      attribute :scripts, :string, collection: true, default: -> { ["*"] }

      # Initialize options with custom values
      #
      # @param attributes [Hash] hash of attribute values
      # @option attributes [String] :profile ("pdf") subsetting profile
      # @option attributes [Boolean] :drop_hints (false) drop hinting
      # @option attributes [Boolean] :drop_names (false) drop glyph names
      # @option attributes [Boolean] :unicode_ranges (true) prune OS/2 ranges
      # @option attributes [Boolean] :retain_gids (false) retain glyph IDs
      # @option attributes [Boolean] :include_notdef (true) include .notdef
      # @option attributes [Boolean] :include_null (false) include .null
      # @option attributes [Array<String>] :features ([]) features to keep
      # @option attributes [Array<String>] :scripts (["*"]) scripts to keep
      def initialize(attributes = {})
        super
      end

      # Check if all features should be retained
      #
      # @return [Boolean] true if features array is empty
      def all_features?
        features.empty?
      end

      # Check if all scripts should be retained
      #
      # @return [Boolean] true if scripts contains "*"
      def all_scripts?
        scripts.include?("*")
      end

      # Validate the options configuration
      #
      # @raise [ArgumentError] if profile is invalid
      # @return [Boolean] true if valid
      def validate!
        valid_profiles = %w[pdf web minimal custom]
        unless valid_profiles.include?(profile)
          raise ArgumentError,
                "Invalid profile '#{profile}'. Must be one of: #{valid_profiles.join(', ')}"
        end

        true
      end
    end
  end
end
