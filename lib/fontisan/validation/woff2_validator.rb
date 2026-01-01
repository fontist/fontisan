# frozen_string_literal: true

require "yaml"
require_relative "../models/validation_report"
require_relative "woff2_header_validator"
require_relative "woff2_table_validator"

module Fontisan
  module Validation
    # Woff2Validator is the main orchestrator for WOFF2 font validation
    #
    # This class coordinates WOFF2-specific validation checks (header, tables)
    # and produces a comprehensive ValidationReport. It is designed to validate
    # WOFF2 encoding quality and spec compliance.
    #
    # Single Responsibility: Orchestration of WOFF2 validation workflow
    #
    # @example Validating a WOFF2 font
    #   validator = Woff2Validator.new(level: :standard)
    #   report = validator.validate(woff2_font, font_path)
    #   puts report.text_summary
    #
    # @example Validating WOFF2 encoding result
    #   woff2_font = Woff2Font.from_file("output.woff2")
    #   validator = Woff2Validator.new
    #   report = validator.validate(woff2_font, "output.woff2")
    #   puts "Valid: #{report.valid}"
    class Woff2Validator
      # Validation levels
      LEVELS = %i[strict standard lenient].freeze

      # Initialize WOFF2 validator
      #
      # @param level [Symbol] Validation level (:strict, :standard, :lenient)
      # @param rules_path [String, nil] Path to custom rules file
      def initialize(level: :standard, rules_path: nil)
        @level = level
        validate_level!

        @rules = load_rules(rules_path)
        @header_validator = Woff2HeaderValidator.new(@rules)
        @table_validator = Woff2TableValidator.new(@rules)
      end

      # Validate a WOFF2 font
      #
      # @param woff2_font [Woff2Font] The WOFF2 font to validate
      # @param font_path [String] Path to the font file
      # @return [Models::ValidationReport] Validation report
      def validate(woff2_font, font_path)
        report = Models::ValidationReport.new(
          font_path: font_path,
          valid: true,
        )

        begin
          # Run all validation checks
          all_issues = []

          # 1. Header validation
          all_issues.concat(@header_validator.validate(woff2_font))

          # 2. Table validation
          all_issues.concat(@table_validator.validate(woff2_font))

          # 3. WOFF2-specific checks
          all_issues.concat(check_woff2_specific(woff2_font))

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
          report.add_error("woff2_validation", "WOFF2 validation failed: #{e.message}", nil)
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
        # If rules file doesn't exist, use minimal defaults
        {
          "woff2_validation" => {
            "min_compression_ratio" => 0.2,
            "max_compression_ratio" => 0.95,
            "max_table_size" => 104_857_600,
          },
        }
      rescue Psych::SyntaxError => e
        raise "Invalid validation rules YAML: #{e.message}"
      end

      # Get the default rules path
      #
      # @return [String] Path to default rules file
      def default_rules_path
        File.join(__dir__, "..", "config", "validation_rules.yml")
      end

      # WOFF2-specific validation checks
      #
      # @param woff2_font [Woff2Font] The WOFF2 font
      # @return [Array<Hash>] Array of WOFF2-specific issues
      def check_woff2_specific(woff2_font)
        issues = []

        # Check required tables for font type
        issues.concat(check_required_woff2_tables(woff2_font))

        # Check compression quality
        issues.concat(check_compression_quality(woff2_font))

        issues
      end

      # Check required tables based on font flavor
      #
      # @param woff2_font [Woff2Font] The WOFF2 font
      # @return [Array<Hash>] Array of required table issues
      def check_required_woff2_tables(woff2_font)
        issues = []

        # Basic required tables for all fonts
        required_tables = %w[head hhea maxp name cmap post]

        # Add flavor-specific tables
        if woff2_font.truetype?
          # For TrueType, we need glyf and hmtx
          # Note: loca is NOT required in WOFF2 table directory because it can be
          # reconstructed from transformed glyf. This is standard WOFF2 behavior.
          required_tables << "glyf"
          required_tables << "hmtx"
        elsif woff2_font.cff?
          required_tables << "CFF "
        end

        # Check each required table
        required_tables.each do |table_tag|
          unless woff2_font.has_table?(table_tag)
            issues << {
              severity: "error",
              category: "woff2_structure",
              message: "Missing required table: #{table_tag}",
              location: nil,
            }
          end
        end

        issues
      end

      # Check compression quality
      #
      # @param woff2_font [Woff2Font] The WOFF2 font
      # @return [Array<Hash>] Array of compression quality issues
      def check_compression_quality(woff2_font)
        issues = []

        header = woff2_font.header
        return issues unless header

        # Calculate actual compression ratio
        if header.total_sfnt_size.positive? && header.total_compressed_size.positive?
          ratio = header.total_compressed_size.to_f / header.total_sfnt_size
          percentage = (ratio * 100).round(2)

          # Info about compression achieved
          issues << {
            severity: "info",
            category: "woff2_compression",
            message: "Compression ratio: #{percentage}% (#{header.total_compressed_size} / #{header.total_sfnt_size} bytes)",
            location: nil,
          }

          # Warn if compression is poor (> 80%)
          if ratio > 0.80
            issues << {
              severity: "warning",
              category: "woff2_compression",
              message: "Poor compression ratio: #{percentage}% (expected < 80%)",
              location: nil,
            }
          end
        end

        issues
      end

      # Determine if WOFF2 font is valid based on validation level
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
          # For WOFF2, treat lenient same as standard
          !report.has_errors?
        end
      end
    end
  end
end
