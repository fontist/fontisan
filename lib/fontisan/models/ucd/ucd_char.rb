# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Ucd
      # Single <char> element from the UCDXML flat file.
      #
      # UCDXML uses two forms:
      #   <char cp="0041" name="..." script="Latin" block="Basic Latin" .../>
      #   <char first-cp="3400" last-cp="4DBF" name="..." script="Han" .../>
      #
      # The first form describes one codepoint. The second form describes a
      # closed range of codepoints that share the same properties (used for
      # CJK ideograph ranges where each codepoint would otherwise need its
      # own <char> entry).
      #
      # Both forms can appear in the same document; `cp` is mutually
      # exclusive with `first-cp`/`last-cp`.
      class UcdChar < Lutaml::Model::Serializable
        attribute :cp, :string
        attribute :first_cp, :string
        attribute :last_cp, :string
        attribute :name, :string
        attribute :general_category, :string
        attribute :script, :string
        attribute :block, :string
        attribute :age, :string

        xml do
          element "char"

          map_attribute "cp",               to: :cp
          map_attribute "first-cp",         to: :first_cp
          map_attribute "last-cp",          to: :last_cp
          map_attribute "name",             to: :name
          map_attribute "general-category", to: :general_category
          map_attribute "script",           to: :script
          map_attribute "block",            to: :block
          map_attribute "age",              to: :age
        end

        # True if this entry describes a codepoint range rather than a
        # single codepoint.
        def range?
          !first_cp.nil? && !last_cp.nil?
        end

        # The codepoints covered by this entry, as Integers.
        # For a single-codepoint entry, returns a one-element array.
        # For a range entry, returns the inclusive range as an array
        # (caller should treat this lazily if the range is huge — CJK
        # ranges can have tens of thousands of codepoints).
        def codepoints
          if range?
            (first_cp.to_i(16)..last_cp.to_i(16)).to_a
          elsif cp
            [cp.to_i(16)]
          else
            []
          end
        end
      end
    end
  end
end
