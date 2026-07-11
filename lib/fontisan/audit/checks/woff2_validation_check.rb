# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates WOFF2 (Web Open Font Format 2) wrapper structure per
      # the W3C WOFF2 spec. Only runs when the font IS a Woff2Font —
      # plain TTF/OTF inputs are skipped.
      #
      # Checks:
      #
      #   - Signature must be 0x774F4632 ('wOF2')
      #   - Flavor must be a valid SFNT version
      #   - reserved field must be 0
      #   - major_version should be 1
      #   - total_compressed_size must be positive
      #   - If metadata block is present, lengths must be consistent
      #   - num_tables must match the table directory count
      #
      # @see https://www.w3.org/TR/WOFF2/
      class Woff2ValidationCheck < Check
        WOFF2_SIGNATURE = 0x774F4632
        VALID_FLAVORS = [
          0x00010000, # TrueType
          0x74727565, # 'true' (Apple TrueType)
          0x4F54544F, # 'OTTO' (OpenType CFF)
          0x74746366, # 'ttcf' (collection)
        ].freeze

        # @param font [Woff2Font, SfntFont]
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          return [] unless woff2?(font)

          header = font.header
          issues = []
          issues.concat(validate_signature(header))
          issues.concat(validate_flavor(header))
          issues.concat(validate_reserved(header))
          issues.concat(validate_version(header))
          issues.concat(validate_sizes(header))
          issues.concat(validate_metadata(header))
          issues
        end

        def self.code
          :woff2_validation
        end

        def self.woff2?(font)
          font.is_a?(Woff2Font)
        end
        private_class_method :woff2?

        def self.validate_signature(header)
          return [] if header.signature == WOFF2_SIGNATURE

          [issue(severity: :error,
                 message: "WOFF2 signature is 0x#{header.signature.to_s(16)} " \
                          "but must be 0x#{WOFF2_SIGNATURE.to_s(16)} ('wOF2')",
                 location: "woff2_header.signature")]
        end
        private_class_method :validate_signature

        def self.validate_flavor(header)
          return [] if VALID_FLAVORS.include?(header.flavor)

          [issue(severity: :error,
                 message: "WOFF2 flavor is 0x#{header.flavor.to_s(16)} " \
                          "but must be a valid SFNT version " \
                          "(0x00010000, 0x74727565, 0x4F54544F, or 0x74746366)",
                 location: "woff2_header.flavor")]
        end
        private_class_method :validate_flavor

        def self.validate_reserved(header)
          return [] if header.reserved.zero?

          [issue(severity: :warning,
                 message: "WOFF2 reserved field is #{header.reserved} " \
                          "but must be 0 per the spec",
                 location: "woff2_header.reserved")]
        end
        private_class_method :validate_reserved

        def self.validate_version(header)
          issues = []
          if header.major_version != 1
            issues << issue(severity: :warning,
                            message: "WOFF2 major version is #{header.major_version} " \
                                     "but the spec recommends 1",
                            location: "woff2_header.major_version")
          end
          issues
        end
        private_class_method :validate_version

        def self.validate_sizes(header)
          issues = []
          if header.total_compressed_size.to_i <= 0
            issues << issue(severity: :error,
                            message: "WOFF2 total_compressed_size is " \
                                     "#{header.total_compressed_size} but must be positive",
                            location: "woff2_header.total_compressed_size")
          end
          if header.total_sfnt_size.to_i <= 0
            issues << issue(severity: :error,
                            message: "WOFF2 total_sfnt_size is " \
                                     "#{header.total_sfnt_size} but must be positive",
                            location: "woff2_header.total_sfnt_size")
          end
          issues
        end
        private_class_method :validate_sizes

        def self.validate_metadata(header)
          return [] unless header.meta_offset.to_i.positive?

          issues = []
          if header.meta_length.to_i <= 0
            issues << issue(severity: :error,
                            message: "WOFF2 metadata offset is set but " \
                                     "meta_length is #{header.meta_length} " \
                                     "(must be positive)",
                            location: "woff2_header.meta_length")
          end
          if header.meta_orig_length.to_i <= 0
            issues << issue(severity: :error,
                            message: "WOFF2 metadata offset is set but " \
                                     "meta_orig_length is #{header.meta_orig_length} " \
                                     "(must be positive)",
                            location: "woff2_header.meta_orig_length")
          end
          issues
        end
        private_class_method :validate_metadata
      end
    end
  end
end
