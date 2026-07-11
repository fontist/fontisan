# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates variable-font readiness: fvar axis invariants, named
      # instances within ranges, companion-table presence (gvar for
      # TrueType outlines, HVAR for horizontal metrics, STAT for OS
      # style matching). Ports the most commonly-hit fontbakery GF-VF
      # check subset.
      #
      # Only runs when the font HAS an fvar table — static fonts are
      # skipped (returns empty issues array).
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/fvar
      class VariableFontCheck < Check
        # @param font [SfntFont]
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          return [] unless font.has_table?("fvar")

          issues = []
          issues.concat(validate_axes(font))
          issues.concat(validate_instances(font))
          issues.concat(validate_companion_tables(font))
          issues
        end

        def self.code
          :variable_font
        end

        # ---------- fvar axes ----------

        def self.validate_axes(font)
          fvar = font.table("fvar")
          axes = fvar.axes
          issues = []

          issues.concat(check_axis_uniqueness(axes))
          axes.each_with_index { |axis, idx| issues.concat(check_one_axis(axis, idx)) }
          issues
        end
        private_class_method :validate_axes

        def self.check_axis_uniqueness(axes)
          tags = axes.map(&:axis_tag)
          duplicates = tags.tally.filter_map { |t, c| t if c > 1 }
          duplicates.map do |tag|
            issue(severity: :error,
                  message: "Duplicate fvar axis tag '#{tag}' — axis tags " \
                           "must be unique within a font",
                  location: "fvar.axes.#{tag}")
          end
        end
        private_class_method :check_axis_uniqueness

        def self.check_one_axis(axis, idx)
          issues = []
          min_v = axis.min_value.to_f
          default_v = axis.default_value.to_f
          max_v = axis.max_value.to_f

          unless min_v <= default_v && default_v <= max_v
            issues << issue(severity: :error,
                            message: "fvar axis '#{axis.axis_tag}' (#{idx}) has " \
                                     "invalid range: min=#{min_v} " \
                                     "default=#{default_v} max=#{max_v} " \
                                     "(must be min ≤ default ≤ max)",
                            location: "fvar.axes.#{idx}")
          end

          if axis.axis_name_id.to_i.zero?
            issues << issue(severity: :warning,
                            message: "fvar axis '#{axis.axis_tag}' (#{idx}) has " \
                                     "no name ID — users cannot identify the axis",
                            location: "fvar.axes.#{idx}.axis_name_id")
          end

          issues
        end
        private_class_method :check_one_axis

        # ---------- fvar named instances ----------

        def self.validate_instances(font)
          fvar = font.table("fvar")
          instances = fvar.instances || []
          axes = fvar.axes

          instances.each_with_index.with_object([]) do |(inst, idx), issues|
            issues.concat(check_instance_ranges(inst, idx, axes))
          end
        end
        private_class_method :validate_instances

        def self.check_instance_ranges(inst, idx, axes)
          issues = []
          coords = inst[:coordinates] || inst["coordinates"] || []
          coords.each_with_index do |coord, axis_idx|
            next unless axes[axis_idx]

            axis = axes[axis_idx]
            min_v = axis.min_value.to_f
            max_v = axis.max_value.to_f
            next if coord.to_f.between?(min_v, max_v)

            issues << issue(severity: :warning,
                            message: "fvar instance #{idx} has coordinate " \
                                     "#{coord} for axis '#{axis.axis_tag}' " \
                                     "outside its range [#{min_v}, #{max_v}]",
                            location: "fvar.instances.#{idx}.#{axis.axis_tag}")
          end
          issues
        end
        private_class_method :check_instance_ranges

        # ---------- companion tables ----------

        def self.validate_companion_tables(font)
          issues = []
          is_truetype = font.has_table?("glyf")
          if is_truetype && !font.has_table?("gvar")
            issues << issue(severity: :warning,
                            message: "Variable TrueType font has no 'gvar' table — " \
                                     "glyph outlines won't vary across the design space",
                            location: "tables.gvar")
          end

          unless font.has_table?("HVAR")
            issues << issue(severity: :warning,
                            message: "Variable font has no 'HVAR' table — " \
                                     "advance widths won't vary; renderers must " \
                                     "fall back to per-glyph hmtx lookups",
                            location: "tables.HVAR")
          end

          unless font.has_table?("STAT")
            issues << issue(severity: :info,
                            message: "Variable font has no 'STAT' table — " \
                                     "OS style-matching won't work; Windows and " \
                                     "modern font pickers rely on STAT",
                            location: "tables.STAT")
          end
          issues
        end
        private_class_method :validate_companion_tables
      end
    end
  end
end
