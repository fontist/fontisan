# frozen_string_literal: true

module Fontisan
  module Commands
    # Audits every font in a directory (tree) and rolls the per-face
    # reports up into a {Models::Audit::LibrarySummary}.
    #
    # Thin wrapper over {Audit::LibraryAuditor}: validates the root
    # path exists, delegates to the auditor, returns the summary.
    # The auditor itself owns file discovery and per-face auditing;
    # this command is the CLI-facing boundary that maps user-facing
    # options onto auditor inputs.
    class AuditLibraryCommand
      # @param root_path [String] directory containing fonts
      # @param recursive [Boolean] walk into subdirectories
      # @param options [Hash] forwarded to AuditCommand for each face
      def initialize(root_path, recursive:, options:)
        @root_path = root_path
        @recursive = recursive
        @options = options
      end

      # @return [Models::Audit::LibrarySummary]
      def run
        raise Error, "library audit requires an existing directory: #{@root_path}" unless Dir.exist?(@root_path)

        auditor.audit
      end

      # @return [Array<String>] files skipped during the audit pass
      def skipped
        auditor.skipped
      end

      private

      def auditor
        @auditor ||= Audit::LibraryAuditor.new(
          @root_path,
          recursive: @recursive,
          options: @options,
        )
      end
    end
  end
end
