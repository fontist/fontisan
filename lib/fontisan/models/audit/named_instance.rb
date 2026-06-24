# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # One fvar named instance (e.g. "Bold", "SemiCondensed").
      #
      # `coordinates` is serialized as a compact "tag=value,tag=value" string
      # (e.g. "wght=700,wdth=100") for human readability. The AuditReport is
      # primarily a human-facing artifact; downstream tooling that needs
      # structured coordinates can re-derive them from fvar.
      class NamedInstance < Lutaml::Model::Serializable
        attribute :subfamily_name,  :string
        attribute :postscript_name, :string
        attribute :coordinates,     :string

        key_value do
          map "subfamily_name",  to: :subfamily_name
          map "postscript_name", to: :postscript_name
          map "coordinates",     to: :coordinates
        end

        # Build the coordinates string from a parallel array of axis tags
        # and fvar coordinate values. Returns nil if either side is empty.
        #
        # @param axis_tags [Array<String>] ordered axis tags (e.g. ["wght", "wdth"])
        # @param values [Array<Numeric>] ordered coordinate values
        # @return [String, nil]
        def self.format_coordinates(axis_tags, values)
          return nil if axis_tags.nil? || values.nil?
          return nil if axis_tags.empty? || values.empty?

          pairs = axis_tags.zip(values).map { |tag, val| "#{tag}=#{val}" }
          pairs.join(",")
        end
      end
    end
  end
end
