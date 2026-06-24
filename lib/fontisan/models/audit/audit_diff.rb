# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Structural diff between two AuditReports.
      #
      # `left_source`/`right_source` are the original source_file paths
      # (or report paths) so a consumer reading the diff alone can locate
      # the inputs.
      #
      # `field_changes` lists scalar fields whose values changed.
      # `codepoints` is the cmap delta (CodepointSetDiff).
      # The remaining fields are array set-diffs over the report's
      # structural inventory: OpenType features, scripts, UCD blocks, and
      # CLDR languages. Each is split into `added_*` (in right, not left)
      # and `removed_*` (in left, not right).
      class AuditDiff < Lutaml::Model::Serializable
        attribute :left_source,      :string
        attribute :right_source,     :string
        attribute :field_changes,    FieldChange, collection: true
        attribute :codepoints,       CodepointSetDiff
        attribute :added_features,   :string, collection: true
        attribute :removed_features, :string, collection: true
        attribute :added_scripts,    :string, collection: true
        attribute :removed_scripts,  :string, collection: true
        attribute :added_blocks,     :string, collection: true
        attribute :removed_blocks,   :string, collection: true
        attribute :added_languages,  :string, collection: true
        attribute :removed_languages, :string, collection: true

        key_value do
          map "left_source",       to: :left_source
          map "right_source",      to: :right_source
          map "field_changes",     to: :field_changes
          map "codepoints",        to: :codepoints
          map "added_features",    to: :added_features
          map "removed_features",  to: :removed_features
          map "added_scripts",     to: :added_scripts
          map "removed_scripts",   to: :removed_scripts
          map "added_blocks",      to: :added_blocks
          map "removed_blocks",    to: :removed_blocks
          map "added_languages",   to: :added_languages
          map "removed_languages", to: :removed_languages
        end

        # True when nothing differs. Useful for the text formatter.
        #
        # @return [Boolean]
        def empty?
          collection_empty?(field_changes) &&
            added_codepoints.zero? && removed_codepoints.zero? &&
            collection_empty?(added_features) && collection_empty?(removed_features) &&
            collection_empty?(added_scripts) && collection_empty?(removed_scripts) &&
            collection_empty?(added_blocks) && collection_empty?(removed_blocks) &&
            collection_empty?(added_languages) && collection_empty?(removed_languages)
        end

        def added_codepoints
          codepoints&.added_count || 0
        end

        def removed_codepoints
          codepoints&.removed_count || 0
        end

        private

        def collection_empty?(value)
          value.nil? || value.empty?
        end
      end
    end
  end
end
