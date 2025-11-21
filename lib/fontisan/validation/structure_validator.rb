# frozen_string_literal: true

module Fontisan
  module Validation
    # StructureValidator validates the structural integrity of fonts
    #
    # This validator checks the SFNT structure, table offsets, table ordering,
    # and other structural properties that ensure the font file is well-formed.
    #
    # Single Responsibility: Font structure and SFNT format validation
    #
    # @example Validating structure
    #   validator = StructureValidator.new(rules)
    #   issues = validator.validate(font)
    class StructureValidator
      # Initialize structure validator
      #
      # @param rules [Hash] Validation rules configuration
      def initialize(rules)
        @rules = rules
        @structure_config = rules["structure_validation"] || {}
      end

      # Validate font structure
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font to validate
      # @return [Array<Hash>] Array of validation issues
      def validate(font)
        issues = []

        # Check glyph count consistency
        issues.concat(check_glyph_consistency(font))

        # Check table offsets
        issues.concat(check_table_offsets(font)) if @rules.dig(
          "validation_levels", "standard", "check_table_offsets"
        )

        # Check table ordering (optional optimization check)
        issues.concat(check_table_ordering(font)) if @rules.dig(
          "validation_levels", "standard", "check_table_ordering"
        )

        issues
      end

      private

      # Check glyph count consistency across tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @return [Array<Hash>] Array of consistency issues
      def check_glyph_consistency(font)
        issues = []

        # Get glyph count from maxp table
        maxp = font.table(Constants::MAXP_TAG)
        return issues unless maxp

        expected_count = maxp.num_glyphs

        # For TrueType fonts, check glyf table glyph count
        if font.has_table?(Constants::GLYF_TAG)
          glyf = font.table(Constants::GLYF_TAG)
          actual_count = glyf.glyphs.length if glyf.respond_to?(:glyphs)

          if actual_count && actual_count != expected_count
            issues << {
              severity: "error",
              category: "structure",
              message: "Glyph count mismatch: maxp=#{expected_count}, glyf=#{actual_count}",
              location: "glyf table",
            }
          end
        end

        # Check glyph count bounds with safe defaults
        min_glyph_count = @structure_config["min_glyph_count"] || 1
        max_glyph_count = @structure_config["max_glyph_count"] || 65536

        if expected_count < min_glyph_count
          issues << {
            severity: "error",
            category: "structure",
            message: "Glyph count (#{expected_count}) below minimum (#{min_glyph_count})",
            location: "maxp table",
          }
        end

        if expected_count > max_glyph_count
          issues << {
            severity: "error",
            category: "structure",
            message: "Glyph count (#{expected_count}) exceeds maximum (#{max_glyph_count})",
            location: "maxp table",
          }
        end

        issues
      end

      # Check that table offsets are valid
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @return [Array<Hash>] Array of offset issues
      def check_table_offsets(font)
        issues = []

        min_offset = @structure_config["min_table_offset"] || 12
        max_size = @structure_config["max_table_size"] || 104857600

        font.tables.each do |table_entry|
          tag = table_entry.tag
          offset = table_entry.offset
          length = table_entry.table_length

          # Check minimum offset
          if offset < min_offset
            issues << {
              severity: "error",
              category: "structure",
              message: "Table '#{tag}' has invalid offset: #{offset} (minimum: #{min_offset})",
              location: "#{tag} table directory",
            }
          end

          # Check for reasonable table size
          if length > max_size
            issues << {
              severity: "warning",
              category: "structure",
              message: "Table '#{tag}' has unusually large size: #{length} bytes",
              location: "#{tag} table",
            }
          end

          # Check alignment (tables should be 4-byte aligned)
          alignment = @structure_config["table_alignment"] || 4
          if offset % alignment != 0
            issues << {
              severity: "warning",
              category: "structure",
              message: "Table '#{tag}' is not #{alignment}-byte aligned (offset: #{offset})",
              location: "#{tag} table directory",
            }
          end
        end

        issues
      end

      # Check table ordering (optimization check, not critical)
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @return [Array<Hash>] Array of ordering issues
      def check_table_ordering(font)
        issues = []

        # Recommended table order for optimal loading
        recommended_order = [
          Constants::HEAD_TAG,
          Constants::HHEA_TAG,
          Constants::MAXP_TAG,
          Constants::OS2_TAG,
          Constants::NAME_TAG,
          Constants::CMAP_TAG,
          Constants::POST_TAG,
          Constants::GLYF_TAG,
          Constants::LOCA_TAG,
          Constants::HMTX_TAG,
        ]

        # Get actual table order
        actual_order = font.table_names

        # Check if critical tables are in recommended order
        critical_tables = recommended_order.take(7) # head through post
        actual_critical = actual_order.select do |tag|
          critical_tables.include?(tag)
        end
        expected_critical = critical_tables.select do |tag|
          actual_order.include?(tag)
        end

        if actual_critical != expected_critical
          issues << {
            severity: "info",
            category: "structure",
            message: "Tables not in optimal order for performance",
            location: nil,
          }
        end

        issues
      end
    end
  end
end
