# frozen_string_literal: true

require_relative "base_command"
require_relative "../validation/validator"
require_relative "../validation/variable_font_validator"
require_relative "../font_loader"

module Fontisan
  module Commands
    # ValidateCommand provides CLI interface for font validation
    #
    # This command validates fonts against quality checks, structural integrity,
    # and OpenType specification compliance. It supports different validation
    # levels and output formats.
    #
    # @example Validating a font
    #   command = ValidateCommand.new(
    #     input: "font.ttf",
    #     level: :standard,
    #     format: :text
    #   )
    #   exit_code = command.run
    class ValidateCommand < BaseCommand
      # Initialize validate command
      #
      # @param input [String] Path to font file
      # @param level [Symbol] Validation level (:strict, :standard, :lenient)
      # @param format [Symbol] Output format (:text, :yaml, :json)
      # @param verbose [Boolean] Show all issues (default: true)
      # @param quiet [Boolean] Only return exit code, no output (default: false)
      def initialize(input:, level: :standard, format: :text, verbose: true,
quiet: false)
        super()
        @input = input
        @level = level.to_sym
        @format = format.to_sym
        @verbose = verbose
        @quiet = quiet
      end

      # Run the validation command
      #
      # @return [Integer] Exit code (0 = valid, 1 = errors, 2 = warnings only)
      def run
        validate_params!

        # Load font
        font = load_font
        return 1 unless font

        # Create validator
        validator = Validation::Validator.new(level: @level)

        # Run validation
        report = validator.validate(font, @input)

        # Add variable font validation if applicable
        validate_variable_font(font, report) if font.has_table?("fvar")

        # Output results unless quiet mode
        output_report(report) unless @quiet

        # Return appropriate exit code
        determine_exit_code(report)
      rescue StandardError => e
        puts "Error: #{e.message}" unless @quiet
        puts e.backtrace.join("\n") if @verbose && !@quiet
        1
      end

      private

      # Validate variable font structure
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font to validate
      # @param report [Models::ValidationReport] The validation report to update
      # @return [void]
      def validate_variable_font(font, report)
        var_validator = Validation::VariableFontValidator.new(font)
        errors = var_validator.validate

        if errors.any?
          puts "\nVariable font validation:" if @verbose && !@quiet
          errors.each do |error|
            puts "  ERROR: #{error}" if @verbose && !@quiet
            # Add to report if report supports adding errors
            report.errors << { message: error, category: "variable_font" } if report.respond_to?(:errors)
          end
        elsif @verbose && !@quiet
          puts "\n✓ Variable font structure valid"
        end
      end

      # Validate command parameters
      #
      # @raise [ArgumentError] if parameters are invalid
      # @return [void]
      def validate_params!
        if @input.nil? || @input.empty?
          raise ArgumentError,
                "Input file is required"
        end
        unless File.exist?(@input)
          raise ArgumentError,
                "Input file does not exist: #{@input}"
        end

        valid_levels = %i[strict standard lenient]
        unless valid_levels.include?(@level)
          raise ArgumentError,
                "Invalid level: #{@level}. Must be one of: #{valid_levels.join(', ')}"
        end

        valid_formats = %i[text yaml json]
        unless valid_formats.include?(@format)
          raise ArgumentError,
                "Invalid format: #{@format}. Must be one of: #{valid_formats.join(', ')}"
        end
      end

      # Load the font file
      #
      # @return [TrueTypeFont, OpenTypeFont, nil] The loaded font or nil on error
      def load_font
        FontLoader.load(@input)
      rescue StandardError => e
        puts "Error loading font: #{e.message}" unless @quiet
        nil
      end

      # Output validation report in requested format
      #
      # @param report [Models::ValidationReport] The validation report
      # @return [void]
      def output_report(report)
        case @format
        when :text
          output_text(report)
        when :yaml
          output_yaml(report)
        when :json
          output_json(report)
        end
      end

      # Output report in text format
      #
      # @param report [Models::ValidationReport] The validation report
      # @return [void]
      def output_text(report)
        if @verbose
          puts report.text_summary
        else
          # Compact output: just status and error/warning counts
          status = report.valid ? "VALID" : "INVALID"
          puts "#{status}: #{report.summary.errors} errors, #{report.summary.warnings} warnings"

          # Show errors only in non-verbose mode
          report.errors.each do |error|
            puts "  [ERROR] #{error.message}"
          end
        end
      end

      # Output report in YAML format
      #
      # @param report [Models::ValidationReport] The validation report
      # @return [void]
      def output_yaml(report)
        require "yaml"
        puts report.to_yaml
      end

      # Output report in JSON format
      #
      # @param report [Models::ValidationReport] The validation report
      # @return [void]
      def output_json(report)
        require "json"
        puts report.to_json
      end

      # Determine exit code based on validation results
      #
      # Exit codes:
      # - 0: Valid (no errors, or only warnings in lenient mode)
      # - 1: Has errors
      # - 2: Has warnings only (no errors)
      #
      # @param report [Models::ValidationReport] The validation report
      # @return [Integer] Exit code
      def determine_exit_code(report)
        if report.has_errors?
          1
        elsif report.has_warnings?
          2
        else
          0
        end
      end
    end
  end
end
