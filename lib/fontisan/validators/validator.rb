# frozen_string_literal: true

require_relative "../models/validation_report"

module Fontisan
  module Validators
    # Base class for all validators using block-based DSL
    #
    # This class provides a declarative DSL for defining validation checks
    # and an execution engine that runs those checks against font files.
    # Subclasses define their validation logic by implementing define_checks.
    #
    # @example Creating a custom validator
    #   class MyValidator < Validator
    #     private
    #
    #     def define_checks
    #       check_table :name_table, 'name' do
    #         check_field :family_name, :family_name do |table, value|
    #           !value.nil? && !value.empty?
    #         end
    #       end
    #     end
    #   end
    #
    # @example Running validation
    #   validator = MyValidator.new
    #   report = validator.validate(font)
    #   puts report.valid?
    class Validator
      # Initialize validator and define checks
      def initialize
        @checks = []
        @current_table_context = nil
        define_checks
      end

      # Validate a font and return a ValidationReport
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font object to validate
      # @return [ValidationReport] Complete validation report
      def validate(font)
        start_time = Time.now
        all_results = []

        @checks.each do |check_def|
          result = execute_check(font, check_def)
          all_results << result
        end

        elapsed = Time.now - start_time
        build_report(font, all_results, elapsed)
      end

      protected

      # DSL method: Define a table-level check
      #
      # @param check_id [Symbol] Unique identifier for this check
      # @param table_tag [String] OpenType table tag (e.g., 'name', 'head')
      # @param severity [Symbol] Severity level (:info, :warning, :error, :fatal)
      # @param block [Proc] Check logic that receives table as parameter
      def check_table(check_id, table_tag, severity: :error, &block)
        @checks << {
          type: :table,
          id: check_id,
          table_tag: table_tag,
          severity: severity,
          block: block,
        }
      end

      # DSL method: Define a field-level check
      #
      # Must be called within a check_table block to establish table context
      #
      # @param check_id [Symbol] Unique identifier for this check
      # @param field_key [Symbol] Field name to check
      # @param severity [Symbol] Severity level (:info, :warning, :error, :fatal)
      # @param block [Proc] Check logic that receives (table, value) as parameters
      def check_field(check_id, field_key, severity: :error, &block)
        unless @current_table_context
          raise ArgumentError, "check_field must be called within check_table block"
        end

        @checks << {
          type: :field,
          id: check_id,
          table_tag: @current_table_context,
          field: field_key,
          severity: severity,
          block: block,
        }
      end

      # DSL method: Define a structural validation check
      #
      # Used for checks that validate font structure and relationships
      #
      # @param check_id [Symbol] Unique identifier for this check
      # @param severity [Symbol] Severity level (:info, :warning, :error, :fatal)
      # @param block [Proc] Check logic that receives font as parameter
      def check_structure(check_id, severity: :error, &block)
        @checks << {
          type: :structure,
          id: check_id,
          severity: severity,
          block: block,
        }
      end

      # DSL method: Define a usability check
      #
      # Used for checks that validate font usability and best practices
      #
      # @param check_id [Symbol] Unique identifier for this check
      # @param severity [Symbol] Severity level (:info, :warning, :error, :fatal)
      # @param block [Proc] Check logic that receives font as parameter
      def check_usability(check_id, severity: :warning, &block)
        @checks << {
          type: :usability,
          id: check_id,
          severity: severity,
          block: block,
        }
      end

      # DSL method: Define an instruction validation check
      #
      # Used for checks that validate TrueType instructions/hinting
      #
      # @param check_id [Symbol] Unique identifier for this check
      # @param severity [Symbol] Severity level (:info, :warning, :error, :fatal)
      # @param block [Proc] Check logic that receives font as parameter
      def check_instructions(check_id, severity: :warning, &block)
        @checks << {
          type: :instructions,
          id: check_id,
          severity: severity,
          block: block,
        }
      end

      # DSL method: Define a glyph-level check
      #
      # Used for checks that validate individual glyphs
      #
      # @param check_id [Symbol] Unique identifier for this check
      # @param severity [Symbol] Severity level (:info, :warning, :error, :fatal)
      # @param block [Proc] Check logic that receives font as parameter
      def check_glyphs(check_id, severity: :error, &block)
        @checks << {
          type: :glyphs,
          id: check_id,
          severity: severity,
          block: block,
        }
      end

      private

      # Template method: Subclasses implement this to define their checks
      #
      # @return [void]
      def define_checks
        # Subclasses override this method
      end

      # Execute a single check using strategy pattern
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param check_def [Hash] Check definition
      # @return [Hash] Check result with :passed, :severity, :messages, :issues
      def execute_check(font, check_def)
        case check_def[:type]
        when :table
          execute_table_check(font, check_def)
        when :field
          execute_field_check(font, check_def)
        when :structure
          execute_structure_check(font, check_def)
        when :usability
          execute_usability_check(font, check_def)
        when :instructions
          execute_instruction_check(font, check_def)
        when :glyphs
          execute_glyph_check(font, check_def)
        else
          {
            check_id: check_def[:id],
            passed: false,
            severity: :fatal,
            messages: ["Unknown check type: #{check_def[:type]}"],
            issues: [],
          }
        end
      rescue => e
        {
          check_id: check_def[:id],
          passed: false,
          severity: :fatal,
          messages: ["Check execution failed: #{e.message}"],
          issues: [{
            severity: "fatal",
            category: "check_execution",
            message: "Exception during check execution: #{e.class} - #{e.message}",
          }],
        }
      end

      # Execute a table-level check
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param check_def [Hash] Check definition
      # @return [Hash] Check result
      def execute_table_check(font, check_def)
        table_tag = check_def[:table_tag]
        table = font.table(table_tag)

        unless table
          return {
            check_id: check_def[:id],
            passed: false,
            severity: check_def[:severity].to_s,
            messages: ["Table '#{table_tag}' not found in font"],
            table: table_tag,
            issues: [{
              severity: check_def[:severity].to_s,
              category: "table_presence",
              table: table_tag,
              message: "Required table '#{table_tag}' is missing",
            }],
          }
        end

        # Set context for nested field checks
        old_context = @current_table_context
        @current_table_context = table_tag

        begin
          result = check_def[:block].call(table)
          passed = result != false && result != nil

          {
            check_id: check_def[:id],
            passed: passed,
            severity: check_def[:severity].to_s,
            messages: passed ? [] : ["Table '#{table_tag}' validation failed"],
            table: table_tag,
            issues: passed ? [] : [{
              severity: check_def[:severity].to_s,
              category: "table_validation",
              table: table_tag,
              message: "Table '#{table_tag}' failed validation",
            }],
          }
        ensure
          @current_table_context = old_context
        end
      end

      # Execute a field-level check
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param check_def [Hash] Check definition
      # @return [Hash] Check result
      def execute_field_check(font, check_def)
        table_tag = check_def[:table_tag]
        field_key = check_def[:field]
        table = font.table(table_tag)

        unless table
          return {
            check_id: check_def[:id],
            passed: false,
            severity: check_def[:severity].to_s,
            messages: ["Table '#{table_tag}' not found"],
            table: table_tag,
            field: field_key.to_s,
            issues: [{
              severity: check_def[:severity].to_s,
              category: "table_presence",
              table: table_tag,
              field: field_key.to_s,
              message: "Cannot validate field '#{field_key}': table '#{table_tag}' missing",
            }],
          }
        end

        # Get field value
        value = if table.respond_to?(field_key)
                  table.public_send(field_key)
                else
                  nil
                end

        result = check_def[:block].call(table, value)
        passed = result != false && result != nil

        {
          check_id: check_def[:id],
          passed: passed,
          severity: check_def[:severity].to_s,
          messages: passed ? [] : ["Field '#{field_key}' validation failed"],
          table: table_tag,
          field: field_key.to_s,
          issues: passed ? [] : [{
            severity: check_def[:severity].to_s,
            category: "field_validation",
            table: table_tag,
            field: field_key.to_s,
            message: "Field '#{field_key}' in table '#{table_tag}' failed validation",
          }],
        }
      end

      # Execute a structure check
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param check_def [Hash] Check definition
      # @return [Hash] Check result
      def execute_structure_check(font, check_def)
        result = check_def[:block].call(font)
        passed = result != false && result != nil

        {
          check_id: check_def[:id],
          passed: passed,
          severity: check_def[:severity].to_s,
          messages: passed ? [] : ["Structure validation failed"],
          issues: passed ? [] : [{
            severity: check_def[:severity].to_s,
            category: "structure",
            message: "Font structure validation failed for check '#{check_def[:id]}'",
          }],
        }
      end

      # Execute a usability check
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param check_def [Hash] Check definition
      # @return [Hash] Check result
      def execute_usability_check(font, check_def)
        result = check_def[:block].call(font)
        passed = result != false && result != nil

        {
          check_id: check_def[:id],
          passed: passed,
          severity: check_def[:severity].to_s,
          messages: passed ? [] : ["Usability check failed"],
          issues: passed ? [] : [{
            severity: check_def[:severity].to_s,
            category: "usability",
            message: "Font usability check failed for '#{check_def[:id]}'",
          }],
        }
      end

      # Execute an instruction check
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param check_def [Hash] Check definition
      # @return [Hash] Check result
      def execute_instruction_check(font, check_def)
        result = check_def[:block].call(font)
        passed = result != false && result != nil

        {
          check_id: check_def[:id],
          passed: passed,
          severity: check_def[:severity].to_s,
          messages: passed ? [] : ["Instruction validation failed"],
          issues: passed ? [] : [{
            severity: check_def[:severity].to_s,
            category: "instructions",
            message: "TrueType instruction check failed for '#{check_def[:id]}'",
          }],
        }
      end

      # Execute a glyph check
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param check_def [Hash] Check definition
      # @return [Hash] Check result
      def execute_glyph_check(font, check_def)
        result = check_def[:block].call(font)
        passed = result != false && result != nil

        {
          check_id: check_def[:id],
          passed: passed,
          severity: check_def[:severity].to_s,
          messages: passed ? [] : ["Glyph validation failed"],
          issues: passed ? [] : [{
            severity: check_def[:severity].to_s,
            category: "glyphs",
            message: "Glyph validation failed for check '#{check_def[:id]}'",
          }],
        }
      end

      # Build ValidationReport from check results
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font that was validated
      # @param all_results [Array<Hash>] All check results
      # @param elapsed [Float] Elapsed time in seconds
      # @return [ValidationReport] Complete report
      def build_report(font, all_results, elapsed)
        # Extract font path from font object
        font_path = if font.respond_to?(:path)
                      font.path
                    elsif font.respond_to?(:filename)
                      font.filename
                    elsif font.instance_variable_defined?(:@filename)
                      font.instance_variable_get(:@filename)
                    else
                      "unknown"
                    end

        report = Models::ValidationReport.new(
          font_path: font_path,
          valid: true,
        )

        # Build CheckResult objects
        all_results.each do |result|
          check_result = Models::ValidationReport::CheckResult.new(
            check_id: result[:check_id].to_s,
            passed: result[:passed],
            severity: result[:severity],
            messages: result[:messages] || [],
            table: result[:table],
            field: result[:field],
          )
          report.check_results << check_result

          # Add issues to main report
          if result[:issues]
            result[:issues].each do |issue_data|
              case issue_data[:severity]
              when "error", "fatal"
                report.add_error(
                  issue_data[:category] || "validation",
                  issue_data[:message],
                  issue_data[:table] || issue_data[:field],
                )
              when "warning"
                report.add_warning(
                  issue_data[:category] || "validation",
                  issue_data[:message],
                  issue_data[:table] || issue_data[:field],
                )
              when "info"
                report.add_info(
                  issue_data[:category] || "validation",
                  issue_data[:message],
                  issue_data[:table] || issue_data[:field],
                )
              end
            end
          end
        end

        # Mark checks performed
        report.checks_performed = all_results.map { |r| r[:check_id].to_s }

        # Set status based on results
        if report.has_errors?
          report.status = "invalid"
          report.valid = false
        elsif report.has_warnings?
          report.status = "valid_with_warnings"
        else
          report.status = "valid"
        end

        report
      end
    end
  end
end
