# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Diff between two cmap codepoint sets.
      #
      # `added`/`removed` are compact range lists (CodepointRange) so a
      # large delta (e.g. CJK extension added) renders as a handful of
      # ranges rather than thousands of codepoints.
      #
      # `unchanged_count` is the intersection size — useful as a sanity
      # check that the two reports share enough coverage to be meaningfully
      # comparable.
      class CodepointSetDiff < Lutaml::Model::Serializable
        attribute :added,            CodepointRange, collection: true
        attribute :removed,          CodepointRange, collection: true
        attribute :added_count,      :integer
        attribute :removed_count,    :integer
        attribute :unchanged_count,  :integer

        key_value do
          map "added",           to: :added
          map "removed",         to: :removed
          map "added_count",     to: :added_count
          map "removed_count",   to: :removed_count
          map "unchanged_count", to: :unchanged_count
        end
      end
    end
  end
end
