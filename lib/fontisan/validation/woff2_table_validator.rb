# frozen_string_literal: true

require_relative "../woff2/directory"

module Fontisan
  module Validation
    # Woff2TableValidator validates WOFF2 table directory entries
    #
    # This validator checks each table entry for:
    # - Valid tag (known or custom)
    # - Valid transformation version
    # - Transform length consistency
    # - Table size validity
    # - Flags byte correctness
    #
    # Single Responsibility: WOFF2 table directory validation
    #
    # @example Validating WOFF2 tables
    #   validator = Woff2TableValidator.new(rules)
    #   issues = validator.validate(woff2_font)
    class Woff2TableValidator
      # Initialize WOFF2 table validator
      #
      # @param rules [Hash] Validation rules configuration
      def initialize(rules)
        @rules = rules
        @woff2_config = rules["woff2_validation"] || {}
      end

      # Validate WOFF2 table directory
      #
      # @param woff2_font [Woff2Font] The WOFF2 font to validate
      # @return [Array<Hash>] Array of validation issues
      def validate(woff2_font)
        issues = []

        woff2_font.table_entries.each do |entry|
          # Check tag validity
          issues.concat(check_tag(entry))

          # Check flags byte
          issues.concat(check_flags(entry))

          # Check transformation version
          issues.concat(check_transformation(entry))

          # Check table sizes
          issues.concat(check_sizes(entry))
        end

        # Check for duplicate tables
        issues.concat(check_duplicates(woff2_font.table_entries))

        issues
      end

      private

      # Check tag validity
      #
      # @param entry [Woff2TableDirectoryEntry] The table entry
      # @return [Array<Hash>] Array of tag issues
      def check_tag(entry)
        issues = []

        if entry.tag.nil? || entry.tag.empty?
          issues << {
            severity: "error",
            category: "woff2_tables",
            message: "Table entry has nil or empty tag",
            location: "table directory",
          }
        elsif entry.tag.bytesize != 4
          issues << {
            severity: "error",
            category: "woff2_tables",
            message: "Table tag '#{entry.tag}' must be exactly 4 bytes, got #{entry.tag.bytesize}",
            location: entry.tag,
          }
        end

        issues
      end

      # Check flags byte validity
      #
      # @param entry [Woff2TableDirectoryEntry] The table entry
      # @return [Array<Hash>] Array of flags issues
      def check_flags(entry)
        issues = []

        tag_index = entry.flags & 0x3F
        (entry.flags >> 6) & 0x03

        # Check tag index consistency
        if tag_index == Woff2::Directory::CUSTOM_TAG_INDEX
          # Custom tag - should not be in known tags
          if Woff2::Directory::KNOWN_TAGS.include?(entry.tag)
            issues << {
              severity: "warning",
              category: "woff2_tables",
              message: "Table '#{entry.tag}' uses custom tag index but is a known tag",
              location: entry.tag,
            }
          end
        else
          # Known tag - should match index
          expected_tag = Woff2::Directory::KNOWN_TAGS[tag_index]
          if expected_tag && expected_tag != entry.tag
            issues << {
              severity: "error",
              category: "woff2_tables",
              message: "Table tag mismatch: index #{tag_index} should be '#{expected_tag}', got '#{entry.tag}'",
              location: entry.tag,
            }
          end
        end

        issues
      end

      # Check transformation version
      #
      # @param entry [Woff2TableDirectoryEntry] The table entry
      # @return [Array<Hash>] Array of transformation issues
      def check_transformation(entry)
        issues = []

        transform_version = (entry.flags >> 6) & 0x03

        # Check transformation consistency for transformable tables
        case entry.tag
        when "glyf", "loca"
          # glyf/loca: version 0 = transformed (needs transform_length)
          #            version 1-3 = not transformed (no transform_length)
          if transform_version.zero?
            # Should be transformed
            unless entry.transform_length&.positive?
              issues << {
                severity: "error",
                category: "woff2_tables",
                message: "Table '#{entry.tag}' has transform version 0 but no transform_length",
                location: entry.tag,
              }
            end
          elsif entry.transform_length&.positive?
            # Should not be transformed
            issues << {
              severity: "warning",
              category: "woff2_tables",
              message: "Table '#{entry.tag}' has transform version #{transform_version} but has transform_length",
              location: entry.tag,
            }
          end

        when "hmtx"
          # hmtx: version 1 = transformed (needs transform_length)
          #       version 0, 2, 3 = not transformed (no transform_length)
          if transform_version == 1
            # Should be transformed
            unless entry.transform_length&.positive?
              issues << {
                severity: "error",
                category: "woff2_tables",
                message: "Table '#{entry.tag}' has transform version 1 but no transform_length",
                location: entry.tag,
              }
            end
          elsif entry.transform_length&.positive?
            # Should not be transformed
            issues << {
              severity: "warning",
              category: "woff2_tables",
              message: "Table '#{entry.tag}' has transform version #{transform_version} but has transform_length",
              location: entry.tag,
            }
          end

        else
          # Other tables should not be transformed
          if entry.transform_length&.positive?
            issues << {
              severity: "warning",
              category: "woff2_tables",
              message: "Table '#{entry.tag}' is not transformable but has transform_length",
              location: entry.tag,
            }
          end
        end

        issues
      end

      # Check table sizes
      #
      # @param entry [Woff2TableDirectoryEntry] The table entry
      # @return [Array<Hash>] Array of size issues
      def check_sizes(entry)
        issues = []

        # Check orig_length
        if entry.orig_length.nil? || entry.orig_length.zero?
          issues << {
            severity: "error",
            category: "woff2_tables",
            message: "Table '#{entry.tag}' has invalid orig_length: #{entry.orig_length}",
            location: entry.tag,
          }
        end

        # Check transform_length if present
        if entry.transform_length
          if entry.transform_length.zero?
            issues << {
              severity: "warning",
              category: "woff2_tables",
              message: "Table '#{entry.tag}' has transform_length of zero",
              location: entry.tag,
            }
          elsif entry.transform_length > entry.orig_length
            issues << {
              severity: "warning",
              category: "woff2_tables",
              message: "Table '#{entry.tag}' has transform_length (#{entry.transform_length}) " \
                       "greater than orig_length (#{entry.orig_length})",
              location: entry.tag,
            }
          end
        end

        # Check for extremely large tables
        max_table_size = @woff2_config["max_table_size"] || 104_857_600 # 100MB
        if entry.orig_length > max_table_size
          issues << {
            severity: "warning",
            category: "woff2_tables",
            message: "Table '#{entry.tag}' has unusually large size: #{entry.orig_length} bytes",
            location: entry.tag,
          }
        end

        issues
      end

      # Check for duplicate table tags
      #
      # @param entries [Array<Woff2TableDirectoryEntry>] All table entries
      # @return [Array<Hash>] Array of duplicate issues
      def check_duplicates(entries)
        issues = []

        tag_counts = Hash.new(0)
        entries.each { |entry| tag_counts[entry.tag] += 1 }

        tag_counts.each do |tag, count|
          if count > 1
            issues << {
              severity: "error",
              category: "woff2_tables",
              message: "Duplicate table tag '#{tag}' appears #{count} times",
              location: tag,
            }
          end
        end

        issues
      end
    end
  end
end
