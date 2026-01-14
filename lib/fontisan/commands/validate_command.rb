# frozen_string_literal: true

require_relative "base_command"
require_relative "../validators/profile_loader"
require_relative "../font_loader"
require_relative "../tables/name"

module Fontisan
  module Commands
    # ValidateCommand provides CLI interface for font validation
    #
    # This command validates fonts against quality checks, structural integrity,
    # and OpenType specification compliance. It supports different validation
    # profiles and output formats, with ftxvalidator-compatible options.
    #
    # @example Validating a font with default profile
    #   command = ValidateCommand.new(input: "font.ttf")
    #   exit_code = command.run
    #
    # @example Validating with specific profile
    #   command = ValidateCommand.new(
    #     input: "font.ttf",
    #     profile: :web,
    #     format: :json
    #   )
    #   exit_code = command.run
    class ValidateCommand < BaseCommand
      # Initialize validate command
      #
      # @param input [String] Path to font file
      # @param profile [Symbol, String, nil] Validation profile (default: :default)
      # @param exclude [Array<String>] Tests to exclude
      # @param output [String, nil] Output file path
      # @param format [Symbol] Output format (:text, :yaml, :json)
      # @param full_report [Boolean] Generate full detailed report
      # @param summary_report [Boolean] Generate brief summary report
      # @param table_report [Boolean] Generate tabular format report
      # @param verbose [Boolean] Show verbose output
      # @param suppress_warnings [Boolean] Suppress warning output
      # @param return_value_results [Boolean] Use return values to indicate results
      def initialize(
        input:,
        profile: nil,
        exclude: [],
        output: nil,
        format: :text,
        full_report: false,
        summary_report: false,
        table_report: false,
        verbose: false,
        suppress_warnings: false,
        return_value_results: false
      )
        @input = input
        @profile = profile || :default
        @exclude = exclude
        @output = output
        @format = format
        @full_report = full_report
        @summary_report = summary_report
        @table_report = table_report
        @verbose = verbose
        @suppress_warnings = suppress_warnings
        @return_value_results = return_value_results
      end

      # Run the validation command
      #
      # @return [Integer] Exit code (0 = valid, 2 = fatal, 3 = errors, 4 = warnings, 5 = info)
      def run
        # Load font with appropriate mode
        profile_config = Validators::ProfileLoader.profile_info(@profile)
        unless profile_config
          puts "Error: Unknown profile '#{@profile}'" unless @suppress_warnings
          return 1
        end

        mode = profile_config[:loading_mode].to_sym

        # Check if input is a collection
        if FontLoader.collection?(@input)
          validate_collection(mode)
        else
          validate_single_font(mode)
        end
      rescue StandardError => e
        puts "Error: #{e.message}" unless @suppress_warnings
        puts e.backtrace.join("\n") if @verbose && !@suppress_warnings
        1
      end

      private

      # Validate a single font file
      #
      # @param mode [Symbol] Loading mode
      # @return [Integer] Exit code
      def validate_single_font(mode)
        font = FontLoader.load(@input, mode: mode)

        # Select validator
        validator = Validators::ProfileLoader.load(@profile)

        # Run validation
        report = validator.validate(font)

        # Filter excluded checks if specified
        if @exclude.any?
          report.check_results.reject! { |cr| @exclude.include?(cr.check_id) }
        end

        # Generate output
        output = generate_output(report)

        # Write to file or stdout
        if @output
          File.write(@output, output)
          puts "Validation report written to #{@output}" if @verbose && !@suppress_warnings
        else
          puts output unless @suppress_warnings
        end

        # Return exit code
        exit_code(report)
      end

      # Validate all fonts in a collection
      #
      # @param mode [Symbol] Loading mode
      # @return [Integer] Exit code
      def validate_collection(mode)
        require_relative "../models/collection_validation_report"
        require_relative "../models/font_report"

        # Load collection metadata
        collection = FontLoader.load_collection(@input)

        # Create collection report
        collection_report = Models::CollectionValidationReport.new(
          collection_path: @input,
          collection_type: collection.class.collection_format,
          num_fonts: collection.num_fonts,
        )

        # Get validator
        validator = Validators::ProfileLoader.load(@profile)

        # Validate each font
        collection.num_fonts.times do |index|
          font = FontLoader.load(@input, font_index: index, mode: mode)
          font_report = validator.validate(font)

          # Extract font name
          font_name = extract_font_name(font, index)

          # Create and add font report
          collection_report.add_font_report(
            Models::FontReport.new(
              font_index: index,
              font_name: font_name,
              report: font_report,
            ),
          )
        rescue StandardError => e
          # Create error report for failed font loading
          error_report = Models::ValidationReport.new(
            font_path: @input,
            valid: false,
          )
          error_report.add_error("font_loading",
                                 "Failed to load font #{index}: #{e.message}", nil)

          collection_report.add_font_report(
            Models::FontReport.new(
              font_index: index,
              font_name: "Font #{index}",
              report: error_report,
            ),
          )
        end

        # Generate output
        output = collection_report.text_summary

        # Write to file or stdout
        if @output
          File.write(@output, output)
          puts "Validation report written to #{@output}" if @verbose && !@suppress_warnings
        else
          puts output unless @suppress_warnings
        end

        # Return exit code based on worst status
        collection_exit_code(collection_report)
      end

      # Extract font name from font object
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font object
      # @param index [Integer] Font index (fallback)
      # @return [String] Font name
      def extract_font_name(font, index)
        return "Font #{index}" unless font.respond_to?(:table)

        name_table = font.table("name")
        return "Font #{index}" unless name_table

        full_name = name_table.english_name(Tables::Name::FULL_NAME)
        return full_name if full_name && !full_name.empty?

        postscript_name = name_table.english_name(Tables::Name::POSTSCRIPT_NAME)
        return postscript_name if postscript_name && !postscript_name.empty?

        "Font #{index}"
      end

      # Calculate exit code for collection validation
      #
      # Uses worst status across all fonts
      #
      # @param report [CollectionValidationReport] Collection report
      # @return [Integer] Exit code
      def collection_exit_code(report)
        return 0 unless @return_value_results

        # Check for fatal errors first
        return 2 if report.font_reports.any? do |fr|
          fr.report.fatal_errors.any?
        end
        # Then check for errors
        return 3 if report.font_reports.any? { |fr| fr.report.errors_only.any? }
        # Then check for warnings
        return 4 if report.font_reports.any? do |fr|
          fr.report.warnings_only.any?
        end
        # Then check for info
        return 5 if report.font_reports.any? { |fr| fr.report.info_only.any? }

        0
      end

      # Generate output based on requested format
      #
      # @param report [ValidationReport] The validation report
      # @return [String] Formatted output
      def generate_output(report)
        if @table_report
          report.to_table_format
        elsif @summary_report
          report.to_summary
        elsif @full_report
          report.to_text_report
        else
          # Default: format-specific output
          case @format
          when :yaml
            require "yaml"
            report.to_yaml
          when :json
            require "json"
            report.to_json
          else
            report.text_summary
          end
        end
      end

      # Determine exit code based on validation results
      #
      # Exit codes (ftxvalidator compatible):
      #   0 = No issues found
      #   1 = Execution errors
      #   2 = Fatal errors found
      #   3 = Major errors found
      #   4 = Minor errors (warnings) found
      #   5 = Spec violations (info) found
      #
      # @param report [ValidationReport] The validation report
      # @return [Integer] Exit code
      def exit_code(report)
        return 0 unless @return_value_results

        return 2 if report.fatal_errors.any?
        return 3 if report.errors_only.any?
        return 4 if report.warnings_only.any?
        return 5 if report.info_only.any?

        0
      end
    end
  end
end
