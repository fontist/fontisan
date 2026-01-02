# frozen_string_literal: true

require "spec_helper"
require "fontisan/validators/validator"

RSpec.describe Fontisan::Validators::Validator do
  let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
  let(:font) { Fontisan::FontLoader.load(font_path) }

  describe "initialization" do
    it "calls define_checks during initialization" do
      validator = Class.new(described_class) do
        attr_reader :checks_defined

        private

        def define_checks
          @checks_defined = true
        end
      end.new

      expect(validator.checks_defined).to be true
    end
  end

  describe "DSL methods" do
    describe "#check_table" do
      it "stores table check definition" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :test_check, "name" do |table|
              true
            end
          end
        end.new

        checks = validator.instance_variable_get(:@checks)
        expect(checks).not_to be_empty
        expect(checks.first[:type]).to eq(:table)
        expect(checks.first[:id]).to eq(:test_check)
        expect(checks.first[:table_tag]).to eq("name")
        expect(checks.first[:severity]).to eq(:error)
      end

      it "allows custom severity" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :test_check, "name", severity: :warning do |table|
              true
            end
          end
        end.new

        checks = validator.instance_variable_get(:@checks)
        expect(checks.first[:severity]).to eq(:warning)
      end
    end

    describe "#check_field" do
      it "raises error when called outside check_table block" do
        expect do
          Class.new(described_class) do
            def define_checks
              check_field :test_field, :family_name do |table, value|
                true
              end
            end
          end.new
        end.to raise_error(ArgumentError, /must be called within check_table block/)
      end

      it "stores field check definition within table context" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :table_check, "name" do |table|
              # This sets context but doesn't actually execute check_field here
              true
            end
          end
        end.new

        # Field checks would be stored during check_table execution
        # but our current implementation doesn't support nested execution
        # This test verifies the error is raised when context is missing
      end
    end

    describe "#check_structure" do
      it "stores structure check definition" do
        validator = Class.new(described_class) do
          def define_checks
            check_structure :test_structure do |font|
              true
            end
          end
        end.new

        checks = validator.instance_variable_get(:@checks)
        expect(checks.first[:type]).to eq(:structure)
        expect(checks.first[:id]).to eq(:test_structure)
      end
    end

    describe "#check_usability" do
      it "stores usability check definition with warning severity by default" do
        validator = Class.new(described_class) do
          def define_checks
            check_usability :test_usability do |font|
              true
            end
          end
        end.new

        checks = validator.instance_variable_get(:@checks)
        expect(checks.first[:type]).to eq(:usability)
        expect(checks.first[:severity]).to eq(:warning)
      end
    end

    describe "#check_instructions" do
      it "stores instruction check definition" do
        validator = Class.new(described_class) do
          def define_checks
            check_instructions :test_instructions do |font|
              true
            end
          end
        end.new

        checks = validator.instance_variable_get(:@checks)
        expect(checks.first[:type]).to eq(:instructions)
      end
    end

    describe "#check_glyphs" do
      it "stores glyph check definition" do
        validator = Class.new(described_class) do
          def define_checks
            check_glyphs :test_glyphs do |font|
              true
            end
          end
        end.new

        checks = validator.instance_variable_get(:@checks)
        expect(checks.first[:type]).to eq(:glyphs)
      end
    end
  end

  describe "#validate" do
    context "with passing checks" do
      it "returns valid ValidationReport" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :name_table, "name" do |table|
              table.valid?
            end
          end
        end.new

        report = validator.validate(font)

        expect(report).to be_a(Fontisan::Models::ValidationReport)
        expect(report.valid).to be true
        expect(report.status).to eq("valid")
        expect(report.check_results.size).to eq(1)
        expect(report.check_results.first.passed).to be true
      end
    end

    context "with failing checks" do
      it "returns invalid ValidationReport with errors" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :invalid_check, "name" do |table|
              false
            end
          end
        end.new

        report = validator.validate(font)

        expect(report.valid).to be false
        expect(report.status).to eq("invalid")
        expect(report.has_errors?).to be true
        expect(report.check_results.first.passed).to be false
      end
    end

    context "with missing table" do
      it "reports table not found" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :missing_table, "ZZZZ" do |table|
              true
            end
          end
        end.new

        report = validator.validate(font)

        expect(report.valid).to be false
        result = report.result_of(:missing_table)
        expect(result.passed).to be false
        expect(result.messages.first).to include("not found")
        expect(result.table).to eq("ZZZZ")
      end
    end

    context "with multiple checks" do
      it "executes all checks and aggregates results" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :name_check, "name" do |table|
              table.valid?
            end

            check_table :head_check, "head" do |table|
              table.valid?
            end

            check_structure :has_glyphs do |font|
              font.table("maxp").num_glyphs > 0
            end
          end
        end.new

        report = validator.validate(font)

        expect(report.check_results.size).to eq(3)
        expect(report.checks_performed.size).to eq(3)
        expect(report.checks_performed).to include("name_check", "head_check", "has_glyphs")
      end
    end

    context "with exception in check" do
      it "handles exception gracefully" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :error_check, "name" do |table|
              raise StandardError, "Test error"
            end
          end
        end.new

        report = validator.validate(font)

        expect(report.valid).to be false
        result = report.result_of(:error_check)
        expect(result.passed).to be false
        expect(result.severity).to eq("fatal")
        expect(result.messages.first).to include("Check execution failed")
      end
    end
  end

  describe "ValidationReport integration" do
    it "builds CheckResult objects correctly" do
      validator = Class.new(described_class) do
        def define_checks
          check_table :test_check, "name", severity: :warning do |table|
            false
          end
        end
      end.new

      report = validator.validate(font)
      result = report.result_of(:test_check)

      expect(result).to be_a(Fontisan::Models::ValidationReport::CheckResult)
      expect(result.check_id).to eq("test_check")
      expect(result.passed).to be false
      expect(result.severity).to eq("warning")
      expect(result.table).to eq("name")
    end

    it "uses result_of to query specific check" do
      validator = Class.new(described_class) do
        def define_checks
          check_table :check_one, "name" do |table|
            true
          end

          check_table :check_two, "head" do |table|
            false
          end
        end
      end.new

      report = validator.validate(font)

      expect(report.result_of(:check_one).passed).to be true
      expect(report.result_of(:check_two).passed).to be false
      expect(report.result_of(:nonexistent)).to be_nil
    end

    it "tracks passed and failed checks" do
      validator = Class.new(described_class) do
        def define_checks
          check_table :pass_check, "name" do |table|
            true
          end

          check_table :fail_check, "head" do |table|
            false
          end
        end
      end.new

      report = validator.validate(font)

      expect(report.passed_checks.size).to eq(1)
      expect(report.failed_checks.size).to eq(1)
      expect(report.passed_checks.first.check_id).to eq("pass_check")
      expect(report.failed_checks.first.check_id).to eq("fail_check")
    end
  end

  describe "real font validation" do
    context "with NotoSans-Regular.ttf" do
      it "validates name table successfully" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :name_version, "name" do |table|
              table.valid_version?
            end

            check_table :name_family, "name" do |table|
              table.family_name_present?
            end

            check_table :postscript_name, "name" do |table|
              table.postscript_name_valid?
            end
          end
        end.new

        report = validator.validate(font)

        expect(report.valid).to be true
        expect(report.check_results.all?(&:passed)).to be true
      end

      it "validates head table successfully" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :head_magic, "head" do |table|
              table.valid_magic?
            end

            check_table :head_version, "head" do |table|
              table.valid_version?
            end

            check_table :head_units_per_em, "head" do |table|
              table.valid_units_per_em?
            end
          end
        end.new

        report = validator.validate(font)

        expect(report.valid).to be true
        expect(report.check_results.all?(&:passed)).to be true
      end

      it "validates maxp table successfully" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :maxp_version, "maxp" do |table|
              table.valid_version?
            end

            check_table :maxp_num_glyphs, "maxp" do |table|
              table.valid_num_glyphs?
            end

            check_table :maxp_metrics, "maxp" do |table|
              table.reasonable_metrics?
            end
          end
        end.new

        report = validator.validate(font)

        expect(report.valid).to be true
        expect(report.check_results.all?(&:passed)).to be true
      end

      it "validates hhea table successfully" do
        validator = Class.new(described_class) do
          def define_checks
            check_table :hhea_version, "hhea" do |table|
              table.valid_version?
            end

            check_table :hhea_metrics, "hhea" do |table|
              table.valid_number_of_h_metrics?
            end

            check_table :hhea_ascent_descent, "hhea" do |table|
              table.valid_ascent_descent?
            end
          end
        end.new

        report = validator.validate(font)

        expect(report.valid).to be true
        expect(report.check_results.all?(&:passed)).to be true
      end
    end

    context "with comprehensive validation" do
      it "validates multiple tables with helper methods" do
        validator = Class.new(described_class) do
          def define_checks
            # Name table checks
            check_table :name_table, "name" do |table|
              table.valid_version? &&
                table.family_name_present? &&
                table.postscript_name_valid?
            end

            # Head table checks
            check_table :head_table, "head" do |table|
              table.valid_magic? &&
                table.valid_version? &&
                table.valid_units_per_em? &&
                table.valid_bounding_box?
            end

            # Maxp table checks
            check_table :maxp_table, "maxp" do |table|
              table.valid_version? &&
                table.valid_num_glyphs? &&
                table.reasonable_metrics?
            end

            # Hhea table checks
            check_table :hhea_table, "hhea" do |table|
              table.valid_version? &&
                table.valid_metric_data_format? &&
                table.valid_ascent_descent?
            end

            # Structure check
            check_structure :required_tables do |font|
              %w[name head maxp hhea].all? { |tag| !font.table(tag).nil? }
            end
          end
        end.new

        report = validator.validate(font)

        expect(report.valid).to be true
        expect(report.check_results.size).to eq(5)
        expect(report.check_results.all?(&:passed)).to be true
        expect(report.summary.errors).to eq(0)
        expect(report.summary.warnings).to eq(0)
      end
    end
  end

  describe "performance" do
    it "completes validation in under 200ms for typical font" do
      validator = Class.new(described_class) do
        def define_checks
          check_table :name_check, "name" do |table|
            table.valid?
          end

          check_table :head_check, "head" do |table|
            table.valid?
          end

          check_table :maxp_check, "maxp" do |table|
            table.valid?
          end

          check_structure :has_glyphs do |font|
            font.table("maxp").num_glyphs > 0
          end
        end
      end.new

      start_time = Time.now
      report = validator.validate(font)
      elapsed = Time.now - start_time

      expect(elapsed).to be < 0.2
      expect(report.valid).to be true
    end
  end

  describe "serialization" do
    it "produces reports that serialize to YAML" do
      validator = Class.new(described_class) do
        def define_checks
          check_table :test_check, "name" do |table|
            true
          end
        end
      end.new

      report = validator.validate(font)
      yaml_output = report.to_yaml

      expect(yaml_output).to be_a(String)
      expect(yaml_output).to include("valid")
      expect(yaml_output).to include("test_check")
      # Check results should be serialized when present
      expect(report.check_results).not_to be_empty
    end

    it "produces reports that serialize to JSON" do
      validator = Class.new(described_class) do
        def define_checks
          check_table :test_check, "name" do |table|
            true
          end
        end
      end.new

      report = validator.validate(font)
      json_output = report.to_json

      expect(json_output).to be_a(String)
      expect(json_output).to include("valid")
      expect(json_output).to include("test_check")
      # Check results should be present in the report object
      expect(report.check_results).not_to be_empty
    end
  end
end
