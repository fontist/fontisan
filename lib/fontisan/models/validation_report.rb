# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # ValidationReport represents the result of font validation
    #
    # This model encapsulates all validation results including error, warning,
    # and informational messages. It supports serialization to YAML, JSON, and
    # plain text formats for different use cases.
    #
    # @example Creating a validation report
    #   report = ValidationReport.new(
    #     font_path: "font.ttf",
    #     valid: false
    #   )
    #   report.add_error("tables", "Missing required table: glyf", nil)
    #   report.add_warning("checksum", "Table 'name' checksum mismatch", "name table")
    #
    # @example Serializing to YAML
    #   yaml_output = report.to_yaml
    #
    # @example Serializing to JSON
    #   json_output = report.to_json
    class ValidationReport < Lutaml::Model::Serializable
      # Individual validation issue
      class Issue < Lutaml::Model::Serializable
        attribute :severity, :string
        attribute :category, :string
        attribute :message, :string
        attribute :location, :string, default: -> {}

        yaml do
          map "severity", to: :severity
          map "category", to: :category
          map "message", to: :message
          map "location", to: :location
        end

        json do
          map "severity", to: :severity
          map "category", to: :category
          map "message", to: :message
          map "location", to: :location
        end
      end

      # Validation summary counts
      class Summary < Lutaml::Model::Serializable
        attribute :errors, :integer, default: -> { 0 }
        attribute :warnings, :integer, default: -> { 0 }
        attribute :info, :integer, default: -> { 0 }

        yaml do
          map "errors", to: :errors
          map "warnings", to: :warnings
          map "info", to: :info
        end

        json do
          map "errors", to: :errors
          map "warnings", to: :warnings
          map "info", to: :info
        end
      end

      attribute :font_path, :string
      attribute :valid, :boolean
      attribute :issues, Issue, collection: true, default: -> { [] }
      attribute :summary, Summary, default: -> { Summary.new }

      yaml do
        map "font_path", to: :font_path
        map "valid", to: :valid
        map "summary", to: :summary
        map "issues", to: :issues
      end

      json do
        map "font_path", to: :font_path
        map "valid", to: :valid
        map "summary", to: :summary
        map "issues", to: :issues
      end

      # Add an error to the report
      #
      # @param category [String] The error category (e.g., "tables", "structure")
      # @param message [String] The error message
      # @param location [String, nil] The specific location of the error
      # @return [void]
      def add_error(category, message, location = nil)
        issues << Issue.new(
          severity: "error",
          category: category,
          message: message,
          location: location,
        )
        summary.errors += 1
        self.valid = false
      end

      # Add a warning to the report
      #
      # @param category [String] The warning category
      # @param message [String] The warning message
      # @param location [String, nil] The specific location of the warning
      # @return [void]
      def add_warning(category, message, location = nil)
        issues << Issue.new(
          severity: "warning",
          category: category,
          message: message,
          location: location,
        )
        summary.warnings += 1
      end

      # Add an info message to the report
      #
      # @param category [String] The info category
      # @param message [String] The info message
      # @param location [String, nil] The specific location
      # @return [void]
      def add_info(category, message, location = nil)
        issues << Issue.new(
          severity: "info",
          category: category,
          message: message,
          location: location,
        )
        summary.info += 1
      end

      # Get all error issues
      #
      # @return [Array<Issue>] Array of error issues
      def errors
        issues.select { |issue| issue.severity == "error" }
      end

      # Get all warning issues
      #
      # @return [Array<Issue>] Array of warning issues
      def warnings
        issues.select { |issue| issue.severity == "warning" }
      end

      # Get all info issues
      #
      # @return [Array<Issue>] Array of info issues
      def info_issues
        issues.select { |issue| issue.severity == "info" }
      end

      # Check if report has errors
      #
      # @return [Boolean] true if errors exist
      def has_errors?
        summary.errors.positive?
      end

      # Check if report has warnings
      #
      # @return [Boolean] true if warnings exist
      def has_warnings?
        summary.warnings.positive?
      end

      # Get a text summary of the validation
      #
      # @return [String] Human-readable summary
      def text_summary
        status = valid ? "VALID" : "INVALID"
        lines = []
        lines << "Font: #{font_path}"
        lines << "Status: #{status}"
        lines << ""
        lines << "Summary:"
        lines << "  Errors: #{summary.errors}"
        lines << "  Warnings: #{summary.warnings}"
        lines << "  Info: #{summary.info}"

        if issues.any?
          lines << ""
          lines << "Issues:"
          issues.each do |issue|
            severity_marker = case issue.severity
                              when "error" then "[ERROR]"
                              when "warning" then "[WARN]"
                              when "info" then "[INFO]"
                              end
            location_info = issue.location ? " (#{issue.location})" : ""
            lines << "  #{severity_marker} #{issue.category}: #{issue.message}#{location_info}"
          end
        end

        lines.join("\n")
      end
    end
  end
end
