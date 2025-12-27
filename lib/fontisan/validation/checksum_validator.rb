# frozen_string_literal: true

require_relative "../utilities/checksum_calculator"

module Fontisan
  module Validation
    # ChecksumValidator validates font file and table checksums
    #
    # This validator checks that the head table checksum adjustment is correct
    # and validates individual table checksums to ensure file integrity.
    #
    # Single Responsibility: Checksum validation and file integrity
    #
    # @example Validating checksums
    #   validator = ChecksumValidator.new(rules)
    #   issues = validator.validate(font, font_path)
    class ChecksumValidator
      # Initialize checksum validator
      #
      # @param rules [Hash] Validation rules configuration
      def initialize(rules)
        @rules = rules
        @checksum_config = rules["checksum_validation"] || {}
      end

      # Validate font checksums
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font to validate
      # @param font_path [String] Path to the font file
      # @return [Array<Hash>] Array of validation issues
      def validate(font, font_path)
        issues = []

        # Check head table checksum adjustment if enabled
        if should_check?("check_head_checksum_adjustment")
          issues.concat(check_head_checksum_adjustment(font, font_path))
        end

        # Check individual table checksums if enabled
        if should_check?("check_table_checksums")
          issues.concat(check_table_checksums(font))
        end

        issues
      end

      private

      # Check if a validation should be performed
      #
      # @param check_name [String] The check name
      # @return [Boolean] true if check should be performed
      def should_check?(check_name)
        @rules.dig("validation_levels", "standard", check_name)
      end

      # Check head table checksum adjustment
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @param font_path [String] Path to the font file
      # @return [Array<Hash>] Array of checksum issues
      def check_head_checksum_adjustment(font, font_path)
        issues = []

        head_entry = font.head_table
        return issues unless head_entry

        # Calculate the checksum of the entire font file
        begin
          file_checksum = Utilities::ChecksumCalculator.calculate_file_checksum(font_path)
          magic = @checksum_config["magic"] || Constants::CHECKSUM_ADJUSTMENT_MAGIC

          # Read the actual checksum adjustment from head table
          head_data = font.table_data[Constants::HEAD_TAG]
          return issues unless head_data && head_data.bytesize >= 12

          actual_adjustment = head_data.byteslice(8, 4).unpack1("N")

          # The actual adjustment should be 0 when we calculate, since we zero it out
          # So we need to check if the file checksum with zeroed adjustment equals magic
          if file_checksum != magic
            # Calculate what the adjustment should be
            temp_checksum = (file_checksum - actual_adjustment) & 0xFFFFFFFF
            correct_adjustment = (magic - temp_checksum) & 0xFFFFFFFF

            if actual_adjustment != correct_adjustment
              issues << {
                severity: "error",
                category: "checksum",
                message: "Invalid head table checksum adjustment (expected: 0x#{correct_adjustment.to_s(16)}, got: 0x#{actual_adjustment.to_s(16)})",
                location: "head table",
              }
            end
          end
        rescue StandardError => e
          issues << {
            severity: "error",
            category: "checksum",
            message: "Failed to validate head checksum adjustment: #{e.message}",
            location: "head table",
          }
        end

        issues
      end

      # Check individual table checksums
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @return [Array<Hash>] Array of table checksum issues
      def check_table_checksums(font)
        issues = []

        skip_tables = @checksum_config["skip_tables"] || []

        font.tables.each do |table_entry|
          tag = table_entry.tag.to_s  # Convert BinData field to string

          # Skip tables that are exempt from checksum validation
          next if skip_tables.include?(tag)

          # Get table data
          table_data = font.table_data[tag]
          next unless table_data

          # Calculate checksum for the table
          calculated_checksum = calculate_table_checksum(table_data)
          declared_checksum = table_entry.checksum.to_i  # Convert BinData field to integer

          # Special handling for head table (checksum adjustment field should be 0)
          if tag == Constants::HEAD_TAG
            # Zero out checksum adjustment field for calculation
            modified_data = table_data.dup
            modified_data[8, 4] = "\x00\x00\x00\x00"
            calculated_checksum = calculate_table_checksum(modified_data)
          end

          if calculated_checksum != declared_checksum
            issues << {
              severity: "warning",
              category: "checksum",
              message: "Table '#{tag}' checksum mismatch (expected: 0x#{declared_checksum.to_s(16)}, got: 0x#{calculated_checksum.to_s(16)})",
              location: "#{tag} table",
            }
          end
        end

        issues
      end

      # Calculate checksum for table data
      #
      # @param data [String] The table data
      # @return [Integer] The calculated checksum
      def calculate_table_checksum(data)
        sum = 0
        # Pad to 4-byte boundary
        padded_data = data + ("\x00" * ((4 - (data.bytesize % 4)) % 4))

        # Sum all 32-bit values
        (0...padded_data.bytesize).step(4) do |i|
          value = padded_data.byteslice(i, 4).unpack1("N")
          sum = (sum + value) & 0xFFFFFFFF
        end

        sum
      end
    end
  end
end
