# frozen_string_literal: true

module Fontisan
  module Commands
    # Diffs two faces or two saved audit reports.
    #
    # Each input is one of:
    #   - A path to a `.yaml`/`.json` file previously written by
    #     `fontisan audit -o`. Loaded as an AuditReport.
    #   - A path to a font file. Audited on-the-fly via AuditCommand.
    #
    # Returns an {Models::Audit::AuditDiff}. The CLI renders it as
    # YAML/JSON (text formatter lands in TODO 25).
    #
    # Mixed inputs are allowed (font vs. saved report), which is useful
    # for tracking a font's evolution against a checked-in baseline.
    class AuditCompareCommand
      # @param left_path [String] path to font file or saved report
      # @param right_path [String] path to font file or saved report
      # @param options [Hash] forwarded to AuditCommand for any input
      #   that needs to be audited fresh
      def initialize(left_path, right_path, options = {})
        @left_path = left_path
        @right_path = right_path
        @options = options
      end

      # @return [Models::Audit::AuditDiff]
      def run
        left_report = load_report(@left_path)
        right_report = load_report(@right_path)
        Audit::Differ.new(left_report, right_report).diff
      end

      private

      def load_report(path)
        if saved_report?(path)
          load_saved_report(path)
        else
          AuditCommand.new(path, audit_options).run
        end
      end

      def saved_report?(path)
        ext = File.extname(path).downcase
        [".yaml", ".yml", ".json"].include?(ext)
      end

      def load_saved_report(path)
        case File.extname(path).downcase
        when ".json"
          Models::Audit::AuditReport.from_json(File.read(path))
        else
          Models::Audit::AuditReport.from_yaml(File.read(path))
        end
      end

      # Forward only the audit-relevant options when auditing fresh fonts.
      # Drops `--compare` (consumed here) and `--output` (no file output).
      def audit_options
        @options.except(:compare, :output)
      end
    end
  end
end
