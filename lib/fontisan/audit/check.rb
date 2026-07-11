# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Audit
    # Abstract base for all audit checks. A check is a stateless
    # function that examines a loaded font and returns an Array of
    # {Models::ValidationReport::Issue} records. An empty array means
    # the font passed the check.
    #
    # Subclasses MUST override {.call} and {.code}.
    #
    # Checks are intentionally stateless + side-effect free so they
    # can be composed, run in parallel, and tested in isolation.
    class Check
      # Run the check against +font+.
      #
      # @param font [SfntFont, BaseCollection]
      # @return [Array<Models::ValidationReport::Issue>]
      def self.call(font)
        raise NotImplementedError,
              "#{name} must override .call(font) -> Array<Issue>"
      end

      # Unique short identifier for this check (e.g. :table_checksum).
      # Used as the issue +category+ for programmatic filtering.
      #
      # @return [Symbol]
      def self.code
        raise NotImplementedError,
              "#{name} must override .code -> Symbol"
      end

      # Build an issue. Centralizes the category so callers don't repeat it.
      # @return [Models::ValidationReport::Issue]
      def self.issue(severity:, message:, location: nil)
        Models::ValidationReport::Issue.new(
          severity: severity.to_s,
          category: code.to_s,
          message: message,
          location: location,
        )
      end
    end
  end
end
