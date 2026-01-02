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

      # Individual check result from DSL-based validation
      class CheckResult < Lutaml::Model::Serializable
        attribute :check_id, :string
        attribute :passed, :boolean
        attribute :severity, :string
        attribute :messages, :string, collection: true, default: -> { [] }
        attribute :table, :string
        attribute :field, :string

        yaml do
          map "check_id", to: :check_id
          map "passed", to: :passed
          map "severity", to: :severity
          map "messages", to: :messages
          map "table", to: :table
          map "field", to: :field
        end

        json do
          map "check_id", to: :check_id
          map "passed", to: :passed
          map "severity", to: :severity
          map "messages", to: :messages
          map "table", to: :table
          map "field", to: :field
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
      attribute :profile, :string
      attribute :status, :string
      attribute :use_case, :string
      attribute :checks_performed, :string, collection: true, default: -> { [] }
      attribute :check_results, CheckResult, collection: true, default: -> { [] }

      yaml do
        map "font_path", to: :font_path
        map "valid", to: :valid
        map "summary", to: :summary
        map "issues", to: :issues
        map "profile", to: :profile
        map "status", to: :status
        map "use_case", to: :use_case
        map "checks_performed", to: :checks_performed
        map "check_results", to: :check_results
      end

      json do
        map "font_path", to: :font_path
        map "valid", to: :valid
        map "summary", to: :summary
        map "issues", to: :issues
        map "profile", to: :profile
        map "status", to: :status
        map "use_case", to: :use_case
        map "checks_performed", to: :checks_performed
        map "check_results", to: :check_results
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

      # Check if font passed validation (alias for valid)
      #
      # @return [Boolean] true if font passed validation
      def passed?
        valid
      end

      # Check if font is valid (alias for valid attribute)
      #
      # @return [Boolean] true if font is valid
      def valid?
        valid
      end

      # Get result for a specific check by ID
      #
      # @param check_id [Symbol, String] The check identifier
      # @return [CheckResult, nil] The check result or nil if not found
      def result_of(check_id)
        check_results.find { |cr| cr.check_id == check_id.to_s }
      end

      # Get all passed checks
      #
      # @return [Array<CheckResult>] Array of passed checks
      def passed_checks
        check_results.select(&:passed)
      end

      # Get all failed checks
      #
      # @return [Array<CheckResult>] Array of failed checks
      def failed_checks
        check_results.reject(&:passed)
      end

      # Severity filtering methods

      # Get issues by severity level
      #
      # @param severity [Symbol, String] Severity level
      # @return [Array<Issue>] Array of issues with the specified severity
      def issues_by_severity(severity)
        issues.select { |issue| issue.severity == severity.to_s }
      end

      # Get fatal error issues
      #
      # @return [Array<Issue>] Array of fatal error issues
      def fatal_errors
        issues_by_severity(:fatal)
      end

      # Get error issues only
      #
      # @return [Array<Issue>] Array of error issues
      def errors_only
        issues_by_severity(:error)
      end

      # Get warning issues only
      #
      # @return [Array<Issue>] Array of warning issues
      def warnings_only
        issues_by_severity(:warning)
      end

      # Get info issues only
      #
      # @return [Array<Issue>] Array of info issues
      def info_only
        issues_by_severity(:info)
      end

      # Category filtering methods

      # Get issues by category
      #
      # @param category [String] Category name
      # @return [Array<Issue>] Array of issues in the specified category
      def issues_by_category(category)
        issues.select { |issue| issue.category == category.to_s }
      end

      # Get check results for a specific table
      #
      # @param table_tag [String] Table tag (e.g., 'name', 'head')
      # @return [Array<CheckResult>] Array of check results for the table
      def table_issues(table_tag)
        check_results.select { |cr| cr.table == table_tag.to_s }
      end

      # Get check results for a specific field in a table
      #
      # @param table_tag [String] Table tag
      # @param field_name [String, Symbol] Field name
      # @return [Array<CheckResult>] Array of check results for the field
      def field_issues(table_tag, field_name)
        check_results.select { |cr| cr.table == table_tag.to_s && cr.field == field_name.to_s }
      end

      # Check filtering methods

      # Get checks by status
      #
      # @param passed [Boolean] true for passed checks, false for failed checks
      # @return [Array<CheckResult>] Array of checks with the specified status
      def checks_by_status(passed:)
        check_results.select { |cr| cr.passed == passed }
      end

      # Get IDs of failed checks
      #
      # @return [Array<String>] Array of failed check IDs
      def failed_check_ids
        failed_checks.map(&:check_id)
      end

      # Get IDs of passed checks
      #
      # @return [Array<String>] Array of passed check IDs
      def passed_check_ids
        passed_checks.map(&:check_id)
      end

      # Statistics methods

      # Calculate failure rate as percentage
      #
      # @return [Float] Failure rate (0.0 to 1.0)
      def failure_rate
        return 0.0 if check_results.empty?
        failed_checks.length.to_f / check_results.length
      end

      # Calculate pass rate as percentage
      #
      # @return [Float] Pass rate (0.0 to 1.0)
      def pass_rate
        1.0 - failure_rate
      end

      # Get severity distribution
      #
      # @return [Hash] Hash with :errors, :warnings, :info counts
      def severity_distribution
        {
          errors: summary.errors,
          warnings: summary.warnings,
          info: summary.info,
        }
      end

      # Export format methods

      # Generate full detailed text report
      #
      # @return [String] Detailed text report
      def to_text_report
        text_summary
      end

      # Generate brief summary
      #
      # @return [String] Brief summary string
      def to_summary
        "#{summary.errors} errors, #{summary.warnings} warnings, #{summary.info} info"
      end

      # Generate tabular format for CLI
      #
      # @return [String] Tabular format output
      def to_table_format
        lines = []
        lines << "CHECK_ID | STATUS | SEVERITY | TABLE"
        lines << "-" * 60
        check_results.each do |cr|
          status = cr.passed ? "PASS" : "FAIL"
          table = cr.table || "N/A"
          lines << "#{cr.check_id} | #{status} | #{cr.severity} | #{table}"
        end
        lines.join("\n")
      end
    end
  end
end
