# frozen_string_literal: true

module Fontisan
  module Validation
    # Woff2HeaderValidator validates the WOFF2 header structure
    #
    # This validator checks the WOFF2 header for:
    # - Valid signature (0x774F4632 'wOF2')
    # - Valid flavor (TrueType or CFF)
    # - Reserved field is zero
    # - File length consistency
    # - Valid table count
    # - Valid compressed size
    # - Metadata offset/length consistency
    # - Private data offset/length consistency
    #
    # Single Responsibility: WOFF2 header validation
    #
    # @example Validating a WOFF2 header
    #   validator = Woff2HeaderValidator.new(rules)
    #   issues = validator.validate(woff2_font)
    class Woff2HeaderValidator
      # Valid WOFF2 flavors
      VALID_FLAVORS = [
        0x00010000, # TrueType
        0x74727565, # 'true' (TrueType)
        0x4F54544F, # 'OTTO' (CFF/OpenType)
      ].freeze

      # Initialize WOFF2 header validator
      #
      # @param rules [Hash] Validation rules configuration
      def initialize(rules)
        @rules = rules
        @woff2_config = rules["woff2_validation"] || {}
      end

      # Validate WOFF2 header
      #
      # @param woff2_font [Woff2Font] The WOFF2 font to validate
      # @return [Array<Hash>] Array of validation issues
      def validate(woff2_font)
        issues = []

        header = woff2_font.header
        return issues unless header

        # Check signature
        issues.concat(check_signature(header))

        # Check flavor
        issues.concat(check_flavor(header))

        # Check reserved field
        issues.concat(check_reserved_field(header))

        # Check table count
        issues.concat(check_table_count(header, woff2_font))

        # Check compressed size
        issues.concat(check_compressed_size(header))

        # Check metadata consistency
        issues.concat(check_metadata(header))

        # Check private data consistency
        issues.concat(check_private_data(header))

        issues
      end

      private

      # Check signature validity
      #
      # @param header [Woff2::Woff2Header] The header
      # @return [Array<Hash>] Array of signature issues
      def check_signature(header)
        issues = []

        unless header.signature == Woff2::Woff2Header::SIGNATURE
          issues << {
            severity: "error",
            category: "woff2_header",
            message: "Invalid WOFF2 signature: expected 0x#{Woff2::Woff2Header::SIGNATURE.to_s(16)}, " \
                     "got 0x#{header.signature.to_s(16)}",
            location: "header",
          }
        end

        issues
      end

      # Check flavor validity
      #
      # @param header [Woff2::Woff2Header] The header
      # @return [Array<Hash>] Array of flavor issues
      def check_flavor(header)
        issues = []

        unless VALID_FLAVORS.include?(header.flavor)
          issues << {
            severity: "error",
            category: "woff2_header",
            message: "Invalid WOFF2 flavor: 0x#{header.flavor.to_s(16)} " \
                     "(expected TrueType 0x00010000 or CFF 0x4F54544F)",
            location: "header",
          }
        end

        issues
      end

      # Check reserved field
      #
      # @param header [Woff2::Woff2Header] The header
      # @return [Array<Hash>] Array of reserved field issues
      def check_reserved_field(header)
        issues = []

        if header.reserved != 0
          issues << {
            severity: "warning",
            category: "woff2_header",
            message: "Reserved field should be 0, got #{header.reserved}",
            location: "header",
          }
        end

        issues
      end

      # Check table count validity
      #
      # @param header [Woff2::Woff2Header] The header
      # @param woff2_font [Woff2Font] The WOFF2 font
      # @return [Array<Hash>] Array of table count issues
      def check_table_count(header, woff2_font)
        issues = []

        if header.num_tables.zero?
          issues << {
            severity: "error",
            category: "woff2_header",
            message: "Number of tables cannot be zero",
            location: "header",
          }
        end

        # Check consistency with actual table entries
        actual_count = woff2_font.table_entries.length
        if header.num_tables != actual_count
          issues << {
            severity: "error",
            category: "woff2_header",
            message: "Table count mismatch: header=#{header.num_tables}, actual=#{actual_count}",
            location: "header",
          }
        end

        issues
      end

      # Check compressed size validity
      #
      # @param header [Woff2::Woff2Header] The header
      # @return [Array<Hash>] Array of compressed size issues
      def check_compressed_size(header)
        issues = []

        if header.total_compressed_size.zero?
          issues << {
            severity: "error",
            category: "woff2_header",
            message: "Total compressed size cannot be zero",
            location: "header",
          }
        end

        # Check compression ratio
        if header.total_sfnt_size.positive? && header.total_compressed_size.positive?
          ratio = header.total_compressed_size.to_f / header.total_sfnt_size
          min_ratio = @woff2_config["min_compression_ratio"] || 0.2
          max_ratio = @woff2_config["max_compression_ratio"] || 0.95

          if ratio < min_ratio
            issues << {
              severity: "warning",
              category: "woff2_header",
              message: "Compression ratio (#{(ratio * 100).round(2)}%) is unusually low",
              location: "header",
            }
          elsif ratio > max_ratio
            issues << {
              severity: "warning",
              category: "woff2_header",
              message: "Compression ratio (#{(ratio * 100).round(2)}%) is unusually high",
              location: "header",
            }
          end
        end

        issues
      end

      # Check metadata consistency
      #
      # @param header [Woff2::Woff2Header] The header
      # @return [Array<Hash>] Array of metadata issues
      def check_metadata(header)
        issues = []

        # If metadata offset is set, length must be positive
        if header.meta_offset.positive? && header.meta_length.zero?
          issues << {
            severity: "warning",
            category: "woff2_header",
            message: "Metadata offset is set but length is zero",
            location: "header",
          }
        end

        # If metadata length is set, offset must be positive
        if header.meta_length.positive? && header.meta_offset.zero?
          issues << {
            severity: "warning",
            category: "woff2_header",
            message: "Metadata length is set but offset is zero",
            location: "header",
          }
        end

        # Original length should be >= compressed length
        if header.meta_orig_length.positive? && header.meta_length.positive? && (header.meta_orig_length < header.meta_length)
          issues << {
            severity: "error",
            category: "woff2_header",
            message: "Metadata original length (#{header.meta_orig_length}) " \
                     "is less than compressed length (#{header.meta_length})",
            location: "header",
          }
        end

        issues
      end

      # Check private data consistency
      #
      # @param header [Woff2::Woff2Header] The header
      # @return [Array<Hash>] Array of private data issues
      def check_private_data(header)
        issues = []

        # If private offset is set, length must be positive
        if header.priv_offset.positive? && header.priv_length.zero?
          issues << {
            severity: "warning",
            category: "woff2_header",
            message: "Private data offset is set but length is zero",
            location: "header",
          }
        end

        # If private length is set, offset must be positive
        if header.priv_length.positive? && header.priv_offset.zero?
          issues << {
            severity: "warning",
            category: "woff2_header",
            message: "Private data length is set but offset is zero",
            location: "header",
          }
        end

        issues
      end
    end
  end
end
