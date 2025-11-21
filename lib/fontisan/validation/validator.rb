# frozen_string_literal: true

require "yaml"
require_relative "../models/validation_report"
require_relative "table_validator"
require_relative "structure_validator"
require_relative "consistency_validator"
require_relative "checksum_validator"

module Fontisan
  module Validation
    # Validator is the main orchestrator for font validation
    #
    # This class coordinates all validation checks (tables, structure,
    # consistency, checksums) and produces a comprehensive ValidationReport.
    #
    # Single Responsibility: Orchestration of validation workflow
    #
    # @example Validating a font
    #   validator = Validator.new(level: :standard)
    #   report = validator.validate(font, font_path)
    #   puts report.text_summary
    class Validator
      # Validation levels
      LEVELS = %i[strict standard lenient].freeze

      # Initialize validator
      #
      # @param level [Symbol] Validation level (:strict, :standard, :lenient)
      # @param rules_path [String, nil] Path to custom rules file
      def initialize(level: :standard, rules_path: nil)
        @level = level
        validate_level!

        @rules = load_rules(rules_path)
        @table_validator = TableValidator.new(@rules)
        @structure_validator = StructureValidator.new(@rules)
        @consistency_validator = ConsistencyValidator.new(@rules)
        @checksum_validator = ChecksumValidator.new(@rules)
      end

      # Validate a font
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font to validate
      # @param font_path [String] Path to the font file
      # @return [Models::ValidationReport] Validation report
      def validate(font, font_path)
        report = Models::ValidationReport.new(
          font_path: font_path,
          valid: true,
        )

        begin
          # Run all validation checks
          all_issues = []

          # 1. Table validation
          all_issues.concat(@table_validator.validate(font))

          # 2. Structure validation
          all_issues.concat(@structure_validator.validate(font))

          # 3. Consistency validation
          all_issues.concat(@consistency_validator.validate(font))

          # 4. Checksum validation (requires file path)
          all_issues.concat(@checksum_validator.validate(font, font_path))

          # Add issues to report
          all_issues.each do |issue|
            case issue[:severity]
            when "error"
              report.add_error(issue[:category], issue[:message],
                               issue[:location])
            when "warning"
              report.add_warning(issue[:category], issue[:message],
                                 issue[:location])
            when "info"
              report.add_info(issue[:category], issue[:message],
                              issue[:location])
            end
          end

          # Determine overall validity based on level
          report.valid = determine_validity(report)
        rescue StandardError => e
          report.add_error("validation", "Validation failed: #{e.message}", nil)
          report.valid = false
        end

        report
      end

      # Get the current validation level
      #
      # @return [Symbol] The validation level
      attr_reader :level

      private

      # Validate that the level is supported
      #
      # @raise [ArgumentError] if level is invalid
      # @return [void]
      def validate_level!
        unless LEVELS.include?(@level)
          raise ArgumentError,
                "Invalid validation level: #{@level}. Must be one of: #{LEVELS.join(', ')}"
        end
      end

      # Load validation rules
      #
      # @param rules_path [String, nil] Path to custom rules file
      # @return [Hash] The rules configuration
      def load_rules(rules_path)
        path = rules_path || default_rules_path
        YAML.load_file(path)
      rescue Errno::ENOENT
        raise "Validation rules file not found: #{path}"
      rescue Psych::SyntaxError => e
        raise "Invalid validation rules YAML: #{e.message}"
      end

      # Get the default rules path
      #
      # @return [String] Path to default rules file
      def default_rules_path
        File.join(__dir__, "..", "config", "validation_rules.yml")
      end

      # Determine if font is valid based on validation level
      #
      # @param report [Models::ValidationReport] The validation report
      # @return [Boolean] true if font is valid for the given level
      def determine_validity(report)
        case @level
        when :strict
          # Strict: no errors, no warnings
          !report.has_errors? && !report.has_warnings?
        when :standard
          # Standard: no errors (warnings allowed)
          !report.has_errors?
        when :lenient
          # Lenient: no critical errors (some errors may be acceptable)
          # For now, treat lenient same as standard
          !report.has_errors?
        end
      end
    end
  end
end
