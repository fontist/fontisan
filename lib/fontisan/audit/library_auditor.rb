# frozen_string_literal: true

require "pathname"

module Fontisan
  module Audit
    # Orchestrates a library-wide audit pass.
    #
    # Owns the file-system side: discovers font files under a root path
    # (recursively or not), audits each via {Commands::AuditCommand},
    # and assembles a {Models::Audit::LibrarySummary} combining the
    # per-face reports with cross-face rollups from {LibraryAggregator}.
    #
    # Aggregation logic lives in the pure {LibraryAggregator}; this
    # class stays focused on discovery + per-face auditing + summary
    # assembly. Errors auditing a single file are logged and skipped so
    # a corrupt file doesn't abort the whole pass.
    class LibraryAuditor
      FONT_EXTENSIONS = %w[.ttf .otf .ttc .otc .dfont .woff .woff2
                           .pfb .pfa .svg].freeze

      # @param root_path [String, Pathname] directory containing fonts
      # @param recursive [Boolean] walk into subdirectories
      # @param options [Hash] forwarded to AuditCommand (minus library-only keys)
      def initialize(root_path, recursive:, options:)
        @root_path = Pathname.new(root_path)
        @recursive = recursive
        @options = options
        @aggregator = LibraryAggregator.new
        @skipped = []
      end

      # @return [Models::Audit::LibrarySummary]
      def audit
        paths = discover_font_paths
        reports = paths.flat_map { |p| audit_one(p) }
        rolled_up = aggregates(reports)

        Models::Audit::LibrarySummary.new(
          root_path: @root_path.to_s,
          total_files: paths.size,
          total_faces: reports.size,
          scanned_extensions: scanned_extensions(paths),
          aggregate_metrics: rolled_up[:aggregate_metrics].merge(
            total_size_bytes: paths.sum { |p| File.size(p) },
          ),
          script_coverage: rolled_up[:script_coverage],
          duplicate_groups: rolled_up[:duplicate_groups],
          license_distribution: rolled_up[:license_distribution],
          per_face_reports: reports,
        )
      end

      # @return [Array<String>] source files that could not be audited
      attr_reader :skipped

      private

      def discover_font_paths
        method = @recursive ? :find : :children
        @root_path.public_send(method).select do |entry|
          next false unless entry.file?
          next false if entry.symlink?

          FONT_EXTENSIONS.include?(entry.extname.downcase)
        end.map(&:to_s).sort
      end

      def audit_one(path)
        Array(Commands::AuditCommand.new(path, audit_options).run)
      rescue StandardError => e
        @skipped << "#{path}: #{e.message}"
        []
      end

      # Drop library-only options before forwarding to AuditCommand.
      def audit_options
        @options.except(:recursive, :summary, :output)
      end

      def scanned_extensions(paths)
        paths.map { |p| File.extname(p).downcase }.uniq.sort
      end

      def aggregates(reports)
        @aggregator.aggregate(reports)
      end
    end
  end
end
