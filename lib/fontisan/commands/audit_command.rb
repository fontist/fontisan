# frozen_string_literal: true

require "fileutils"

module Fontisan
  module Commands
    # Produces a complete per-face font audit report.
    #
    # One AuditReport per face. For standalone fonts (TTF/OTF/WOFF/WOFF2),
    # #run returns a single AuditReport. For collections (TTC/OTC/dfont),
    # #run returns an Array<AuditReport> — one per face, in source order.
    #
    # The report is assembled by running every extractor in
    # {Audit::Registry} against an {Audit::Context}. Each extractor
    # owns one concern (provenance, identity, style, coverage,
    # aggregations, …). Adding a new concern means adding one
    # extractor class and one line in the registry — AuditCommand
    # itself never changes.
    class AuditCommand < BaseCommand
      # @return [Models::Audit::AuditReport, Array<Models::Audit::AuditReport>]
      def run
        if FontLoader.collection?(@font_path)
          audit_collection
        else
          audit_face(@font, 0, 1)
        end
      end

      # Write one file per face under `to` (a directory). Pure utility —
      # operates on a pre-built reports array, no font_path required.
      #
      # @param reports [Array<Models::Audit::AuditReport>]
      # @param to [String] output directory; created if missing
      # @param format [Symbol] :yaml or :json
      # @return [Array<String>] written file paths
      def self.write_reports(reports, to:, format: :yaml)
        FileUtils.mkdir_p(to)

        reports.map do |report|
          path = File.join(to, output_filename(report, format))
          content = format == :json ? report.to_json : report.to_yaml
          File.write(path, content)
          path
        end
      end

      # Compute the per-face filename for a report.
      #
      # @param report [Models::Audit::AuditReport]
      # @param format [Symbol] :yaml or :json
      # @return [String] filename only (no directory)
      def self.output_filename(report, format)
        ext = format == :json ? "json" : "yaml"
        base = if report.num_fonts_in_source == 1
                 safe_filename(report.postscript_name || report.family_name || "font")
               else
                 format("%<idx>02d-%<name>s",
                        idx: report.font_index,
                        name: safe_filename(report.postscript_name || "face"))
               end
        "#{base}.#{ext}"
      end

      # Sanitize an arbitrary string into a filesystem-safe basename.
      #
      # @param name [String, nil]
      # @return [String]
      def self.safe_filename(name)
        return "font" if name.nil? || name.empty?

        name.gsub(/[^A-Za-z0-9._-]/, "_")
      end

      private

      def audit_collection
        collection = FontLoader.load_collection(@font_path)
        num = collection.num_fonts
        Array.new(num) do |index|
          font = FontLoader.load(@font_path, font_index: index,
                                             mode: LoadingModes::FULL)
          audit_face(font, index, num)
        end
      end

      def audit_face(font, font_index, num_fonts_in_source)
        context = Audit::Context.new(
          font: font,
          font_path: @font_path,
          font_index: font_index,
          num_fonts_in_source: num_fonts_in_source,
          options: @options,
        )

        fields = {}
        Audit::Registry.each do |extractor_class|
          fields.merge!(extractor_class.new.extract(context))
        end

        fields[:warning] = context.ucd[:warning]

        Models::Audit::AuditReport.new(**fields)
      end
    end
  end
end
