# frozen_string_literal: true

require_relative "font_report"
require_relative "validation_report"
require "lutaml/model"

module Fontisan
  module Models
    # CollectionValidationReport aggregates validation results for all fonts
    # in a TTC/OTC/dfont collection.
    #
    # Provides collection-level summary statistics and per-font validation
    # details with clear formatting.
    class CollectionValidationReport < Lutaml::Model::Serializable
      attribute :collection_path, :string
      attribute :collection_type, :string
      attribute :num_fonts, :integer
      attribute :font_reports, FontReport, collection: true,
                                           initialize_empty: true
      attribute :valid, :boolean, default: -> { true }

      key_value do
        map "collection_path", to: :collection_path
        map "collection_type", to: :collection_type
        map "num_fonts", to: :num_fonts
        map "font_reports", to: :font_reports
        map "valid", to: :valid
      end

      # Add a font report to the collection
      #
      # @param font_report [FontReport] The font report to add
      # @return [void]
      def add_font_report(font_report)
        font_reports << font_report
        # Mark that we're no longer using the default value
        value_set_for(:font_reports)
        # Update overall validity
        self.valid = valid && font_report.report.valid?
      end

      # Get overall validation status for the collection
      #
      # @return [String] "valid", "invalid", or "valid_with_warnings"
      def overall_status
        return "invalid" unless font_reports.all? { |fr| fr.report.valid? }
        return "valid_with_warnings" if font_reports.any? do |fr|
          fr.report.has_warnings?
        end

        "valid"
      end

      # Generate text summary with collection header and per-font sections
      #
      # @return [String] Formatted validation report
      def text_summary
        lines = []
        lines << "Collection: #{collection_path}"
        lines << "Type: #{collection_type}"
        lines << "Fonts: #{num_fonts}"
        lines << ""
        lines << "Summary:"
        lines << "  Total Errors: #{total_errors}"
        lines << "  Total Warnings: #{total_warnings}"
        lines << "  Total Info: #{total_info}"

        if font_reports.any?
          lines << ""
          font_reports.each do |font_report|
            lines << "=== Font #{font_report.font_index}: #{font_report.font_name} ==="
            # Indent each line of the font's report
            font_lines = font_report.report.text_summary.split("\n")
            lines.concat(font_lines)
            lines << "" unless font_report == font_reports.last
          end
        end

        lines.join("\n")
      end

      # Calculate total errors across all fonts
      #
      # @return [Integer] Total error count
      def total_errors
        font_reports.sum { |fr| fr.report.summary.errors }
      end

      # Calculate total warnings across all fonts
      #
      # @return [Integer] Total warning count
      def total_warnings
        font_reports.sum { |fr| fr.report.summary.warnings }
      end

      # Calculate total info messages across all fonts
      #
      # @return [Integer] Total info count
      def total_info
        font_reports.sum { |fr| fr.report.summary.info }
      end
    end
  end
end
