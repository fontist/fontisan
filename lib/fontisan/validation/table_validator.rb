# frozen_string_literal: true

require "yaml"

module Fontisan
  module Validation
    # TableValidator validates the presence and correctness of font tables
    #
    # This validator checks that all required tables are present in the font
    # based on the font type (TrueType, OpenType/CFF, Variable) and validates
    # table-specific properties like versioning.
    #
    # Single Responsibility: Table presence and table-level validation
    #
    # @example Validating tables
    #   validator = TableValidator.new(rules)
    #   issues = validator.validate(font)
    class TableValidator
      # Initialize table validator
      #
      # @param rules [Hash] Validation rules configuration
      def initialize(rules)
        @rules = rules
        @required_tables = rules["required_tables"]
      end

      # Validate font tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font to validate
      # @return [Array<Hash>] Array of validation issues
      def validate(font)
        issues = []

        # Determine font type
        font_type = determine_font_type(font)

        # Check required tables based on font type
        issues.concat(check_required_tables(font, font_type))

        # Check table-specific validations if tables exist
        issues.concat(check_table_versions(font)) if @rules["check_table_versions"]

        issues
      end

      private

      # Determine the font type
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @return [Symbol] :truetype, :opentype_cff, or :variable
      def determine_font_type(font)
        if font.has_table?(Constants::FVAR_TAG)
          :variable
        elsif font.has_table?(Constants::CFF_TAG) || font.has_table?("CFF2")
          :opentype_cff
        else
          :truetype
        end
      end

      # Check that required tables are present
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @param font_type [Symbol] The font type
      # @return [Array<Hash>] Array of missing table issues
      def check_required_tables(font, font_type)
        issues = []

        # Get required tables for this font type
        required = @required_tables["all"].dup

        case font_type
        when :truetype
          required.concat(@required_tables["truetype"])
        when :opentype_cff
          required.concat(@required_tables["opentype_cff"])
        when :variable
          required.concat(@required_tables["variable"])
        end

        # Check each required table
        required.each do |table_tag|
          next if font.has_table?(table_tag)

          # Special case: CFF or CFF2 are alternatives
          if (table_tag == Constants::CFF_TAG) && font.has_table?("CFF2")
            next
          end

          issues << {
            severity: "error",
            category: "tables",
            message: "Missing required table: #{table_tag}",
            location: nil,
          }
        end

        issues
      end

      # Check table version compatibility
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @return [Array<Hash>] Array of version issues
      def check_table_versions(font)
        issues = []

        # Check head table version
        if font.has_table?(Constants::HEAD_TAG)
          head = font.table(Constants::HEAD_TAG)
          unless valid_head_version?(head)
            issues << {
              severity: "warning",
              category: "tables",
              message: "Unsupported head table version: #{head.major_version}.#{head.minor_version}",
              location: Constants::HEAD_TAG,
            }
          end
        end

        # Check maxp table version
        if font.has_table?(Constants::MAXP_TAG)
          maxp = font.table(Constants::MAXP_TAG)
          unless valid_maxp_version?(maxp)
            issues << {
              severity: "warning",
              category: "tables",
              message: "Unsupported maxp table version: #{maxp.version}",
              location: Constants::MAXP_TAG,
            }
          end
        end

        issues
      end

      # Check if head table version is valid
      #
      # @param head [Tables::Head] The head table
      # @return [Boolean] true if version is valid
      def valid_head_version?(head)
        # Head table version should be 1.0
        head.major_version == 1 && head.minor_version.zero?
      end

      # Check if maxp table version is valid
      #
      # @param maxp [Tables::Maxp] The maxp table
      # @return [Boolean] true if version is valid
      def valid_maxp_version?(maxp)
        # Version 0.5 for CFF fonts, 1.0 for TrueType fonts
        version = maxp.version
        [0x00005000, 0x00010000].include?(version)
      end
    end
  end
end
